--[[
	RoundUI — barra do topo (fase, tempo, times vivos, eventos ativos),
	anúncios de evento, votação de modo, killfeed e tela de vitória. Tudo RGB.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

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
			warn(("[RoundUI] Esperando '%s' dentro de %s..."):format(name, parent:GetFullName()))
		end
		task.wait(0.1)
	end
end

local player = Players.LocalPlayer
local Shared = findChild(ReplicatedStorage, "Shared")
local RoundConfig = require(findChild(Shared, "RoundConfig"))
local RGB = require(findChild(Shared, "RGB"))
local UIKit = require(findChild(Shared, "UIKit"))

local T = UIKit.Theme
local new = UIKit.new
local Label = UIKit.Label

local State = findChild(ReplicatedStorage, "RoundState")
local Remotes = findChild(ReplicatedStorage, "RoundRemotes")

---------------------------------------------------------------------
-- Base
---------------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = "RoundUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 5,
	Parent = player:WaitForChild("PlayerGui"),
})

local function currentFit(): number
	local viewport = workspace.CurrentCamera.ViewportSize
	return math.clamp(math.min(viewport.X / 900, viewport.Y / 620), 0.55, 1)
end
local fitScales = {}
local function fitToScreen(obj: Instance)
	local scale = new("UIScale", { Scale = currentFit(), Parent = obj })
	table.insert(fitScales, scale)
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	local s = currentFit()
	for _, scale in ipairs(fitScales) do
		scale.Scale = s
	end
end)

local function decode(attribute: string, fallback)
	local raw = State:GetAttribute(attribute)
	if type(raw) ~= "string" or raw == "" then
		return fallback
	end
	local ok, value = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	return ok and value or fallback
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

local function textWithStroke(props, rgbMode: string?, speed: number?)
	local thickness = props.StrokeThickness or 1.5
	props.StrokeThickness = nil -- não é propriedade do TextLabel
	local label = Label(props)
	UIKit.TextStroke(thickness).Parent = label
	if rgbMode then
		RGB.Apply(label, rgbMode, speed)
	end
	return label
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

