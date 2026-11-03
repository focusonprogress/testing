--[[
	ProgressionUI — HUD de nível/XP/moedas, loja de gears, conquistas e
	notificações (recompensa, level up, conquista). Tudo com texto RGB.
	A interface é montada por código, então não precisa criar nada no StarterGui.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

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

local player = Players.LocalPlayer
local Shared = findChild(ReplicatedStorage, "Shared")
local Config = require(findChild(Shared, "Config"))
local RGB = require(findChild(Shared, "RGB"))
local UIKit = require(findChild(Shared, "UIKit"))

print("[ProgressionUI] Interface iniciando...")
local Remotes -- preenchido no final, quando o servidor responder

local T = UIKit.Theme
local new = UIKit.new
local Label = UIKit.Label
local fmt = UIKit.FormatNumber

local SOUNDS = {
	LevelUp = "rbxasset://sounds/electronicpingshort.wav",
	Achievement = "rbxasset://sounds/electronicpingshort.wav",
}

---------------------------------------------------------------------
-- Estado
---------------------------------------------------------------------
local state = {
	data = nil, -- dados do servidor (moedas, nível, itens...)
	available = {}, -- [itemId] = true para gears já configurados
}

local refreshers: { () -> () } = {}
local function onRefresh(fn: () -> ())
	table.insert(refreshers, fn)
end
local function refreshAll()
	for _, fn in ipairs(refreshers) do
		fn()
	end
end

---------------------------------------------------------------------
-- Base
---------------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = "ProgressionUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

-- Escala tudo para caber em telas pequenas (celular)
local fitScales: { UIScale } = {}
local function currentFit(): number
	local viewport = workspace.CurrentCamera.ViewportSize
	return math.clamp(math.min(viewport.X / 820, viewport.Y / 600), 0.55, 1)
end
-- Para elementos fixos (HUD, janelas): acompanha mudanças no tamanho da tela
local function fitToScreen(obj: GuiObject)
	local scale = new("UIScale", { Scale = currentFit(), Parent = obj })
	table.insert(fitScales, scale)
	return scale
end
local function updateFit()
	local s = currentFit()
	for _, scale in ipairs(fitScales) do
		scale.Scale = s
	end
end

local function playSound(id: string)
	local sound = new("Sound", { SoundId = id, Volume = 0.6, Parent = gui })
	sound:Play()
	Debris:AddItem(sound, 4)
end

local function fadeOut(root: Instance, time: number)
	for _, obj in ipairs(root:GetDescendants()) do
		if obj:IsA("TextLabel") or obj:IsA("TextButton") then
			UIKit.Tween(obj, time, { TextTransparency = 1, BackgroundTransparency = 1 })
		elseif obj:IsA("UIStroke") then
			UIKit.Tween(obj, time, { Transparency = 1 })
		elseif obj:IsA("Frame") then
			UIKit.Tween(obj, time, { BackgroundTransparency = 1 })
		end
	end
end

-- Botão com texto RGB e borda RGB
local function rgbButton(text: string, props, onClick)
	local button = UIKit.Button(props, onClick)
	button.Text = ""
	local label = Label({
		Text = text,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = T.FontTitle,
		TextSize = props.TextSize or 18,
		Parent = button,
	})
	UIKit.TextStroke(1.5).Parent = label
	RGB.Apply(label, "Gradient")
	local stroke = UIKit.Stroke(Color3.new(1, 1, 1), 2)
	stroke.Parent = button
	RGB.Apply(stroke, "Rainbow")
	return button, label
end

-- Barra de progresso com preenchimento RGB
local function progressBar(props)
	local bar = new("Frame", {
		BackgroundColor3 = T.Background,
		BorderSizePixel = 0,
		Size = props.Size,
		Position = props.Position,
		Parent = props.Parent,
	}, { UIKit.Corner(8) })
	local fill = new("Frame", {
		Name = "Fill",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = bar,
	}, { UIKit.Corner(8) })
	RGB.Apply(fill, "Gradient", 0.4)
	return bar, fill
end

---------------------------------------------------------------------
-- HUD (canto superior esquerdo)
---------------------------------------------------------------------
local hudHolder = new("Frame", {
	Name = "HUDHolder",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(16, 64),
	Size = UDim2.fromOffset(310, 160),
	Parent = gui,
})
fitToScreen(hudHolder)

local hud = new("Frame", {
	Name = "HUD",
	BackgroundColor3 = T.Panel,
	BackgroundTransparency = 0.08,
	Size = UDim2.fromOffset(310, 96),
	Parent = hudHolder,
}, { UIKit.Corner(16) })
RGB.Apply(new("UIStroke", { Thickness = 2.5, Parent = hud }), "Gradient")

-- Círculo do nível
local levelBadge = new("Frame", {
	BackgroundColor3 = T.PanelLight,
	Position = UDim2.fromOffset(12, 12),
	Size = UDim2.fromOffset(72, 72),
	Parent = hud,
}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
RGB.Apply(new("UIStroke", { Thickness = 3, Parent = levelBadge }), "Rainbow", 0.5)

local levelNumber = Label({
	Text = "1",
	Font = T.FontTitle,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Center,
	Position = UDim2.fromScale(0.12, 0.12),
	Size = UDim2.fromScale(0.76, 0.56),
	Parent = levelBadge,
})
UIKit.TextStroke(2).Parent = levelNumber
RGB.Apply(levelNumber, "Gradient")

Label({
	Text = "NÍVEL",
	TextSize = 11,
	TextColor3 = T.SubText,
	TextXAlignment = Enum.TextXAlignment.Center,
	Position = UDim2.fromScale(0, 0.66),
	Size = UDim2.fromScale(1, 0.2),
	Parent = levelBadge,
})

-- Título, XP e moedas
local titleLabel = Label({
	Text = "Carregando...",
	Font = T.FontTitle,
	TextSize = 20,
	Position = UDim2.fromOffset(96, 12),
	Size = UDim2.new(1, -108, 0, 24),
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = hud,
})
UIKit.TextStroke(1.5).Parent = titleLabel
RGB.Apply(titleLabel, "Gradient")

local xpBar, xpFill = progressBar({
	Position = UDim2.fromOffset(96, 42),
	Size = UDim2.new(1, -108, 0, 16),
	Parent = hud,
})
local xpText = Label({
	Text = "0 / 0 XP",
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 2,
	Parent = xpBar,
})
UIKit.TextStroke(1.5).Parent = xpText

local coinsLabel = Label({
	Text = "🪙 0",
	Font = T.FontTitle,
	TextSize = 20,
	Position = UDim2.fromOffset(96, 64),
	Size = UDim2.new(1, -108, 0, 22),
	Parent = hud,
})
UIKit.TextStroke(1.5).Parent = coinsLabel
RGB.Apply(coinsLabel, "Rainbow", 0.3)

-- Contador de moedas animado
local coinValue = new("NumberValue", { Value = 0 })
coinValue.Changed:Connect(function(value)
	coinsLabel.Text = "🪙 " .. fmt(value)
end)

local firstRefresh = true
onRefresh(function()
	local data = state.data
	if not data then
		return
	end
	levelNumber.Text = tostring(data.Level)
	titleLabel.Text = data.Title

	local atMax = data.Level >= data.MaxLevel
	local pct = atMax and 1 or math.clamp(data.XP / math.max(data.XPNeeded, 1), 0, 1)
	xpText.Text = atMax and "NÍVEL MÁXIMO" or ("%s / %s XP"):format(fmt(data.XP), fmt(data.XPNeeded))
	UIKit.Tween(xpFill, 0.5, { Size = UDim2.fromScale(pct, 1) })

	if firstRefresh then
		coinValue.Value = data.Coins
		firstRefresh = false
	else
		UIKit.Tween(coinValue, 0.6, { Value = data.Coins }, Enum.EasingStyle.Quad)
	end
end)

---------------------------------------------------------------------
-- Janelas (loja e conquistas)
---------------------------------------------------------------------
local blur = new("BlurEffect", { Size = 0, Parent = workspace.CurrentCamera })
local windows = {}
local currentWindow = nil

local function closeWindow(window)
	local info = windows[window]
	if not info or not window.Visible then
		return
	end
	if currentWindow == window then
		currentWindow = nil
		UIKit.Tween(blur, 0.2, { Size = 0 })
	end
	local tween = UIKit.Tween(info.Anim, 0.15, { Scale = 0.85 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween.Completed:Connect(function()
		if currentWindow ~= window then
			window.Visible = false
		end
	end)
end

local function openWindow(window)
	if currentWindow == window then
		closeWindow(window)
		return
	end
	if currentWindow then
		closeWindow(currentWindow)
	end
	currentWindow = window
	local info = windows[window]
	window.Visible = true
	info.Anim.Scale = 0.85
	UIKit.Tween(info.Anim, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	UIKit.Tween(blur, 0.3, { Size = 14 })
	info.OnOpen()
end

local function createWindow(title: string, onOpen: (() -> ())?)
	local holder = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(720, 500),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	})
	fitToScreen(holder)

	local window = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = T.Background,
		BackgroundTransparency = 0.04,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	}, { UIKit.Corner(20) })
	local anim = new("UIScale", { Parent = window }) -- animação de abrir/fechar
	RGB.Apply(new("UIStroke", { Thickness = 3, Parent = window }), "Gradient")

	local titleText = Label({
		Text = title,
		Font = T.FontTitle,
		TextSize = 32,
		Position = UDim2.fromOffset(24, 16),
		Size = UDim2.new(1, -260, 0, 44),
		Parent = window,
	})
	UIKit.TextStroke(2).Parent = titleText
	RGB.Apply(titleText, "Gradient")

	local headerCoins = Label({
		Text = "🪙 0",
		Font = T.FontTitle,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -76, 0, 20),
		Size = UDim2.fromOffset(180, 36),
		Parent = window,
	})
	UIKit.TextStroke(1.5).Parent = headerCoins
	RGB.Apply(headerCoins, "Rainbow", 0.3)
	onRefresh(function()
		if state.data then
			headerCoins.Text = "🪙 " .. fmt(state.data.Coins)
		end
	end)

	UIKit.Button({
		Text = "✕",
		TextSize = 22,
		BackgroundColor3 = T.Bad,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 18),
		Size = UDim2.fromOffset(42, 42),
		Parent = window,
	}, function()
		closeWindow(holder)
	end)

	local body = new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 74),
		Size = UDim2.new(1, 0, 1, -74),
		Parent = window,
	}, { UIKit.Padding(16) })

	windows[holder] = { Anim = anim, OnOpen = onOpen or function() end }
	return holder, body
