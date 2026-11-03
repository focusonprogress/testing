--[[
	DataService — carrega e salva o progresso dos jogadores com DataStore.

	No Studio: Game Settings > Security > "Enable Studio Access to API Services"
	precisa estar ligado para salvar. Se estiver desligado, o jogo funciona
	normalmente, só não salva (aparece um aviso no Output).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Acha um filho pelo nome, ignorando espaços sobrando e maiúsculas/minúsculas
local function findChild(parent: Instance, name: string): Instance
	local target = name:lower()
	local started = os.clock()
	local warned = false
	while true do
		for _, child in ipairs(parent:GetChildren()) do
			local clean = child.Name:gsub("^%s+", ""):gsub("%s+$", "")
			if clean:lower() == target then
				return child
			end
		end
		if not warned and os.clock() - started > 5 then
			warned = true
			warn(("[Progression] Esperando '%s' dentro de %s... confira se ele existe e está no lugar certo."):format(name, parent:GetFullName()))
		end
		task.wait(0.1)
	end
end

local Config = require(findChild(findChild(ReplicatedStorage, "Shared"), "Config"))

local DataService = {}

local profiles: { [Player]: any } = {}

local storeOk, store = pcall(function()
	return DataStoreService:GetDataStore(Config.DataStoreName)
end)
if not storeOk then
	warn("[DataService] DataStore indisponível, o progresso NÃO será salvo:", store)
	store = nil
end

local function template()
	return {
		Coins = Config.StartingCoins,
		XP = 0,
		Level = 1,
		Kills = 0,
		Deaths = 0,
		Wins = 0,
		BestStreak = 0,
		Owned = {}, -- [itemId] = true
		Equipped = "", -- itemId ou ""
		Achievements = {}, -- [achievementId] = true
	}
end

-- Adiciona campos novos em saves antigos (quando você criar stats novos depois)
local function reconcile(data)
	for key, value in pairs(template()) do
		if data[key] == nil then
			data[key] = value
		end
	end
	return data
end

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

local function withRetries(label: string, fn: () -> any): (boolean, any)
	local lastErr
	local maxAttempts = RunService:IsStudio() and 1 or 4 -- no Studio falha rápido
	for attempt = 1, maxAttempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		warn(("[DataService] %s falhou (tentativa %d): %s"):format(label, attempt, tostring(result)))
		if attempt < maxAttempts then
			task.wait(2 ^ attempt)
		end
	end
	return false, lastErr
end

function DataService.Load(player: Player)
	if not store then
		profiles[player] = template()
		return profiles[player]
	end

	local ok, result = withRetries("Load " .. player.Name, function()
		return store:GetAsync(keyFor(player))
	end)

	if not ok and RunService:IsStudio() then
		warn("[DataService] Sem acesso ao DataStore no Studio: jogando SEM salvar. Ligue 'Enable Studio Access to API Services' em Game Settings > Security.")
		store = nil
		profiles[player] = template()
		return profiles[player]
	end
	if not ok then
		-- Melhor expulsar do que deixar jogar e sobrescrever o save com dados zerados
		player:Kick("Não conseguimos carregar seu progresso. Entre de novo em alguns instantes!")
		return nil
	end
	if not player.Parent then
		return nil -- saiu enquanto carregava
	end

	local data = reconcile(type(result) == "table" and result or template())
	profiles[player] = data
	return data
end

function DataService.Get(player: Player)
	return profiles[player]
end

function DataService.Save(player: Player)
	local data = profiles[player]
	if not data or not store then
		return
	end
	withRetries("Save " .. player.Name, function()
		store:UpdateAsync(keyFor(player), function()
			return data
		end)
	end)
end

function DataService.Release(player: Player)
	DataService.Save(player)
	profiles[player] = nil
end

-- Autosave
task.spawn(function()
	while true do
		task.wait(Config.AutosaveInterval)
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(DataService.Save, player)
		end
	end
end)

-- Salva todo mundo quando o servidor fecha
game:BindToClose(function()
	local pending = 0
	for _, player in ipairs(Players:GetPlayers()) do
		pending += 1
		task.spawn(function()
			DataService.Save(player)
			pending -= 1
		end)
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < 25 do
		task.wait(0.1)
	end
end)

return DataService
