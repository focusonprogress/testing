--[[
	GearService — acha o Tool de cada item da loja e entrega para o jogador.

	Ordem de busca:
		1) ServerStorage > ShopItems > (Tool com o nome igual ao Id do item)
		2) InsertService:LoadAsset(item.AssetId)  (gears oficiais do Roblox)
]]

local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local GearService = {}

local GEAR_ATTRIBUTE = "ShopGearId"

local cacheFolder = Instance.new("Folder")
cacheFolder.Name = "GearCache"
cacheFolder.Parent = ServerStorage

local cache: { [string]: Tool } = {}
local failed: { [string]: boolean } = {}
local loading: { [string]: boolean } = {}

function GearService.GetTemplate(item): Tool?
	-- se outro pedido já está carregando esse gear, espera ele terminar
	while loading[item.Id] do
		task.wait(0.1)
	end
	if cache[item.Id] then
		return cache[item.Id]
	end

	local manualFolder = ServerStorage:FindFirstChild("ShopItems")
	local manual = manualFolder and manualFolder:FindFirstChild(item.Id)
	if manual and manual:IsA("Tool") then
		cache[item.Id] = manual
		return manual
	end

	if item.AssetId and item.AssetId > 0 and not failed[item.Id] then
		loading[item.Id] = true
		local ok, model = pcall(function()
			return InsertService:LoadAsset(item.AssetId)
		end)
		loading[item.Id] = nil
		if ok and model then
			local tool = model:FindFirstChildWhichIsA("Tool", true)
			if tool then
				tool.Parent = cacheFolder
				model:Destroy()
				cache[item.Id] = tool
				return tool
			end
			model:Destroy()
			warn(("[GearService] O asset %d (%s) não tem um Tool dentro."):format(item.AssetId, item.Name))
		else
			warn(("[GearService] Não deu pra carregar %s (asset %d): %s"):format(item.Name, item.AssetId, tostring(model)))
		end
		failed[item.Id] = true
	end

	return nil
end

function GearService.IsAvailable(item): boolean
	return GearService.GetTemplate(item) ~= nil
end

-- Lista de Ids que têm Tool configurado (o cliente usa para mostrar "Em breve")
function GearService.GetAvailableIds(): { [string]: boolean }
	local result = {}
	for _, item in ipairs(Config.ShopItems) do
		if GearService.IsAvailable(item) then
			result[item.Id] = true
		end
	end
	return result
end

function GearService.Preload()
	for _, item in ipairs(Config.ShopItems) do
		task.spawn(GearService.GetTemplate, item)
	end
end

function GearService.RemoveGear(player: Player)
	local containers = { player:FindFirstChildOfClass("Backpack"), player.Character }
	for _, container in ipairs(containers) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and child:GetAttribute(GEAR_ATTRIBUTE) then
					child:Destroy()
				end
			end
		end
	end
end

function GearService.Give(player: Player, itemId: string)
	GearService.RemoveGear(player)
	if itemId == "" then
		return
	end

	local item = Config.GetShopItem(itemId)
	local template = item and GearService.GetTemplate(item)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not template or not backpack then
		return
	end

	local tool = template:Clone()
	tool:SetAttribute(GEAR_ATTRIBUTE, itemId)
	tool.Parent = backpack
end

return GearService
