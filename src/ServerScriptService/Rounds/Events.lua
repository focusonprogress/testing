--[[
	Events — cada evento é uma função Start(ctx) que devolve:
		{ Stop = function() ... end, OnCharacter = function(player, character) ... end }

	ctx (montado pelo RoundService):
		ctx.Map            -> MapService
		ctx.Runtime        -> pasta no Workspace para colocar peças do evento
		ctx.Speed()        -> multiplicador de velocidade (2 na morte súbita)
		ctx.Alive()        -> lista { Player, Character, Humanoid, Root } de quem está vivo
		ctx.Reward(player, xp, coins, motivo)
		ctx.Info(texto)    -> aviso pequeno na tela de todo mundo
		ctx.SetSwordsOnly(bool)
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

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

local Shared = findChild(ReplicatedStorage, "Shared")
local RoundConfig = require(findChild(Shared, "RoundConfig"))
local RGB = require(findChild(Shared, "RGB"))

local Tuning = RoundConfig.Tuning

local Events = {}

---------------------------------------------------------------------
-- Ajudantes
---------------------------------------------------------------------
local function newPart(props): any
	local part: any = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	return part
end

local function horizontalDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function maxSize(part: BasePart): number
	return math.max(part.Size.X, part.Size.Y, part.Size.Z)
end

local function detach(part: BasePart)
	for _, joint in ipairs(part:GetJoints()) do
		joint:Destroy()
	end
	part.Anchored = false
end

-- Faz um loop até `running()` virar false, passando o dt
local function loop(running: () -> boolean, interval: number, fn: (number) -> ())
	task.spawn(function()
		local last = os.clock()
		while running() do
			task.wait(interval)
			local now = os.clock()
			if not running() then
				break
			end
			local ok, err = pcall(fn, now - last)
			if not ok then
				warn("[Rounds] Erro num evento:", err)
			end
			last = now
		end
	end)
end

local function explode(position: Vector3, radius: number, runtime: Instance)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = radius
	explosion.BlastPressure = 400000
	explosion.DestroyJointRadiusPercent = 1
	explosion.Parent = runtime
end

---------------------------------------------------------------------
-- EVENTOS QUE ENCOLHEM O MAPA
---------------------------------------------------------------------
function Events.Lava(ctx)
	local info = ctx.Map.Info
	local width = math.min(2048, info.Radius * 2 + 400)
	local lava = newPart({
		Name = "Lava",
		Size = Vector3.new(width, 4, width),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 90, 20),
		Transparency = 0.15,
		Parent = ctx.Runtime,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 40)
	light.Range = 60
	light.Brightness = 3
	light.Parent = lava

	local level = info.MinY - 1
	local rise = (info.MaxY - info.MinY) / Tuning.LavaRiseTime
	local running = true
	local meltTimer = 0

	loop(function()
		return running
	end, 0.2, function(dt)
		level = math.min(level + rise * dt * ctx.Speed(), info.MaxY + 5)
		lava.CFrame = CFrame.new(info.Center.X, level - 2, info.Center.Z)

		for _, alive in ipairs(ctx.Alive()) do
			if alive.Root.Position.Y - 2.5 < level then
				alive.Humanoid:TakeDamage(Tuning.LavaDamagePerSecond * dt)
			end
		end

		-- tijolos que a lava cobre derretem
		meltTimer += dt
		if meltTimer >= 1 then
			meltTimer = 0
			for _, part in ipairs(ctx.Map.GetParts()) do
				if part.Parent and part.Position.Y + part.Size.Y / 2 < level - 1 and maxSize(part) < Tuning.MeltIgnoreBiggerThan then
					part:Destroy()
				end
			end
		end
	end)

	return {
		Stop = function()
			running = false
			lava:Destroy()
		end,
	}
end

function Events.Melt(ctx)
	local info = ctx.Map.Info
	local level = info.MinY
	local rise = (info.MaxY - info.MinY) / Tuning.MeltTime
	local running = true

	-- Derrete só os tijolos soltos (as torres). Se o mapa for todo ancorado, derrete tudo.
	local onlyUnanchored = false
	for _, part in ipairs(ctx.Map.GetParts()) do
		if not part.Anchored then
			onlyUnanchored = true
			break
		end
	end

	loop(function()
		return running
	end, 0.5, function(dt)
		level += rise * dt * ctx.Speed()
		for _, part in ipairs(ctx.Map.GetParts()) do
			if
				part.Parent
				and not part:GetAttribute("Melting")
				and not part:IsA("SpawnLocation")
				and part.Position.Y - part.Size.Y / 2 < level
				and maxSize(part) < Tuning.MeltIgnoreBiggerThan
				and (not onlyUnanchored or not part.Anchored)
			then
				part:SetAttribute("Melting", true)
				part.Material = Enum.Material.Neon
				part.Color = Color3.fromRGB(255, 120, 30)
				Debris:AddItem(part, 0.7)
			end
		end
	end)

	return {
		Stop = function()
			running = false
		end,
	}
end

function Events.Edge(ctx)
	local info = ctx.Map.Info
	local radius = info.Radius
	local shrink = (info.Radius - Tuning.EdgeMinRadius) / Tuning.EdgeShrinkTime
	local running = true

	loop(function()
		return running
	end, 0.5, function(dt)
		radius = math.max(Tuning.EdgeMinRadius, radius - shrink * dt * ctx.Speed())
		for _, part in ipairs(ctx.Map.GetParts()) do
			if
				part.Parent
				and not part:GetAttribute("Falling")
				and maxSize(part) < Tuning.MeltIgnoreBiggerThan
				and horizontalDistance(part.Position, info.Center) > radius
			then
				part:SetAttribute("Falling", true)
				part.Color = part.Color:Lerp(Color3.new(0, 0, 0), 0.5)
				detach(part)
				Debris:AddItem(part, 8)
			end
		end
	end)

	return {
		Stop = function()
			running = false
		end,
	}
end

function Events.Zone(ctx)
	local info = ctx.Map.Info
	local radius = info.Radius + 10
	local shrink = (radius - Tuning.ZoneMinRadius) / Tuning.ZoneShrinkTime
	local height = (info.MaxY - info.MinY) + 200
	local running = true

	local zone = newPart({
		Name = "SafeZone",
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.ForceField,
		Color = Color3.fromRGB(80, 255, 120),
		Parent = ctx.Runtime,
	})

	local function updateZone()
		local diameter = math.min(2048, radius * 2)
		zone.Size = Vector3.new(height, diameter, diameter)
		zone.CFrame = CFrame.new(info.Center.X, (info.MinY + info.MaxY) / 2, info.Center.Z) * CFrame.Angles(0, 0, math.rad(90))
	end
	updateZone()

	loop(function()
		return running
	end, 0.2, function(dt)
		radius = math.max(Tuning.ZoneMinRadius, radius - shrink * dt * ctx.Speed())
		updateZone()
		for _, alive in ipairs(ctx.Alive()) do
			if horizontalDistance(alive.Root.Position, info.Center) > radius then
				alive.Humanoid:TakeDamage(Tuning.ZoneDamagePerSecond * dt * ctx.Speed())
			end
		end
	end)

	return {
		Stop = function()
			running = false
			zone:Destroy()
		end,
	}
end

---------------------------------------------------------------------
-- EVENTOS ALEATÓRIOS
---------------------------------------------------------------------
local function fallingProjectiles(ctx, every: number, make: (Vector3) -> ())
	local running = true
	loop(function()
		return running
	end, every, function()
		make(ctx.Map.RandomPoint(ctx.Map.Info.MaxY + 70))
	end)
	return {
		Stop = function()
			running = false
		end,
	}
end

function Events.Meteors(ctx)
	return fallingProjectiles(ctx, Tuning.MeteorEvery, function(position)
		local meteor = newPart({
			Name = "Meteor",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(4, 4, 4),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 120, 30),
			Anchored = false,
			CanCollide = true,
			CanTouch = true,
			Position = position,
			Parent = ctx.Runtime,
		})
		Instance.new("Fire", meteor).Size = 8
		meteor.AssemblyLinearVelocity = Vector3.new(math.random(-20, 20), -140, math.random(-20, 20))
		meteor:SetNetworkOwner(nil)

		local exploded = false
		meteor.Touched:Connect(function(hit)
			if exploded or hit.Name == "Meteor" or hit:IsDescendantOf(ctx.Runtime) then
				return
			end
			exploded = true
			explode(meteor.Position, 7, ctx.Runtime)
			meteor:Destroy()
		end)
		Debris:AddItem(meteor, 12)
	end)
end

function Events.Bombs(ctx)
	return fallingProjectiles(ctx, Tuning.BombEvery, function(position)
		local bomb = newPart({
			Name = "Bomb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(3, 3, 3),
			Color = Color3.fromRGB(25, 25, 25),
			Anchored = false,
			CanCollide = true,
			Position = position,
			Parent = ctx.Runtime,
		})
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 40, 40)
		light.Range = 12
		light.Parent = bomb
		bomb:SetNetworkOwner(nil)

		task.spawn(function()
			-- pisca cada vez mais rápido e explode
			for i = 1, 12 do
				if not bomb.Parent then
					return
				end
				light.Enabled = not light.Enabled
				bomb.Color = light.Enabled and Color3.fromRGB(200, 30, 30) or Color3.fromRGB(25, 25, 25)
				task.wait(0.4 - i * 0.025)
			end
			if bomb.Parent then
				explode(bomb.Position, 11, ctx.Runtime)
				bomb:Destroy()
			end
		end)
	end)