---------------------------------------------------------------------
-- Barra do topo
---------------------------------------------------------------------
local top = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(460, 140),
	Parent = gui,
}, {
	new("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
fitToScreen(top)

local bar = new("Frame", {
	BackgroundColor3 = T.Panel,
	BackgroundTransparency = 0.08,
	LayoutOrder = 1,
	Size = UDim2.fromOffset(460, 48),
	Parent = top,
}, { UIKit.Corner(14) })
local barStroke = new("UIStroke", { Thickness = 2.5, Parent = bar })
RGB.Apply(barStroke, "Gradient")

local statusLabel = textWithStroke({
	Text = "Carregando...",
	Font = T.FontTitle,
	TextSize = 22,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Position = UDim2.fromOffset(16, 0),
	Size = UDim2.new(1, -120, 1, 0),
	Parent = bar,
}, "Gradient")

local timerLabel = textWithStroke({
	Text = "",
	Font = T.FontTitle,
	TextSize = 26,
	TextXAlignment = Enum.TextXAlignment.Right,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 0),
	Size = UDim2.new(0, 100, 1, 0),
	Parent = bar,
}, "Rainbow", 0.4)

local teamsRow = new("Frame", {
	BackgroundTransparency = 1,
	LayoutOrder = 2,
	Size = UDim2.fromOffset(460, 30),
	Parent = top,
}, {
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local eventsRow = new("Frame", {
	BackgroundTransparency = 1,
	LayoutOrder = 3,
	Size = UDim2.fromOffset(460, 28),
	Parent = top,
}, {
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
	}),
})

local function pill(parent: Instance, text: string, color: Color3?, order: number, rgb: boolean?)
	local frame = new("Frame", {
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = T.Panel,
		BackgroundTransparency = 0.1,
		LayoutOrder = order,
		Size = UDim2.fromOffset(0, 28),
		Parent = parent,
	}, {
		UIKit.Corner(14),
		new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
	})
	local stroke = new("UIStroke", { Color = color or Color3.new(1, 1, 1), Thickness = 2, Parent = frame })
	if rgb then
		RGB.Apply(stroke, "Rainbow", 0.5)
	end
	local label = textWithStroke({
		AutomaticSize = Enum.AutomaticSize.X,
		Text = text,
		Font = T.FontTitle,
		TextSize = 15,
		Size = UDim2.fromScale(0, 1),
		Parent = frame,
	}, rgb and "Gradient" or nil)
	if not rgb and color then
		label.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
	end
	return frame
end

local function refreshTeams()
	for _, child in ipairs(teamsRow:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local phase = State:GetAttribute("Phase")
	if phase == "Waiting" then
		return
	end

	local mode = RoundConfig.GetMode(State:GetAttribute("Mode") or "Classic")
	local teams = decode("Teams", {})
	if #teams > 0 then
		for index, team in ipairs(teams) do
			local color = Color3.fromHex(team.Color)
			local icon = team.Tower and "🏰" or "💥"
			pill(teamsRow, ("%s %d/%d"):format(icon, team.Alive, team.Total), color, index)
		end
	elseif phase == "Playing" then
		pill(teamsRow, ("👥 %d na disputa"):format(State:GetAttribute("PlayersLeft") or 0), nil, 1, true)
	end

	local myLives = player:GetAttribute("Lives")
	if phase == "Playing" and mode.Lives and myLives then
		pill(teamsRow, ("❤️ %d"):format(myLives), Color3.fromRGB(255, 80, 100), 100, true)
	end
end

local function refreshEvents()
	for _, child in ipairs(eventsRow:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index, active in ipairs(decode("Events", {})) do
		local event = RoundConfig.Events[active.Id]
		if event then
			local chip = pill(eventsRow, event.Emoji .. " " .. event.Name, nil, index, true)
			chip:SetAttribute("EndsAt", active.EndsAt)
			chip:SetAttribute("BaseText", event.Emoji .. " " .. event.Name)
		end
	end
end

local function refreshStatus()
	local phase = State:GetAttribute("Phase")
	local mode = RoundConfig.GetMode(State:GetAttribute("Mode") or "Classic")
	if phase == "Waiting" then
		local message = State:GetAttribute("Message")
		statusLabel.Text = "⏳ " .. ((message and message ~= "") and message or "Aguardando jogadores")
	elseif phase == "Intermission" then
		statusLabel.Text = "⏱️ INTERMISSÃO"
	elseif phase == "Playing" then
		if State:GetAttribute("SuddenDeath") then
			statusLabel.Text = "☠️ MORTE SÚBITA • " .. mode.Name:upper()
		else
			statusLabel.Text = mode.Emoji .. " " .. mode.Name:upper()
		end
	elseif phase == "Ending" then
		statusLabel.Text = "🏁 FIM DA RODADA"
	end
	barStroke:SetAttribute("RGBSpeed", State:GetAttribute("SuddenDeath") and 1.2 or 0.25)
end

-- relógio
task.spawn(function()
	while true do
		local endsAt = State:GetAttribute("EndsAt") or 0
		timerLabel.Text = endsAt > 0 and formatTime(endsAt - workspace:GetServerTimeNow()) or ""
		for _, chip in ipairs(eventsRow:GetChildren()) do
			local chipEnds = chip:IsA("Frame") and chip:GetAttribute("EndsAt")
			if chipEnds and chipEnds > 0 then
				local label = chip:FindFirstChildOfClass("TextLabel")
				if label then
					label.Text = ("%s  %s"):format(chip:GetAttribute("BaseText"), formatTime(chipEnds - workspace:GetServerTimeNow()))
				end
			end
		end
		task.wait(0.25)
	end
end)

---------------------------------------------------------------------
-- Anúncio no meio da tela
---------------------------------------------------------------------
local currentAnnouncement = nil

local function bigAnnouncement(emoji: string, title: string, subtitle: string?, duration: number, accent: Color3?)
	if currentAnnouncement then
		currentAnnouncement:Destroy()
	end
	local holder = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(760, 190),
		ZIndex = 10,
		Parent = gui,
	})
	currentAnnouncement = holder
	local fit = currentFit()
	local pop = new("UIScale", { Scale = 0, Parent = holder })

	textWithStroke({
		Text = emoji,
		TextSize = 64,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 70),
		Parent = holder,
	})
	local titleLabel = textWithStroke({
		Text = title,
		Font = T.FontTitle,
		TextSize = 54,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Position = UDim2.fromOffset(0, 70),
		Size = UDim2.new(1, 0, 0, 64),
		StrokeThickness = 3,
		Parent = holder,
	}, "Gradient", 0.7)
	if accent then
		titleLabel:FindFirstChildOfClass("UIStroke").Color = accent
	end
	if subtitle and subtitle ~= "" then
		textWithStroke({
			Text = subtitle,
			Font = T.FontBold,
			TextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 138),
			Size = UDim2.new(1, 0, 0, 30),
			StrokeThickness = 2,
			Parent = holder,
		}, "Rainbow", 0.5)
	end

	UIKit.Tween(pop, 0.45, { Scale = fit }, Enum.EasingStyle.Back)
	task.delay(duration, function()
		if holder.Parent then
			UIKit.Tween(pop, 0.35, { Scale = fit * 1.25 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			fadeOut(holder, 0.35)
			Debris:AddItem(holder, 0.4)
		end
	end)
end

-- Aviso pequeno (ex.: "Fulano pegou o tijolo dourado!")
local function smallInfo(text: string)
	local holder = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = T.Panel,
		BackgroundTransparency = 0.1,
		Position = UDim2.new(0.5, 0, 0, 160),
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 9,
		Parent = gui,
	}, {
		UIKit.Corner(18),
		new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }),
	})
	new("UIScale", { Scale = currentFit(), Parent = holder })
	RGB.Apply(new("UIStroke", { Thickness = 2, Parent = holder }), "Rainbow", 0.6)
	textWithStroke({
		AutomaticSize = Enum.AutomaticSize.X,
		Text = text,
		Font = T.FontTitle,
		TextSize = 18,
		Size = UDim2.fromScale(0, 1),
		Parent = holder,
	}, "Gradient")
	task.delay(3.5, function()
		fadeOut(holder, 0.4)
		Debris:AddItem(holder, 0.5)
	end)