end

local function scrollList(parent: Instance, props)
	local scroll = new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = props.Position or UDim2.new(),
		Size = props.Size or UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = T.PanelLighter,
		Parent = parent,
	}, { UIKit.Padding(4) })
	return scroll
end

---------------------------------------------------------------------
-- Toasts (canto superior direito)
---------------------------------------------------------------------
local toastArea = new("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	BackgroundTransparency = 1,
	Position = UDim2.new(1, -16, 0, 64),
	Size = UDim2.fromOffset(340, 500),
	ZIndex = 20,
	Parent = gui,
}, {
	new("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
	}),
})
fitToScreen(toastArea)
local toastCount = 0

local function makeToast(height: number, accent: Color3, duration: number)
	toastCount += 1
	local slot = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(340, height),
		LayoutOrder = toastCount,
		Parent = toastArea,
	})
	local card = new("Frame", {
		BackgroundColor3 = T.Panel,
		Position = UDim2.fromOffset(380, 0),
		Size = UDim2.fromScale(1, 1),
		Parent = slot,
	}, { UIKit.Corner(14) })
	new("Frame", {
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 6, 1, 0),
		Parent = card,
	}, { UIKit.Corner(6) })

	UIKit.Tween(card, 0.4, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
	task.delay(duration, function()
		local out = UIKit.Tween(card, 0.3, { Position = UDim2.fromOffset(380, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		out.Completed:Wait()
		slot:Destroy()
	end)
	return card
end

local function showMessage(text: string, good: boolean)
	local card = makeToast(52, good and T.Good or T.Bad, 2.5)
	local label = Label({
		Text = text,
		TextSize = 17,
		Position = UDim2.fromOffset(20, 0),
		Size = UDim2.new(1, -30, 1, 0),
		TextWrapped = true,
		Parent = card,
	})
	UIKit.TextStroke(1).Parent = label
	RGB.Apply(label, "Gradient")
end

local function showAchievement(payload)
	local card = makeToast(84, T.Gold, 4.5)
	RGB.Apply(new("UIStroke", { Thickness = 2, Parent = card }), "Rainbow", 0.5)

	local header = Label({
		Text = "🏆 CONQUISTA DESBLOQUEADA",
		Font = T.FontTitle,
		TextSize = 14,
		Position = UDim2.fromOffset(20, 10),
		Size = UDim2.new(1, -30, 0, 18),
		Parent = card,
	})
	RGB.Apply(header, "Gradient", 0.6)

	local name = Label({
		Text = payload.Name,
		Font = T.FontTitle,
		TextSize = 22,
		Position = UDim2.fromOffset(20, 30),
		Size = UDim2.new(1, -110, 0, 26),
		Parent = card,
	})
	UIKit.TextStroke(1.5).Parent = name
	RGB.Apply(name, "Rainbow", 0.4)

	Label({
		Text = payload.Description,
		Font = T.Font,
		TextSize = 13,
		TextColor3 = T.SubText,
		Position = UDim2.fromOffset(20, 58),
		Size = UDim2.new(1, -30, 0, 16),
		Parent = card,
	})
	Label({
		Text = "+" .. fmt(payload.Coins) .. " 🪙",
		Font = T.FontTitle,
		TextSize = 18,
		TextColor3 = T.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 32),
		Size = UDim2.fromOffset(90, 22),
		Parent = card,
	})
	playSound(SOUNDS.Achievement)
end

---------------------------------------------------------------------
-- "+25 XP +10 🪙" flutuando no meio da tela
---------------------------------------------------------------------
local function showReward(payload)
	local holder = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, math.random(-50, 50), 0.66, 0),
		Size = UDim2.fromOffset(420, 64),
		ZIndex = 15,
		Parent = gui,
	})
	new("UIScale", { Scale = currentFit(), Parent = holder })

	local main = Label({
		Text = ("+%d XP    +%d 🪙"):format(payload.XP, payload.Coins),
		Font = T.FontTitle,
		TextSize = 32,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 36),
		Parent = holder,
	})
	UIKit.TextStroke(2.5).Parent = main
	RGB.Apply(main, "Gradient", 0.8)

	if payload.Reason then
		local reason = Label({
			Text = payload.Reason,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 38),
			Size = UDim2.new(1, 0, 0, 22),
			Parent = holder,
		})
		UIKit.TextStroke(1.5).Parent = reason
		RGB.Apply(reason, "Rainbow", 0.5)
	end

	UIKit.Tween(holder, 1.6, { Position = holder.Position - UDim2.fromOffset(0, 70) }, Enum.EasingStyle.Quad)
	task.delay(0.9, function()
		fadeOut(holder, 0.6)
	end)
	Debris:AddItem(holder, 1.8)