end

function Events.LowGravity(ctx)
	local original = workspace.Gravity
	workspace.Gravity = Tuning.LowGravity
	return {
		Stop = function()
			workspace.Gravity = original
		end,
	}
end

function Events.Speed(ctx)
	local function apply(humanoid: Humanoid)
		humanoid.WalkSpeed = Tuning.SpeedWalkSpeed
	end
	for _, alive in ipairs(ctx.Alive()) do
		apply(alive.Humanoid)
	end
	return {
		OnCharacter = function(_, character)
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				apply(humanoid)
			end
		end,
		Stop = function()
			for _, player in ipairs(Players:GetPlayers()) do
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.WalkSpeed = StarterPlayer.CharacterWalkSpeed
				end
			end
		end,
	}
end

function Events.Blackout(ctx)
	local saved = {
		ClockTime = Lighting.ClockTime,
		Brightness = Lighting.Brightness,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
	}
	local info = TweenInfo.new(2)
	TweenService:Create(Lighting, info, {
		ClockTime = 0,
		Brightness = 0,
		Ambient = Color3.fromRGB(15, 15, 30),
		OutdoorAmbient = Color3.fromRGB(20, 20, 40),
	}):Play()
	return {
		Stop = function()
			TweenService:Create(Lighting, info, saved):Play()
		end,
	}
