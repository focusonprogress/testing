--[[
	MapService — guarda uma cópia do mapa, reconstrói a cada rodada e
	descobre as torres (pelos SpawnLocations de cada time).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local function findChild(parent: Instance, name: string): Instance
	local target = name:lower()
	while true do
		for _, child in ipairs(parent:GetChildren()) do
			local clean = child.Name:gsub("^%s+", ""):gsub("%s+$", "")
			if clean:lower() == target then
				return child
			end
		end
		task.wait(0.1)
	end
end

local RoundConfig = require(findChild(findChild(ReplicatedStorage, "Shared"), "RoundConfig"))

local MapService = {}

MapService.RuntimeName = "RoundRuntime" -- pasta dos efeitos dos eventos (lava, meteoros...)

MapService.Info = {
	Center = Vector3.zero,
	MinY = 0,
	MaxY = 50,
	Radius = 100,
}

local backup = Instance.new("Folder")
backup.Name = "MapBackup"
backup.Parent = ServerStorage

local usingContainer = false
local parts: { BasePart } = {}
local spawns: { { Spawn: SpawnLocation, OriginY: number } } = {}

local function isIgnored(obj: Instance): boolean
	if obj:IsA("Terrain") or obj:IsA("Camera") then
		return true
	end
	if table.find(RoundConfig.IgnoreInWorkspace, obj.Name) then
		return true
	end
	if obj.Name == MapService.RuntimeName or obj:GetAttribute("IgnoreRegen") then
		return true
	end
	if obj:IsA("Model") and Players:GetPlayerFromCharacter(obj) then
		return true
	end
	return false
end

local function getContainer(): Instance?
	if RoundConfig.MapName ~= "" then
		return workspace:FindFirstChild(RoundConfig.MapName)
	end
	return nil
end

-- Raízes do mapa que estão no Workspace agora
function MapService.GetRoots(): { Instance }
	if usingContainer then
		local container = getContainer()
		return container and { container } or {}
	end
	local roots = {}
	for _, child in ipairs(workspace:GetChildren()) do
		if not isIgnored(child) then
			table.insert(roots, child)
		end
	end
	return roots
end

function MapService.Scan()
	parts = {}
	spawns = {}

	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)

	local function consider(obj: Instance)
		if obj:IsA("BasePart") then
			table.insert(parts, obj)
			local half = obj.Size / 2
			minV = minV:Min(obj.Position - half)
			maxV = maxV:Max(obj.Position + half)
			if obj:IsA("SpawnLocation") then
				table.insert(spawns, { Spawn = obj, OriginY = obj.Position.Y })
			end
		end
	end

	for _, root in ipairs(MapService.GetRoots()) do
		consider(root)
		for _, obj in ipairs(root:GetDescendants()) do
			consider(obj)
		end
	end

	if #parts > 0 then
		local center = (minV + maxV) / 2
		MapService.Info = {
			Center = center,
			MinY = minV.Y,
			MaxY = maxV.Y,
			Radius = math.max(maxV.X - minV.X, maxV.Z - minV.Z) / 2,
		}
	end
end

-- Guarda a cópia do mapa (chamado uma vez quando o servidor liga)
function MapService.Snapshot()
	backup:ClearAllChildren()

	local container = getContainer()
	usingContainer = container ~= nil
	if RoundConfig.MapName ~= "" and not container then
		warn(("[Rounds] Não achei o mapa '%s' no Workspace. Usando o Workspace inteiro."):format(RoundConfig.MapName))
	end

	for _, root in ipairs(MapService.GetRoots()) do
		local wasArchivable = root.Archivable
		root.Archivable = true
		local copy = root:Clone()
		root.Archivable = wasArchivable
		if copy then
			copy.Parent = backup
		end
	end

	MapService.Scan()
	print(("[Rounds] Mapa salvo: %d peças, %d spawns."):format(#parts, #spawns))
end

-- Apaga o mapa atual (com tudo que foi construído/destruído) e coloca a cópia
function MapService.Regenerate()
	for _, root in ipairs(MapService.GetRoots()) do
		pcall(function()
			root:Destroy()
		end)
	end
	for _, copy in ipairs(backup:GetChildren()) do
		copy:Clone().Parent = workspace
	end
	MapService.Scan()
end

function MapService.GetParts(): { BasePart }
	return parts
end

local function spawnAlive(record): boolean
	local spawn = record.Spawn
	return spawn.Parent ~= nil
		and spawn:IsDescendantOf(workspace)
		and spawn.Position.Y > record.OriginY - RoundConfig.SpawnFallTolerance
end

function MapService.GetAliveSpawns(): { SpawnLocation }
	local result = {}
	for _, record in ipairs(spawns) do
		if spawnAlive(record) then
			table.insert(result, record.Spawn)
		end
	end
	return result
end

-- Spawns da torre do time que ainda estão de pé
function MapService.GetTeamSpawns(team: Team): { SpawnLocation }
	local result = {}
	for _, record in ipairs(spawns) do
		local spawn = record.Spawn
		if not spawn.Neutral and spawn.TeamColor == team.TeamColor and spawnAlive(record) then
			table.insert(result, spawn)
		end
	end
	return result
end

function MapService.GetRuntimeFolder(): Folder
	local folder = workspace:FindFirstChild(MapService.RuntimeName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = MapService.RuntimeName
		folder.Parent = workspace
	end
	return folder
end

function MapService.ClearRuntime()
	local folder = workspace:FindFirstChild(MapService.RuntimeName)
	if folder then
		folder:ClearAllChildren()
	end
end

-- Ponto aleatório dentro do mapa (horizontal), na altura pedida
function MapService.RandomPoint(y: number): Vector3
	local info = MapService.Info
	local angle = math.random() * math.pi * 2
	local distance = math.sqrt(math.random()) * info.Radius * 0.9
	return Vector3.new(info.Center.X + math.cos(angle) * distance, y, info.Center.Z + math.sin(angle) * distance)
end

return MapService