end

---------------------------------------------------------------------
-- LEVEL UP gigante
---------------------------------------------------------------------
local function showLevelUp(payload)
	local holder = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(640, 170),
		ZIndex = 30,
		Parent = gui,
	})
	local fit = currentFit()
	local pop = new("UIScale", { Scale = 0, Parent = holder })

	local big = Label({
		Text = ("NÍVEL %d!"):format(payload.Level),
		Font = T.FontTitle,
		TextSize = 84,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 96),
		Parent = holder,
	})
	UIKit.TextStroke(4).Parent = big
	RGB.Apply(big, "Gradient", 0.7)

	local sub = Label({
		Text = payload.NewTitle and ("Novo título: " .. payload.Title) or "Continue assim!",
		Font = T.FontTitle,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 100),
		Size = UDim2.new(1, 0, 0, 36),
		Parent = holder,
	})
	UIKit.TextStroke(2).Parent = sub
	RGB.Apply(sub, "Rainbow", 0.5)

	playSound(SOUNDS.LevelUp)
	UIKit.Tween(pop, 0.5, { Scale = fit }, Enum.EasingStyle.Back)
	task.delay(2.4, function()
		UIKit.Tween(pop, 0.4, { Scale = fit * 1.3 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		fadeOut(holder, 0.4)
		Debris:AddItem(holder, 0.5)
	end)
end

---------------------------------------------------------------------
-- LOJA
---------------------------------------------------------------------
local shopWindow, shopBody = createWindow("🛒 LOJA DE GEARS", nil)

local shopScroll = scrollList(shopBody, {})
new("UIGridLayout", {
	CellSize = UDim2.fromOffset(212, 200),
	CellPadding = UDim2.fromOffset(12, 12),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = shopScroll,
})

local busy = false

local function invoke(remote: RemoteFunction, arg: string)
	if busy then
		return
	end
	busy = true
	local success, ok, message = pcall(function()
		return remote:InvokeServer(arg)
	end)
	busy = false
	if not success then
		showMessage("Erro de conexão, tente de novo.", false)
	elseif message then
		showMessage(message, ok)
	end
end

for index, item in ipairs(Config.ShopItems) do
	local card = new("Frame", {
		BackgroundColor3 = T.Panel,
		LayoutOrder = index,
		Parent = shopScroll,
	}, { UIKit.Corner(14) })
	local cardStroke = new("UIStroke", { Color = item.Color, Thickness = 2, Transparency = 0.25, Parent = card })
	if item.Rainbow then
		RGB.Apply(cardStroke, "Gradient", 0.5)
	end

	-- brilho com a cor do item no topo do card
	new("Frame", {
		BackgroundColor3 = item.Color,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 96),
		Parent = card,
	}, {
		UIKit.Corner(14),
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new(0.45, 1),
		}),
	})

	Label({
		Text = "⚔️",
		TextSize = 46,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 56),
		Parent = card,
	})

	local nameLabel = Label({
		Text = item.Name,
		Font = T.FontTitle,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(8, 78),
		Size = UDim2.new(1, -16, 0, 24),
		Parent = card,
	})
	UIKit.TextStroke(1.5).Parent = nameLabel
	RGB.Apply(nameLabel, "Gradient", item.Rainbow and 0.7 or 0.25)

	local levelLabel = Label({
		Text = ("Nível %d+"):format(item.MinLevel),
		Font = T.Font,
		TextSize = 14,
		TextColor3 = T.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 104),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = card,
	})

	local priceLabel = Label({
		Text = "🪙 " .. fmt(item.Price),
		Font = T.FontTitle,
		TextSize = 18,
		TextColor3 = T.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 124),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = card,
	})
	UIKit.TextStroke(1).Parent = priceLabel

	local actionButton = UIKit.Button({
		Text = "...",
		TextSize = 16,
		Font = T.FontTitle,
		Position = UDim2.fromOffset(12, 156),
		Size = UDim2.new(1, -24, 0, 32),
		Parent = card,
	})
	local equippedStroke = new("UIStroke", {
		Thickness = 2.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Enabled = false,
		Parent = actionButton,
	})
	RGB.Apply(equippedStroke, "Rainbow", 0.6)

	actionButton.Activated:Connect(function()
		local data = state.data
		if not data or not Remotes then
			return
		end
		if data.Equipped == item.Id then
			invoke(Remotes.EquipItem, "")
		elseif data.Owned[item.Id] then
			invoke(Remotes.EquipItem, item.Id)
		else
			invoke(Remotes.BuyItem, item.Id)
		end
	end)

	onRefresh(function()
		local data = state.data
		if not data then
			return
		end
		local owned = data.Owned[item.Id]
		local equipped = data.Equipped == item.Id
		local unlocked = data.Level >= item.MinLevel

		levelLabel.Text = unlocked and ("Nível %d+"):format(item.MinLevel) or ("🔒 Nível %d+"):format(item.MinLevel)
		levelLabel.TextColor3 = unlocked and T.SubText or T.Bad
		priceLabel.Visible = not owned
		equippedStroke.Enabled = equipped

		if equipped then
			actionButton.Text = "✓ EQUIPADO"
			actionButton.BackgroundColor3 = T.Info
		elseif owned then
			actionButton.Text = "EQUIPAR"
			actionButton.BackgroundColor3 = T.PanelLighter
		elseif not state.available[item.Id] then
			actionButton.Text = "EM BREVE"
			actionButton.BackgroundColor3 = T.Locked
		elseif not unlocked then
			actionButton.Text = ("🔒 NÍVEL %d"):format(item.MinLevel)
			actionButton.BackgroundColor3 = T.Locked
		elseif data.Coins < item.Price then
			actionButton.Text = "SEM MOEDAS"
			actionButton.BackgroundColor3 = Color3.fromRGB(110, 45, 55)
		else
			actionButton.Text = "COMPRAR"
			actionButton.BackgroundColor3 = T.Good
		end
	end)
