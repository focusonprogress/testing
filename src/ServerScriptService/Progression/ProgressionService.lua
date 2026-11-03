--[[
	ProgressionService — XP, níveis, títulos, moedas, kills, vitórias,
	conquistas e loja.

	Para usar de outros scripts do servidor (ex.: o sistema de rodadas):
		local Progression = require(game.ServerScriptService.Progression.ProgressionService)
		Progression.AddWin(player)                 -- time do jogador venceu
		Progression.Reward(player, 50, 20, "Bônus") -- XP, moedas, motivo

	As kills já são contadas sozinhas pela tag "creator" que as armas
	clássicas (espada, foguete, bomba, estilingue) colocam no Humanoid.
]]

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RGB = require(Shared:WaitForChild("RGB"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local GearService = require(script.Parent:WaitForChild("GearService"))

local Progression = {}

local remotes: { [string]: any } = {}
local session: { [Player]: { Streak: number, LastRequest: number } } = {}

---------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------
local function createRemotes()
	local folder = Instance.new("Folder")
	folder.Name = "ProgressionRemotes"

	for _, name in ipairs({ "DataChanged", "Notify" }) do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		remotes[name] = remote
	end
	for _, name in ipairs({ "RequestData", "BuyItem", "EquipItem" }) do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = folder
		remotes[name] = remote
	end

	folder.Parent = ReplicatedStorage
end

local function notify(player: Player, kind: string, payload)
	if remotes.Notify then
		remotes.Notify:FireClient(player, kind, payload)
	end
end

---------------------------------------------------------------------
-- Leaderstats + título em cima da cabeça
---------------------------------------------------------------------
local function createLeaderstats(player: Player, data)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	for _, info in ipairs({
		{ "Nível", data.Level },
		{ "Kills", data.Kills },
		{ "Vitórias", data.Wins },
	}) do
		local value = Instance.new("IntValue")
		value.Name = info[1]
		value.Value = info[2]
		value.Parent = leaderstats
	end

	leaderstats.Parent = player
end

local function updateLeaderstats(player: Player, data)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	leaderstats["Nível"].Value = data.Level
	leaderstats.Kills.Value = data.Kills
	leaderstats["Vitórias"].Value = data.Wins
end

local function teamColor(player: Player): Color3
	if player.Team and not player.Neutral then
		return player.TeamColor.Color
	end
	return Color3.new(0, 0, 0)
end

local function updateOverhead(player: Player, data)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local overhead = head and head:FindFirstChild("Overhead")
	if not overhead then
		return
	end
	overhead.TitleLabel.Text = ("Nv. %d • %s"):format(data.Level, Config.GetTitle(data.Level))
	overhead.NameLabel.UIStroke.Color = teamColor(player)
end

local function buildOverhead(player: Player, character: Model)
	local head = character:WaitForChild("Head", 10)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not head or not humanoid then
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	local old = head:FindFirstChild("Overhead")
	if old then
		old:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Overhead"
	billboard.Size = UDim2.fromOffset(240, 58)
	billboard.StudsOffset = Vector3.new(0, 2.7, 0)
	billboard.MaxDistance = 90
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.fromScale(1, 0.58)
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextScaled = true
	nameLabel.Text = player.DisplayName
	local nameStroke = Instance.new("UIStroke")
	nameStroke.Thickness = 2.5
	nameStroke.Color = teamColor(player) -- contorno na cor do time
	nameStroke.Parent = nameLabel
	nameLabel.Parent = billboard
	RGB.Apply(nameLabel, "Gradient")

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.fromScale(0, 0.58)
	titleLabel.Size = UDim2.fromScale(1, 0.42)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextScaled = true
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Thickness = 1.5
	titleStroke.Parent = titleLabel
	titleLabel.Parent = billboard
	RGB.Apply(titleLabel, "Rainbow", 0.35)

	billboard.Parent = head

	local data = DataService.Get(player)
	if data then
		updateOverhead(player, data)
	end
end

---------------------------------------------------------------------
-- Sincronizar com o cliente
---------------------------------------------------------------------
local function publicData(data)
	return {
		Coins = data.Coins,
		XP = data.XP,
		XPNeeded = Config.XPForLevel(data.Level),
		Level = data.Level,
		MaxLevel = Config.MaxLevel,
		Title = Config.GetTitle(data.Level),
		Kills = data.Kills,
		Deaths = data.Deaths,
		Wins = data.Wins,
		BestStreak = data.BestStreak,
		Owned = data.Owned,
		Equipped = data.Equipped,
		Achievements = data.Achievements,
	}
end

local function sync(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	updateLeaderstats(player, data)
	updateOverhead(player, data)
	if remotes.DataChanged then
		remotes.DataChanged:FireClient(player, publicData(data))
	end
end

---------------------------------------------------------------------
-- Conquistas
---------------------------------------------------------------------
local function statValue(data, stat: string): number
	if stat == "OwnedCount" then
		local count = 0
		for _ in pairs(data.Owned) do
			count += 1
		end
		return count
	end
	return data[stat] or 0
end

local function checkAchievements(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	for _, achievement in ipairs(Config.Achievements) do
		if not data.Achievements[achievement.Id] and statValue(data, achievement.Stat) >= achievement.Goal then
			data.Achievements[achievement.Id] = true
			data.Coins += achievement.Coins
			notify(player, "Achievement", {
				Name = achievement.Name,
				Description = achievement.Description,
				Coins = achievement.Coins,
			})
			if achievement.BadgeId and achievement.BadgeId > 0 then
				task.spawn(function()
					local ok, err = pcall(function()
						BadgeService:AwardBadge(player.UserId, achievement.BadgeId)
					end)
					if not ok then
						warn("[Progression] Falha ao dar badge:", err)
					end
				end)
			end
		end
	end
end

---------------------------------------------------------------------
-- API pública
---------------------------------------------------------------------
function Progression.AddXP(player: Player, amount: number)
	local data = DataService.Get(player)
	if not data or data.Level >= Config.MaxLevel then
		return
	end

	local oldTitle = Config.GetTitle(data.Level)
	local oldLevel = data.Level
	data.XP += amount

	while data.Level < Config.MaxLevel and data.XP >= Config.XPForLevel(data.Level) do
		data.XP -= Config.XPForLevel(data.Level)
		data.Level += 1
	end
	if data.Level >= Config.MaxLevel then
		data.XP = 0
	end

	if data.Level > oldLevel then
		local newTitle = Config.GetTitle(data.Level)
		notify(player, "LevelUp", {
			Level = data.Level,
			Title = newTitle,
			NewTitle = newTitle ~= oldTitle,
		})
	end
end

-- Dá XP e moedas de uma vez, mostra o "+X" na tela e salva no estado
function Progression.Reward(player: Player, xp: number, coins: number, reason: string?)
	local data = DataService.Get(player)
	if not data then
		return
	end
	data.Coins += coins
	Progression.AddXP(player, xp)
	notify(player, "Reward", { XP = xp, Coins = coins, Reason = reason })
	checkAchievements(player)
	sync(player)
end

function Progression.AddKill(killer: Player, victim: Player?)
	local data = DataService.Get(killer)
	if not data or killer == victim then
		return
	end
	-- sem pontos por matar alguém do próprio time
	if victim and killer.Team and victim.Team == killer.Team and not killer.Neutral then
		return
	end

	data.Kills += 1
	local state = session[killer]
	local streak = 0
	if state then
		state.Streak += 1
		streak = state.Streak
		if streak > data.BestStreak then
			data.BestStreak = streak
		end
	end

	local coins = Config.Rewards.Kill.Coins
	local reason = victim and ("Eliminou " .. victim.DisplayName) or "Kill"
	if streak >= Config.Rewards.StreakBonusFrom then
		coins += Config.Rewards.StreakBonusCoins
		reason = ("Sequência de %d! 🔥"):format(streak)
	end

	Progression.Reward(killer, Config.Rewards.Kill.XP, coins, reason)
end

function Progression.AddDeath(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	data.Deaths += 1
	if session[player] then
		session[player].Streak = 0
	end
	sync(player)
end

function Progression.AddWin(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	data.Wins += 1
	Progression.Reward(player, Config.Rewards.Win.XP, Config.Rewards.Win.Coins, "Vitória! 🏆")
end

---------------------------------------------------------------------
-- Loja
---------------------------------------------------------------------
local function rateLimited(player: Player): boolean
	local state = session[player]
	if not state then
		return true
	end
	local now = os.clock()
	if now - state.LastRequest < 0.3 then
		return true
	end
	state.LastRequest = now
	return false
end

local function buyItem(player: Player, itemId: any)
	if type(itemId) ~= "string" or rateLimited(player) then
		return false, "Calma aí!"
	end
	local item = Config.GetShopItem(itemId)
	if not item then
		return false, "Item inválido."
	end
	-- Pode demorar (carrega o gear), por isso vem antes de mexer nos dados
	if not GearService.IsAvailable(item) then
		return false, "Esse item chega em breve!"
	end

	local data = DataService.Get(player)
	if not data then
		return false, "Seus dados ainda estão carregando."
	end
	if data.Owned[itemId] then
		return false, "Você já tem esse item."
	end
	if data.Level < item.MinLevel then
		return false, ("Precisa do nível %d."):format(item.MinLevel)
	end
	if data.Coins < item.Price then
		return false, "Moedas insuficientes."
	end

	data.Coins -= item.Price
	data.Owned[itemId] = true
	data.Equipped = itemId
	GearService.Give(player, itemId)

	checkAchievements(player)
	sync(player)
	return true, ("Você comprou %s!"):format(item.Name)
end

local function equipItem(player: Player, itemId: any)
	if type(itemId) ~= "string" or rateLimited(player) then
		return false, "Calma aí!"
	end
	local data = DataService.Get(player)
	if not data then
		return false, "Seus dados ainda estão carregando."
	end
	if itemId ~= "" and not data.Owned[itemId] then
		return false, "Você não tem esse item."
	end

	data.Equipped = itemId
	GearService.Give(player, itemId)
	sync(player)
	return true, itemId == "" and "Gear guardado." or "Gear equipado!"
end

---------------------------------------------------------------------
-- Jogadores
---------------------------------------------------------------------
local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	task.spawn(buildOverhead, player, character)

	local data = DataService.Get(player)
	if data and data.Equipped ~= "" then
		GearService.Give(player, data.Equipped)
	end

	humanoid.Died:Connect(function()
		Progression.AddDeath(player)
		local tag = humanoid:FindFirstChild("creator")
		local killer = tag and tag:IsA("ObjectValue") and tag.Value
		if killer and killer:IsA("Player") and killer.Parent then
			Progression.AddKill(killer, player)
		end
	end)
end

local function onPlayerAdded(player: Player)
	session[player] = { Streak = 0, LastRequest = 0 }

	local data = DataService.Load(player)
	if not data or not player.Parent then
		session[player] = nil
		return
	end

	createLeaderstats(player, data)
	checkAchievements(player) -- libera conquistas novas para saves antigos

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end

	player:GetPropertyChangedSignal("Team"):Connect(function()
		local current = DataService.Get(player)
		if current then
			updateOverhead(player, current)
		end
	end)

	sync(player)
end

local function onPlayerRemoving(player: Player)
	DataService.Release(player)
	session[player] = nil
end

local initialized = false

function Progression.Init()
	if initialized then
		return
	end
	initialized = true

	createRemotes()
	GearService.Preload()

	remotes.RequestData.OnServerInvoke = function(player)
		local data = DataService.Get(player)
		return data and publicData(data), GearService.GetAvailableIds()
	end
	remotes.BuyItem.OnServerInvoke = buyItem
	remotes.EquipItem.OnServerInvoke = equipItem

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

return Progression