end

function Events.SwordDuel(ctx)
	ctx.SetSwordsOnly(true)
	return {
		Stop = function()
			ctx.SetSwordsOnly(false)
		end,
	}
end

function Events.GoldenBrick(ctx)
	local info = ctx.Map.Info
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { ctx.Runtime }
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude

	-- tenta achar um lugar com chão embaixo
	local position = Vector3.new(info.Center.X, info.MaxY + 3, info.Center.Z)
	for _ = 1, 15 do
		local origin = ctx.Map.RandomPoint(info.MaxY + 50)
		local result = workspace:Raycast(origin, Vector3.new(0, -(info.MaxY - info.MinY) - 100, 0), params)
		if result then
			position = result.Position + Vector3.new(0, 3, 0)
			break
		end
	end

	local brick = newPart({
		Name = "GoldenBrick",
		Size = Vector3.new(3, 3, 3),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 210, 60),
		CanTouch = true,
		CFrame = CFrame.new(position),
		Parent = ctx.Runtime,
	})
	RGB.Apply(brick, "Rainbow", 0.6)
	Instance.new("Sparkles", brick)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 100)
	light.Range = 20
	light.Brightness = 3
	light.Parent = brick

	local running = true
	loop(function()
		return running and brick.Parent ~= nil
	end, 0.05, function(dt)
		brick.CFrame = brick.CFrame * CFrame.Angles(0, dt * 2, 0)
	end)

	brick.Touched:Connect(function(hit)
		if not running then
			return
		end
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		local humanoid = hit.Parent and hit.Parent:FindFirstChildOfClass("Humanoid")
		if player and humanoid and humanoid.Health > 0 then
			running = false
			brick:Destroy()
			ctx.Reward(player, RoundConfig.GoldenBrickReward.XP, RoundConfig.GoldenBrickReward.Coins, "Pegou o tijolo dourado! 💎")
			ctx.Info(("💎 %s pegou o tijolo dourado!"):format(player.DisplayName))
		end
	end)

	return {
		Stop = function()
			running = false
			if brick.Parent then
				brick:Destroy()
			end
		end,
	}
end

function Events.KingHunt(ctx)
	local alive = ctx.Alive()
	if #alive < 2 then
		ctx.Info("👑 Precisa de 2 jogadores vivos pra ter rei!")
		return { Stop = function() end }
	end

	local chosen = alive[math.random(1, #alive)]
	local king: Player = chosen.Player
	local kingAlive = true
	local connections = {}

	local highlight = Instance.new("Highlight")
	highlight.Name = "KingHighlight"
	highlight.FillColor = Color3.fromRGB(255, 210, 60)
	highlight.FillTransparency = 0.6
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.Parent = chosen.Character

	local crown = Instance.new("BillboardGui")
	crown.Name = "KingCrown"
	crown.Size = UDim2.fromOffset(160, 40)
	crown.StudsOffset = Vector3.new(0, 5.5, 0)
	crown.AlwaysOnTop = true
	crown.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = "👑 REI 👑"
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = label
	label.Parent = crown
	RGB.Apply(label, "Gradient", 0.8)
	crown.Parent = chosen.Root

	ctx.Info(("👑 %s é o rei! Derrube ele!"):format(king.DisplayName))

	table.insert(connections, chosen.Humanoid.Died:Connect(function()
		if not kingAlive then
			return
		end
		kingAlive = false
		local tag = chosen.Humanoid:FindFirstChild("creator")
		local killer = tag and tag:IsA("ObjectValue") and tag.Value
		if killer and killer:IsA("Player") and killer ~= king and killer.Parent then
			ctx.Reward(killer, RoundConfig.KingKillReward.XP, RoundConfig.KingKillReward.Coins, "Derrubou o rei! 👑")
			ctx.Info(("👑 %s derrubou o rei %s!"):format(killer.DisplayName, king.DisplayName))
		else
			ctx.Info(("👑 O rei %s caiu!"):format(king.DisplayName))
		end
	end))

	return {
		Stop = function()
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
			highlight:Destroy()
			crown:Destroy()
			if kingAlive and king.Parent and chosen.Humanoid.Health > 0 then
				ctx.Reward(king, RoundConfig.KingSurviveReward.XP, RoundConfig.KingSurviveReward.Coins, "Sobreviveu como rei! 👑")
				ctx.Info(("👑 O rei %s sobreviveu!"):format(king.DisplayName))
			end
		end,
	}
end

return Events