end

---------------------------------------------------------------------
-- CONQUISTAS + estatísticas
---------------------------------------------------------------------
local achievementsWindow, achievementsBody = createWindow("🏆 CONQUISTAS", nil)

-- Linha de estatísticas
local statsRow = new("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 64),
	Parent = achievementsBody,
}, {
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local statBoxes = {}
for index, info in ipairs({
	{ "Kills", "⚔️ Kills" },
	{ "Deaths", "💀 Mortes" },
	{ "KD", "📊 K/D" },
	{ "Wins", "🏆 Vitórias" },
	{ "BestStreak", "🔥 Melhor sequência" },
}) do
	local box = new("Frame", {
		BackgroundColor3 = T.Panel,
		LayoutOrder = index,
		Size = UDim2.new(0.2, -8, 1, 0),
		Parent = statsRow,
	}, { UIKit.Corner(12) })
	local value = Label({
		Text = "0",
		Font = T.FontTitle,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = box,
	})
	UIKit.TextStroke(1.5).Parent = value
	RGB.Apply(value, "Gradient")
	Label({
		Text = info[2],
		Font = T.Font,
		TextSize = 12,
		TextColor3 = T.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(4, 38),
		Size = UDim2.new(1, -8, 0, 18),
		Parent = box,
	})
	statBoxes[info[1]] = value
end

onRefresh(function()
	local data = state.data
	if not data then
		return
	end
	statBoxes.Kills.Text = fmt(data.Kills)
	statBoxes.Deaths.Text = fmt(data.Deaths)
	statBoxes.KD.Text = ("%.2f"):format(data.Kills / math.max(data.Deaths, 1))
	statBoxes.Wins.Text = fmt(data.Wins)
	statBoxes.BestStreak.Text = fmt(data.BestStreak)
end)

local achievementScroll = scrollList(achievementsBody, {
	Position = UDim2.fromOffset(0, 76),
	Size = UDim2.new(1, 0, 1, -76),
})
new("UIListLayout", {
	Padding = UDim.new(0, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = achievementScroll,
})

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

for index, achievement in ipairs(Config.Achievements) do
	local row = new("Frame", {
		BackgroundColor3 = T.Panel,
		LayoutOrder = index,
		Size = UDim2.new(1, -12, 0, 80),
		Parent = achievementScroll,
	}, { UIKit.Corner(12) })
	local rowStroke = new("UIStroke", { Color = T.Locked, Thickness = 2, Parent = row })

	local icon = Label({
		Text = "🔒",
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(10, 12),
		Size = UDim2.fromOffset(56, 56),
		Parent = row,
	})

	local name = Label({
		Text = achievement.Name,
		Font = T.FontTitle,
		TextSize = 20,
		Position = UDim2.fromOffset(78, 8),
		Size = UDim2.new(1, -200, 0, 24),
		Parent = row,
	})
	UIKit.TextStroke(1.5).Parent = name

	Label({
		Text = achievement.Description,
		Font = T.Font,
		TextSize = 14,
		TextColor3 = T.SubText,
		Position = UDim2.fromOffset(78, 32),
		Size = UDim2.new(1, -200, 0, 18),
		Parent = row,
	})

	Label({
		Text = "+" .. fmt(achievement.Coins) .. " 🪙",
		Font = T.FontTitle,
		TextSize = 18,
		TextColor3 = T.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 10),
		Size = UDim2.fromOffset(110, 22),
		Parent = row,
	})

	local _, fill = progressBar({
		Position = UDim2.fromOffset(78, 56),
		Size = UDim2.new(1, -200, 0, 12),
		Parent = row,
	})
	local progressText = Label({
		Text = "0/0",
		Font = T.FontBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 52),
		Size = UDim2.fromOffset(110, 20),
		Parent = row,
	})

	local wasUnlocked = nil
	onRefresh(function()
		local data = state.data
		if not data then
			return
		end
		local unlocked = data.Achievements[achievement.Id] == true
		local current = math.min(statValue(data, achievement.Stat), achievement.Goal)
		fill.Size = UDim2.fromScale(current / achievement.Goal, 1)
		progressText.Text = unlocked and "COMPLETA ✓" or ("%s/%s"):format(fmt(current), fmt(achievement.Goal))

		if unlocked == wasUnlocked then
			return
		end
		wasUnlocked = unlocked
		icon.Text = unlocked and "🏆" or "🔒"
		if unlocked then
			RGB.Apply(name, "Gradient")
			RGB.Apply(rowStroke, "Rainbow", 0.3)
			RGB.Apply(progressText, "Rainbow")
		else
			RGB.Remove(name)
			RGB.Remove(rowStroke)
			RGB.Remove(progressText)
			name.TextColor3 = T.SubText
			rowStroke.Color = T.Locked
			progressText.TextColor3 = T.SubText
		end
	end)
