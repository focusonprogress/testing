--[[
	RoundService — ciclo de rodadas:

		Aguardando jogadores -> Intermissão (votação, mapa reconstruído)
		-> Partida (eventos, encolhimento, morte súbita) -> Fim (vencedor, recompensas)

	Ele controla o respawn (Players.CharacterAutoLoads = false), então
	desligue outros scripts que fazem rodada/respawn/regen do mapa
	(ex.: GameControl e RegenControl do Doomspire).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Teams = game:GetService("Teams")

local function findChild(parent: Instance, name: string, timeout: number?): Instance?
	local target = name:lower()
	local started = os.clock()
	while true do
		for _, child in ipairs(parent:GetChildren()) do
			local clean = child.Name:gsub("^%s+", ""):gsub("%s+$", "")
			if clean:lower() == target then
				return child
			end
		end
		if timeout and os.clock() - started > timeout then
			return nil
		end
		task.wait(0.1)
	end
end

local Shared = findChild(ReplicatedStorage, "Shared") :: Instance
local RoundConfig = require(findChild(Shared, "RoundConfig") :: any)
local MapService = require(findChild(script.Parent, "MapService") :: any)
local Events = require(findChild(script.Parent, "Events") :: any)

-- Progressão é opcional: se existir, dá vitórias/recompensas
local Progression = nil
task.spawn(function()
	local folder = findChild(ServerScriptService, "Progression", 10)
	local module = folder and findChild(folder, "ProgressionService", 5)
	if module then
		Progression = require(module :: any)
	else
		warn("[Rounds] ProgressionService não encontrado: rodadas sem recompensas.")
	end
end)

local RoundService = {}

---------------------------------------------------------------------
-- Estado
---------------------------------------------------------------------
local phase = "Waiting"
local mode = RoundConfig.Modes[1]
local teamsMode = true
local suddenDeath = false
local roundStartedAt = 0

local votes: { [Player]: string } = {}
local participants: { [Player]: boolean } = {}
local eliminated: { [Player]: boolean } = {}
local lives: { [Player]: number } = {}
local roundKills: { [Player]: number } = {}

local activeEvents: { [string]: any } = {} -- [id] = { Handle, EndsAt, Random }
local swordsOverride = false

local stateFolder: Folder
local remotes: { [string]: any } = {}

local stashRoot = Instance.new("Folder")
stashRoot.Name = "RoundToolStash"
stashRoot.Parent = ServerStorage

---------------------------------------------------------------------
-- Replicação (atributos em ReplicatedStorage.RoundState)
---------------------------------------------------------------------
local function setState(key: string, value: any)
	stateFolder:SetAttribute(key, value)
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function announce(kind: string, payload: any)
	remotes.Announce:FireAllClients(kind, payload)
end

local function info(text: string)
	announce("Info", { Text = text })
end

local function publishVotes()
	local counts = {}
	for _, modeId in pairs(votes) do
		counts[modeId] = (counts[modeId] or 0) + 1
	end
	setState("Votes", HttpService:JSONEncode(counts))
end

local function publishEvents()
	local list = {}
	for id, active in pairs(activeEvents) do
		table.insert(list, { Id = id, EndsAt = active.EndsAt })
	end
	setState("Events", HttpService:JSONEncode(list))
end

---------------------------------------------------------------------
-- Jogadores vivos / times
---------------------------------------------------------------------
local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function isAlive(player: Player): boolean
	local humanoid = getHumanoid(player)
	return humanoid ~= nil and humanoid.Health > 0
end

local function aliveList()
	local result = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = getHumanoid(player)
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 then
			table.insert(result, { Player = player, Character = character, Humanoid = humanoid, Root = root })
		end
	end
	return result
end

-- Times que têm pelo menos uma torre (SpawnLocation do time) no mapa
local function towerTeams(): { Team }
	local result = {}
	for _, team in ipairs(Teams:GetTeams()) do
		if #MapService.GetTeamSpawns(team) > 0 then
			table.insert(result, team)
		end
	end
	return result
end

local function canRespawn(player: Player): boolean
	if not player.Parent then
		return false
	end
	if phase ~= "Playing" then
		return true
	end
	if not participants[player] or eliminated[player] or suddenDeath then
		return false
	end
	if mode.Lives then
		return (lives[player] or 0) > 0
	end
	if teamsMode then
		return player.Team ~= nil and #MapService.GetTeamSpawns(player.Team) > 0
	end
	return true
end

local function inGame(player: Player): boolean
	return participants[player] == true
		and player.Parent ~= nil
		and not eliminated[player]
		and (isAlive(player) or canRespawn(player))
end

-- Quem ainda está na disputa: lista de times (modo times) ou de jogadores (FFA)
local function standing(): { any }
	local result = {}
	if teamsMode then
		local seen = {}
		for player in pairs(participants) do
			if inGame(player) and player.Team and not seen[player.Team] then
				seen[player.Team] = true
				table.insert(result, player.Team)
			end
		end
	else
		for player in pairs(participants) do
			if inGame(player) then
				table.insert(result, player)
			end
		end
	end
	return result
end

local function publishTeams()
	local list = {}
	if teamsMode then
		for _, team in ipairs(Teams:GetTeams()) do
			local total, alive = 0, 0
			for _, player in ipairs(team:GetPlayers()) do
				if participants[player] or phase ~= "Playing" then
					total += 1
					if isAlive(player) then
						alive += 1
					end
				end
			end
			if total > 0 then
				table.insert(list, {
					Name = team.Name,
					Color = team.TeamColor.Color:ToHex(),
					Alive = alive,
					Total = total,
					Tower = #MapService.GetTeamSpawns(team) > 0,
				})
			end
		end
	end
	setState("Teams", HttpService:JSONEncode(list))

	local left = 0
	for player in pairs(participants) do
		if inGame(player) then
			left += 1
		end
	end
	setState("PlayersLeft", left)
end

-- Compatibilidade com a interface do jogo (Remotes.ChangeTeam / RequestSpectator)
local function gameRemote(name: string): RemoteEvent?
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = folder and folder:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	return nil
end

local function notifyTeamChange(player: Player)
	local remote = gameRemote("ChangeTeam")
	if remote then
		remote:FireClient(player, player.TeamColor)
	end
end

local function assignTeams()
	local teams = towerTeams()
	local players = Players:GetPlayers()
	-- embaralha
	for i = #players, 2, -1 do
		local j = math.random(1, i)
		players[i], players[j] = players[j], players[i]
	end

	if not mode.Teams or #teams == 0 then
		if mode.Teams then
			warn("[Rounds] Nenhum SpawnLocation de time no mapa: jogando sem times.")
		end
		teamsMode = false
		for _, player in ipairs(players) do
			player.Neutral = true
			player.Team = nil
		end
		return
	end

	teamsMode = true
	for index, player in ipairs(players) do
		player.Neutral = false
		player.Team = teams[((index - 1) % #teams) + 1]
		notifyTeamChange(player)
	end
end

-- Coloca quem entrou no meio da partida no time com menos gente (que ainda tem torre)
local function assignLateJoiner(player: Player)
	if not teamsMode then
		player.Neutral = true
		return
	end
	local best, bestCount = nil, math.huge
	for _, team in ipairs(towerTeams()) do
		local count = #team:GetPlayers()
		if count < bestCount then
			best, bestCount = team, count
		end
	end
	if best then
		player.Neutral = false
		player.Team = best
		notifyTeamChange(player)
	end
end

---------------------------------------------------------------------
-- Armas (intermissão sem armas, modo/evento só espadas)
---------------------------------------------------------------------
local function toolPolicy(): string
	if phase == "Intermission" then
		return "None"
	end
	if phase == "Playing" and (mode.SwordsOnly or swordsOverride) then
		return "Swords"
	end
	return "All"
end

local function isSword(tool: Tool): boolean
	if tool:GetAttribute("ShopGearId") then
		return true
	end
	local name = tool.Name:lower()
	for _, keyword in ipairs(RoundConfig.SwordKeywords) do
		if name:find(keyword, 1, true) then
			return true
		end
	end
	return false
end

local function allowed(tool: Tool, policy: string): boolean
	return policy == "All" or (policy == "Swords" and isSword(tool))
end

local function getStash(player: Player): Folder
	local key = tostring(player.UserId)
	local folder = stashRoot:FindFirstChild(key)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = key
		folder.Parent = stashRoot
	end
	return folder :: Folder
end

local function filterTool(player: Player, tool: Instance)
	if tool:IsA("Tool") and tool.Parent ~= nil and not allowed(tool, toolPolicy()) then
		tool.Parent = getStash(player)
	end
end

local function applyToolPolicy(player: Player)
	local policy = toolPolicy()
	local backpack = player:FindFirstChildOfClass("Backpack")
	local containers = { backpack, player.Character }

	local have = {}
	for _, container in ipairs(containers) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") then
					if allowed(child, policy) then
						have[child.Name] = true
					else
						child.Parent = getStash(player)
					end
				end
			end
		end
	end

	-- devolve o que voltou a ser permitido
	if backpack then
		for _, tool in ipairs(getStash(player):GetChildren()) do
			if tool:IsA("Tool") and allowed(tool, policy) and not have[tool.Name] then
				have[tool.Name] = true
				tool.Parent = backpack
			end
		end
	end
end

local function applyToolPolicyAll()
	for _, player in ipairs(Players:GetPlayers()) do
		applyToolPolicy(player)
	end
end

local function watchTools(player: Player)
	local function watch(container: Instance)
		container.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				task.defer(filterTool, player, child)
			end
		end)
	end
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			watch(child)
		end
	end)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		watch(backpack)
	end
	player.CharacterAdded:Connect(watch)
	if player.Character then
		watch(player.Character)
	end
end

---------------------------------------------------------------------
-- Spawn / morte
---------------------------------------------------------------------
local function chooseSpawn(player: Player): SpawnLocation?
	local list = {}
	if teamsMode and player.Team then
		list = MapService.GetTeamSpawns(player.Team)
	end
	if #list == 0 then
		list = MapService.GetAliveSpawns()
	end
	if #list == 0 then
		return nil
	end
	return list[math.random(1, #list)]
end

local function eliminate(player: Player)
	if eliminated[player] then
		return
	end
	eliminated[player] = true
	player:SetAttribute("Eliminated", true)
end

local spawnPlayer -- declarado abaixo

local function onDied(player: Player, humanoid: Humanoid)
	if phase == "Playing" and participants[player] then
		local tag = humanoid:FindFirstChild("creator")
		local killer = tag and tag:IsA("ObjectValue") and tag.Value
		if killer and killer:IsA("Player") and killer ~= player then
			roundKills[killer] = (roundKills[killer] or 0) + 1
		else
			killer = nil
		end

		local function colorOf(p: Player?): Color3
			if p and teamsMode and p.Team then
				return p.TeamColor.Color
			end
			return Color3.new(1, 1, 1)
		end
		remotes.Killfeed:FireAllClients({
			Killer = killer and killer.DisplayName or nil,
			KillerColor = colorOf(killer),
			Victim = player.DisplayName,
			VictimColor = colorOf(player),
		})

		if mode.Lives then
			lives[player] = math.max(0, (lives[player] or 1) - 1)
			player:SetAttribute("Lives", lives[player])
		end
	end

	task.delay(RoundConfig.RespawnTime, function()
		if not player.Parent or player.Character and getHumanoid(player) ~= humanoid then
			return -- já renasceu por outro motivo
		end
		if canRespawn(player) then
			spawnPlayer(player)
		elseif phase == "Playing" then
			eliminate(player)
		end
	end)
end

spawnPlayer = function(player: Player)
	if not player.Parent then
		return
	end
	getStash(player):ClearAllChildren()

	local spawn = chooseSpawn(player)
	if spawn then
		player.RespawnLocation = spawn
	end

	local ok, err = pcall(function()
		player:LoadCharacter()
	end)
	if not ok then
		warn("[Rounds] LoadCharacter falhou:", err)
		return
	end

	local character = player.Character
	if not character then
		return
	end
	if spawn then
		character:PivotTo(spawn.CFrame + Vector3.new(0, spawn.Size.Y / 2 + 3, 0))
	end
	if phase == "Intermission" then
		Instance.new("ForceField").Parent = character
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if humanoid then
		humanoid.Died:Connect(function()
			onDied(player, humanoid :: Humanoid)
		end)
	end

	for _, active in pairs(activeEvents) do
		if active.Handle.OnCharacter then
			pcall(active.Handle.OnCharacter, player, character)
		end
	end

	task.delay(0.5, applyToolPolicy, player)
end

local function spawnAll()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(spawnPlayer, player)
	end
	task.wait(1)
end

---------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------
local function eventContext()
	return {
		Map = MapService,
		Runtime = MapService.GetRuntimeFolder(),
		Speed = function()
			return suddenDeath and RoundConfig.Tuning.SuddenDeathSpeedMultiplier or 1
		end,
		Alive = aliveList,
		Reward = function(player: Player, xp: number, coins: number, reason: string)
			if Progression then
				Progression.Reward(player, xp, coins, reason)
			end
		end,
		Info = info,
		SetSwordsOnly = function(value: boolean)
			swordsOverride = value
			applyToolPolicyAll()
		end,
	}
end

local function startEvent(id: string, duration: number?, isRandom: boolean)
	local starter = Events[id]
	if not starter or activeEvents[id] then
		return
	end
	local ok, handle = pcall(starter, eventContext())
	if not ok then
		warn("[Rounds] Evento", id, "deu erro ao começar:", handle)
		return
	end
	activeEvents[id] = {
		Handle = handle,
		EndsAt = duration and (serverNow() + duration) or 0,
		Random = isRandom,
	}
	announce("Event", { Id = id })
	publishEvents()
end

local function stopEvent(id: string)
	local active = activeEvents[id]
	if not active then
		return
	end
	activeEvents[id] = nil
	if active.Handle and active.Handle.Stop then
		local ok, err = pcall(active.Handle.Stop)
		if not ok then
			warn("[Rounds] Evento", id, "deu erro ao parar:", err)
		end
	end
	publishEvents()
end

local function stopAllEvents()
	for id in pairs(activeEvents) do
		stopEvent(id)
	end
	swordsOverride = false
	MapService.ClearRuntime()
end

local function randomEventActive(): boolean
	for _, active in pairs(activeEvents) do
		if active.Random then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------
-- Fases
---------------------------------------------------------------------
local function setPhase(newPhase: string, duration: number?)
	phase = newPhase
	setState("Phase", newPhase)
	setState("EndsAt", duration and (serverNow() + duration) or 0)
end

local function waitForPlayers()
	local minPlayers = RunService:IsStudio() and 1 or RoundConfig.MinPlayers
	if #Players:GetPlayers() >= minPlayers then
		return
	end
	setPhase("Waiting")
	while #Players:GetPlayers() < minPlayers do
		setState("Message", ("Aguardando jogadores (%d/%d)"):format(#Players:GetPlayers(), minPlayers))
		task.wait(1)
	end
	setState("Message", "")
end

local function tallyVotes()
	local counts = {}
	for _, modeId in pairs(votes) do
		counts[modeId] = (counts[modeId] or 0) + 1
	end
	local best, bestCount = {}, 0
	for _, m in ipairs(RoundConfig.Modes) do
		local count = counts[m.Id] or 0
		if count > bestCount then
			best, bestCount = { m }, count
		elseif count == bestCount and count > 0 then
			table.insert(best, m)
		end
	end
	if #best == 0 then
		return RoundConfig.Modes[1]
	end
	return best[math.random(1, #best)]
end

local function intermission()
	votes = {}
	publishVotes()
	setPhase("Intermission", RoundConfig.IntermissionTime)

	MapService.Regenerate()
	local reset = gameRemote("RequestSpectator")
	if reset then
		reset:FireAllClients("GameReset") -- tira todo mundo do modo espectador do jogo
	end
	mode = RoundConfig.Modes[1]
	assignTeams()
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("Eliminated", false)
		player:SetAttribute("Lives", nil)
	end
	spawnAll()

	local endsAt = os.clock() + RoundConfig.IntermissionTime - 1
	while os.clock() < endsAt do
		publishTeams()
		task.wait(0.5)
	end
	mode = tallyVotes()
end

local function finishRound(winner: any)
	stopAllEvents()
	setPhase("Ending", RoundConfig.EndingTime)

	local text, color = "EMPATE!", Color3.new(1, 1, 1)
	local winners = {}
	if typeof(winner) == "Instance" and winner:IsA("Team") then
		text = ("TIME %s VENCEU!"):format(winner.Name:upper())
		color = winner.TeamColor.Color
		for player in pairs(participants) do
			if player.Parent and player.Team == winner then
				table.insert(winners, player)
			end
		end
	elseif typeof(winner) == "Instance" and winner:IsA("Player") then
		text = ("%s VENCEU!"):format(winner.DisplayName:upper())
		winners = { winner }
	end

	-- MVP = mais kills na rodada
	local mvp, mvpKills = nil, 0
	for player, kills in pairs(roundKills) do
		if player.Parent and kills > mvpKills then
			mvp, mvpKills = player, kills
		end
	end

	announce("Winner", {
		Text = text,
		Color = color,
		MVP = mvp and mvp.DisplayName or nil,
		MVPKills = mvpKills,
	})

	if Progression then
		for _, player in ipairs(winners) do
			Progression.AddWin(player)
		end
		if mvp then
			Progression.Reward(mvp, RoundConfig.MVPReward.XP, RoundConfig.MVPReward.Coins, "MVP da rodada! ⭐")
		end
	end

	task.wait(RoundConfig.EndingTime)
end

local function playRound()
	suddenDeath = false
	setState("SuddenDeath", false)
	setState("Mode", mode.Id)
	participants, eliminated, lives, roundKills = {}, {}, {}, {}

	assignTeams()
	for _, player in ipairs(Players:GetPlayers()) do
		participants[player] = true
		player:SetAttribute("Eliminated", false)
		if mode.Lives then
			lives[player] = mode.Lives
			player:SetAttribute("Lives", mode.Lives)
		end
	end

	setPhase("Playing", RoundConfig.MaxRoundTime)
	roundStartedAt = os.clock()
	spawnAll() -- todo mundo renasce na torre, com as armas
	announce("RoundStart", { Mode = mode.Id })

	-- Sozinho (ex.: testando no Studio) a rodada só acaba se você for eliminado ou pelo tempo
	local soloTest = #standing() <= 1

	local shrinkStarted = false
	local nextRandomAt = RoundConfig.FirstRandomEventAt
	local lastRandom = nil

	while true do
		task.wait(0.5)
		local elapsed = os.clock() - roundStartedAt

		-- eventos aleatórios que acabaram
		for id, active in pairs(activeEvents) do
			if active.EndsAt > 0 and serverNow() >= active.EndsAt then
				stopEvent(id)
			end
		end

		-- evento que encolhe o mapa
		if not shrinkStarted and elapsed >= RoundConfig.ShrinkStartsAt then
			shrinkStarted = true
			local list = RoundConfig.ShrinkEvents
			startEvent(list[math.random(1, #list)].Id, nil, false)
		end

		-- evento aleatório
		if elapsed >= nextRandomAt and not randomEventActive() then
			local options = {}
			for _, event in ipairs(RoundConfig.RandomEvents) do
				if event.Id ~= lastRandom and not (event.Id == "SwordDuel" and mode.SwordsOnly) then
					table.insert(options, event.Id)
				end
			end
			lastRandom = options[math.random(1, #options)]
			startEvent(lastRandom, mode.EventDuration, true)
			local interval = mode.EventInterval / (suddenDeath and 1.5 or 1)
			nextRandomAt = elapsed + mode.EventDuration + interval
		end

		-- morte súbita
		if not suddenDeath and elapsed >= RoundConfig.SuddenDeathAt then
			suddenDeath = true
			setState("SuddenDeath", true)
			announce("SuddenDeath", {})
			if not shrinkStarted then
				shrinkStarted = true
				startEvent("Lava", nil, false)
			end
		end

		publishTeams()

		-- quem ainda está vivo na disputa?
		local sides = standing()
		if soloTest then
			if #sides == 0 then
				return finishRound(nil)
			end
		elseif #sides <= 1 then
			return finishRound(sides[1])
		end

		-- acabou o tempo: vence quem tiver mais gente viva
		if elapsed >= RoundConfig.MaxRoundTime then
			local best, bestAlive, tie = nil, -1, false
			for _, side in ipairs(sides) do
				local alive = 0
				if typeof(side) == "Instance" and side:IsA("Team") then
					for _, player in ipairs(side:GetPlayers()) do
						if isAlive(player) then
							alive += 1
						end
					end
				else
					alive = isAlive(side) and 1 or 0
				end
				if alive > bestAlive then
					best, bestAlive, tie = side, alive, false
				elseif alive == bestAlive then
					tie = true
				end
			end
			return finishRound(not tie and best or nil)
		end
	end
end

---------------------------------------------------------------------
-- Entrada / saída de jogadores
---------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	watchTools(player)
	player:SetAttribute("Eliminated", false)

	if phase == "Playing" then
		if suddenDeath or mode.Lives then
			-- entrou no meio de uma rodada que não aceita gente nova: assiste
			eliminate(player)
			return
		end
		assignLateJoiner(player)
		participants[player] = true
	elseif phase == "Intermission" then
		assignLateJoiner(player)
	end
	task.spawn(spawnPlayer, player)
end

local function onPlayerRemoving(player: Player)
	votes[player] = nil
	participants[player] = nil
	eliminated[player] = nil
	lives[player] = nil
	roundKills[player] = nil
	local stash = stashRoot:FindFirstChild(tostring(player.UserId))
	if stash then
		stash:Destroy()
	end
	publishVotes()
end

---------------------------------------------------------------------
-- Init
---------------------------------------------------------------------
function RoundService.Init()
	Players.CharacterAutoLoads = false

	stateFolder = Instance.new("Folder")
	stateFolder.Name = "RoundState"
	stateFolder.Parent = ReplicatedStorage

	local remoteFolder = Instance.new("Folder")
	remoteFolder.Name = "RoundRemotes"
	for _, name in ipairs({ "Announce", "Killfeed", "Vote" }) do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remoteFolder
		remotes[name] = remote
	end
	remoteFolder.Parent = ReplicatedStorage

	setState("Phase", "Waiting")
	setState("EndsAt", 0)
	setState("Mode", mode.Id)
	setState("SuddenDeath", false)
	setState("Teams", "[]")
	setState("Votes", "{}")
	setState("Events", "[]")
	setState("Message", "")
	setState("PlayersLeft", 0)

	remotes.Vote.OnServerEvent:Connect(function(player, modeId)
		if phase ~= "Intermission" or type(modeId) ~= "string" then
			return
		end
		for _, m in ipairs(RoundConfig.Modes) do
			if m.Id == modeId then
				votes[player] = modeId
				publishVotes()
				return
			end
		end
	end)

	task.wait(1) -- deixa o mapa terminar de carregar
	MapService.Snapshot()

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	print("[Rounds] Sistema de rodadas iniciado!")

	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				waitForPlayers()
				intermission()
				playRound()
			end)
			if not ok then
				warn("[Rounds] Erro na rodada, recomeçando:", err)
				stopAllEvents()
				task.wait(3)
			end
		end
	end)
end

return RoundService
