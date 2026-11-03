--[[
	RGB — deixa qualquer texto (ou borda/fundo) com efeito arco-íris.

	Uso (funciona no servidor E no cliente):
		local RGB = require(ReplicatedStorage.Shared.RGB)
		RGB.Apply(meuTextLabel)                -- gradiente arco-íris que "anda"
		RGB.Apply(meuTextLabel, "Rainbow")     -- cor única que troca com o tempo
		RGB.Apply(meuUIStroke, "Rainbow", 0.5) -- borda RGB, mais rápida
		RGB.Remove(meuTextLabel)

	O efeito é animado só no cliente (RGB.Start(), chamado pelo RGBController).
	Como usa tags (CollectionService), dá pra marcar textos pelo servidor
	também, e eles ficam RGB para todo mundo (ex.: títulos em cima da cabeça).

	Também dá pra fazer sem código no Studio: coloque a tag "RGBText" em
	qualquer TextLabel/TextButton/UIStroke/Frame. Atributos opcionais:
		RGBMode  = "Gradient" | "Rainbow"
		RGBSpeed = número (padrão 0.25 = uma volta a cada 4s)
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local RGB = {}

RGB.TagName = "RGBText"
RGB.DefaultSpeed = 0.25
RGB.Saturation = 0.85
RGB.Value = 1

local GRADIENT_NAME = "_RGBGradient"
local KEYPOINTS = 6
local GRADIENT_SPREAD = 0.5 -- quanto do arco-íris aparece ao mesmo tempo no gradiente

function RGB.Apply(obj: Instance, mode: string?, speed: number?)
	obj:SetAttribute("RGBMode", mode or "Gradient")
	if speed then
		obj:SetAttribute("RGBSpeed", speed)
	end
	CollectionService:AddTag(obj, RGB.TagName)
	return obj
end

function RGB.Remove(obj: Instance)
	CollectionService:RemoveTag(obj, RGB.TagName)
	local gradient = obj:FindFirstChild(GRADIENT_NAME)
	if gradient then
		gradient:Destroy()
	end
end

-- Cor RGB "atual" — útil para efeitos (partículas, luzes, rastros)
function RGB.Now(offset: number?, speed: number?): Color3
	local hue = (os.clock() * (speed or RGB.DefaultSpeed) + (offset or 0)) % 1
	return Color3.fromHSV(hue, RGB.Saturation, RGB.Value)
end

local function buildSequence(hue: number): ColorSequence
	local points = table.create(KEYPOINTS + 1)
	for i = 0, KEYPOINTS do
		local alpha = i / KEYPOINTS
		local color = Color3.fromHSV((hue + alpha * GRADIENT_SPREAD) % 1, RGB.Saturation, RGB.Value)
		points[i + 1] = ColorSequenceKeypoint.new(alpha, color)
	end
	return ColorSequence.new(points)
end

local function isText(obj: Instance): boolean
	return obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")
end

local function update(obj: any, now: number, sequenceCache)
	local mode = obj:GetAttribute("RGBMode") or "Gradient"
	local speed = obj:GetAttribute("RGBSpeed") or RGB.DefaultSpeed
	local hue = (now * speed) % 1

	if mode == "Rainbow" then
		local color = Color3.fromHSV(hue, RGB.Saturation, RGB.Value)
		if isText(obj) then
			obj.TextColor3 = color
		elseif obj:IsA("UIStroke") then
			obj.Color = color
		elseif obj:IsA("GuiObject") then
			obj.BackgroundColor3 = color
		elseif obj:IsA("BasePart") then
			obj.Color = color
		end
	else -- "Gradient"
		local gradient = obj:FindFirstChild(GRADIENT_NAME)
		if not gradient then
			gradient = Instance.new("UIGradient")
			gradient.Name = GRADIENT_NAME
			gradient.Parent = obj
			-- o gradiente multiplica a cor original, então deixamos branco
			if isText(obj) then
				obj.TextColor3 = Color3.new(1, 1, 1)
			elseif obj:IsA("UIStroke") then
				obj.Color = Color3.new(1, 1, 1)
			elseif obj:IsA("GuiObject") then
				obj.BackgroundColor3 = Color3.new(1, 1, 1)
			end
		end
		local sequence = sequenceCache[speed]
		if not sequence then
			sequence = buildSequence(hue)
			sequenceCache[speed] = sequence
		end
		gradient.Color = sequence
	end
end

local started = false

-- Liga a animação. Só roda no cliente (o RGBController já chama isso).
function RGB.Start()
	if started or not RunService:IsClient() then
		return
	end
	started = true

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local sequenceCache = {} -- uma sequência por velocidade por frame
		for _, obj in ipairs(CollectionService:GetTagged(RGB.TagName)) do
			update(obj, now, sequenceCache)
		end
	end)
end

return RGB