end

---------------------------------------------------------------------
-- Botões do HUD
---------------------------------------------------------------------
local buttonRow = new("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 106),
	Size = UDim2.fromOffset(310, 44),
	Parent = hudHolder,
}, {
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
	}),
})

rgbButton("🛒 LOJA", {
	BackgroundColor3 = T.Panel,
	Size = UDim2.fromOffset(130, 44),
	Parent = buttonRow,
}, function()
	openWindow(shopWindow)
end)

rgbButton("🏆 CONQUISTAS", {
	BackgroundColor3 = T.Panel,
	TextSize = 16,
	Size = UDim2.fromOffset(170, 44),
	Parent = buttonRow,
}, function()
	openWindow(achievementsWindow)
end)

---------------------------------------------------------------------
-- Conexão com o servidor
---------------------------------------------------------------------
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateFit)
updateFit()

Remotes = ReplicatedStorage:WaitForChild("ProgressionRemotes", 15)
if not Remotes then
	titleLabel.Text = "Servidor offline"
	warn("[ProgressionUI] Não achei ReplicatedStorage.ProgressionRemotes. O Script 'Main' do servidor está rodando? Veja os erros no Output.")
	return
end
print("[ProgressionUI] Conectado ao servidor!")

Remotes:WaitForChild("DataChanged").OnClientEvent:Connect(function(data)
	state.data = data
	refreshAll()
end)

Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(kind: string, payload)
	if kind == "Reward" then
		showReward(payload)
	elseif kind == "LevelUp" then
		showLevelUp(payload)
	elseif kind == "Achievement" then
		showAchievement(payload)
	end
end)

task.spawn(function()
	local ok, data, available = pcall(function()
		return Remotes:WaitForChild("RequestData"):InvokeServer()
	end)
	if ok then
		state.available = available or {}
		if data then
			state.data = data
		end
		refreshAll()
	end
end)