end

---------------------------------------------------------------------
-- Votação
---------------------------------------------------------------------
local votePanel = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundColor3 = T.Background,
	BackgroundTransparency = 0.1,
	Position = UDim2.new(0.5, 0, 1, -96),
	Size = UDim2.fromOffset(680, 118),
	Visible = false,
	Parent = gui,
}, { UIKit.Corner(18) })
fitToScreen(votePanel)
RGB.Apply(new("UIStroke", { Thickness = 2.5, Parent = votePanel }), "Gradient")

textWithStroke({
	Text = "🗳️ VOTE NO MODO DA PRÓXIMA RODADA",
	Font = T.FontTitle,
	TextSize = 18,
	TextXAlignment = Enum.TextXAlignment.Center,
	Position = UDim2.fromOffset(0, 8),
	Size = UDim2.new(1, 0, 0, 22),
	Parent = votePanel,
}, "Gradient")

local voteRow = new("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(12, 38),
	Size = UDim2.new(1, -24, 0, 70),
	Parent = votePanel,
}, {
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local myVote = nil
local voteButtons = {}

for index, mode in ipairs(RoundConfig.Modes) do
	local button = UIKit.Button({
		Text = "",
		BackgroundColor3 = T.PanelLight,
		LayoutOrder = index,
		Size = UDim2.fromOffset(155, 70),
		Parent = voteRow,
	})
	local selectedStroke = new("UIStroke", {
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Enabled = false,
		Parent = button,
	})
	RGB.Apply(selectedStroke, "Rainbow", 0.8)

	textWithStroke({
		Text = mode.Emoji .. " " .. mode.Name,
		Font = T.FontTitle,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Position = UDim2.fromOffset(4, 6),
		Size = UDim2.new(1, -8, 0, 36),
		Parent = button,
	}, "Gradient")
	local count = textWithStroke({
		Text = "0 votos",
		Font = T.FontBold,
		TextSize = 14,
		TextColor3 = T.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = button,
	})

	button.Activated:Connect(function()
		myVote = mode.Id
		Remotes.Vote:FireServer(mode.Id)
		for id, info in pairs(voteButtons) do
			info.Stroke.Enabled = id == myVote
		end
	end)
	voteButtons[mode.Id] = { Stroke = selectedStroke, Count = count, Mode = mode }
end

local function refreshVotes()
	local counts = decode("Votes", {})
	for id, info in pairs(voteButtons) do
		local n = counts[id] or 0
		info.Count.Text = n == 1 and "1 voto" or (n .. " votos")
		info.Stroke.Enabled = id == myVote
	end
end

local function refreshVotePanel()
	local intermission = State:GetAttribute("Phase") == "Intermission"
	if intermission and not votePanel.Visible then
		myVote = nil
		refreshVotes()
	end
	votePanel.Visible = intermission
end

---------------------------------------------------------------------
-- Killfeed (lado direito)
---------------------------------------------------------------------
local killfeed = new("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	BackgroundTransparency = 1,
	Position = UDim2.new(1, -16, 0.42, 0),
	Size = UDim2.fromOffset(340, 220),
	Parent = gui,
}, {
	new("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
fitToScreen(killfeed)
local killCount = 0

local function addKill(payload)
	killCount += 1
	local entries = {}
	for _, child in ipairs(killfeed:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(entries, child)
		end
	end
	if #entries >= 5 then
		table.sort(entries, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		entries[1]:Destroy()
	end

	local entry = new("Frame", {
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = T.Panel,
		BackgroundTransparency = 0.15,
		LayoutOrder = killCount,
		Size = UDim2.fromOffset(0, 30),
		Parent = killfeed,
	}, {
		UIKit.Corner(10),
		new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	RGB.Apply(new("UIStroke", { Thickness = 1.5, Parent = entry }), "Rainbow", 0.5)

	local function name(text: string, color: Color3, order: number)
		local label = textWithStroke({
			AutomaticSize = Enum.AutomaticSize.X,
			Text = text,
			Font = T.FontTitle,
			TextSize = 16,
			TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.2),
			LayoutOrder = order,
			Size = UDim2.fromOffset(0, 30),
			Parent = entry,
		})
		return label
	end

	if payload.Killer then
		name(payload.Killer, payload.KillerColor, 1)
		textWithStroke({
			AutomaticSize = Enum.AutomaticSize.X,
			Text = "⚔️",
			TextSize = 16,
			LayoutOrder = 2,
			Size = UDim2.fromOffset(0, 30),
			Parent = entry,
		})
	else
		textWithStroke({
			AutomaticSize = Enum.AutomaticSize.X,
			Text = "💀",
			TextSize = 16,
			LayoutOrder = 2,
			Size = UDim2.fromOffset(0, 30),
			Parent = entry,
		})
	end
	name(payload.Victim, payload.VictimColor, 3)

	-- se você estiver envolvido, seu nome fica RGB
	for _, child in ipairs(entry:GetChildren()) do
		if child:IsA("TextLabel") and child.Text == player.DisplayName then
			RGB.Apply(child, "Gradient", 0.8)
		end
	end

	task.delay(6, function()
		if entry.Parent then
			fadeOut(entry, 0.5)
			Debris:AddItem(entry, 0.6)
		end
	end)
end

---------------------------------------------------------------------
-- "Você foi eliminado"
---------------------------------------------------------------------
local eliminatedBanner = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundColor3 = T.Background,
	BackgroundTransparency = 0.15,
	Position = UDim2.new(0.5, 0, 1, -100),
	Size = UDim2.fromOffset(560, 54),
	Visible = false,
	Parent = gui,
}, { UIKit.Corner(16) })
fitToScreen(eliminatedBanner)
RGB.Apply(new("UIStroke", { Thickness = 2, Parent = eliminatedBanner }), "Rainbow")
textWithStroke({
	Text = "💀 VOCÊ FOI ELIMINADO • aguarde a próxima rodada",
	Font = T.FontTitle,
	TextSize = 19,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.fromScale(1, 1),
	Parent = eliminatedBanner,
}, "Gradient")

local function refreshEliminated()
	eliminatedBanner.Visible = player:GetAttribute("Eliminated") == true and State:GetAttribute("Phase") == "Playing"
end

---------------------------------------------------------------------
-- Conectando tudo
---------------------------------------------------------------------
local function refreshAll()
	refreshStatus()
	refreshTeams()
	refreshEvents()
	refreshVotePanel()
	refreshEliminated()
end

State.AttributeChanged:Connect(function(attribute)
	if attribute == "Teams" or attribute == "PlayersLeft" then
		refreshTeams()
	elseif attribute == "Events" then
		refreshEvents()
	elseif attribute == "Votes" then
		refreshVotes()
	else
		refreshAll()
	end
end)
player.AttributeChanged:Connect(function(attribute)
	if attribute == "Eliminated" then
		refreshEliminated()
	elseif attribute == "Lives" then
		refreshTeams()
	end
end)

findChild(Remotes, "Announce").OnClientEvent:Connect(function(kind: string, payload)
	if kind == "Event" then
		local event = RoundConfig.Events[payload.Id]
		if event then
			bigAnnouncement(event.Emoji, event.Name, event.Description, 3)
		end
	elseif kind == "RoundStart" then
		local mode = RoundConfig.GetMode(payload.Mode)
		bigAnnouncement(mode.Emoji, mode.Name:upper(), mode.Description, 3.5)
	elseif kind == "SuddenDeath" then
		bigAnnouncement("☠️", "MORTE SÚBITA!", "Sem respawn. Tudo mais rápido!", 3.5, Color3.fromRGB(200, 0, 0))
	elseif kind == "Winner" then
		local subtitle = payload.MVP and ("⭐ MVP: %s (%d kills)"):format(payload.MVP, payload.MVPKills) or "Boa partida!"
		bigAnnouncement("🏆", payload.Text, subtitle, RoundConfig.EndingTime - 1, payload.Color)
	elseif kind == "Info" then
		smallInfo(payload.Text)
	end
end)

findChild(Remotes, "Killfeed").OnClientEvent:Connect(addKill)

refreshAll()
print("[RoundUI] Interface de rodadas pronta!")
