--[[
	UIKit — atalhos para montar interface por código, com o mesmo visual em tudo.
]]

local TweenService = game:GetService("TweenService")

local UIKit = {}

UIKit.Theme = {
	Background = Color3.fromRGB(14, 14, 22),
	Panel = Color3.fromRGB(24, 24, 36),
	PanelLight = Color3.fromRGB(36, 36, 54),
	PanelLighter = Color3.fromRGB(50, 50, 74),
	Text = Color3.fromRGB(240, 240, 250),
	SubText = Color3.fromRGB(160, 160, 190),
	Good = Color3.fromRGB(60, 200, 110),
	Bad = Color3.fromRGB(220, 70, 80),
	Info = Color3.fromRGB(70, 130, 255),
	Gold = Color3.fromRGB(255, 205, 60),
	Locked = Color3.fromRGB(70, 70, 90),

	FontTitle = Enum.Font.GothamBlack,
	FontBold = Enum.Font.GothamBold,
	Font = Enum.Font.GothamMedium,
}

-- UIKit.new("Frame", { Size = ..., Parent = ... }, { filhos })
function UIKit.new(className: string, props: { [string]: any }?, children: { Instance }?)
	local obj: any = Instance.new(className)
	local parent = nil
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			obj[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = obj
	end
	if parent then
		obj.Parent = parent
	end
	return obj
end

function UIKit.Corner(radius: number?)
	return UIKit.new("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

function UIKit.Stroke(color: Color3?, thickness: number?, transparency: number?)
	return UIKit.new("UIStroke", {
		Color = color or Color3.new(0, 0, 0),
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

-- Contorno do texto (deixa legível em qualquer fundo)
function UIKit.TextStroke(thickness: number?)
	return UIKit.new("UIStroke", {
		Color = Color3.new(0, 0, 0),
		Thickness = thickness or 1.5,
		Transparency = 0.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	})
end

function UIKit.Padding(px: number)
	return UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

function UIKit.Label(props: { [string]: any })
	local defaults = {
		BackgroundTransparency = 1,
		Font = UIKit.Theme.FontBold,
		TextColor3 = UIKit.Theme.Text,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for key, value in pairs(props) do
		defaults[key] = value
	end
	return UIKit.new("TextLabel", defaults)
end

function UIKit.Tween(obj: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local tween = TweenService:Create(
		obj,
		TweenInfo.new(time, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out),
		goal
	)
	tween:Play()
	return tween
end

-- Botão arredondado com animação de hover/clique
function UIKit.Button(props: { [string]: any }, onClick: (() -> ())?)
	local defaults = {
		AutoButtonColor = false,
		BackgroundColor3 = UIKit.Theme.PanelLighter,
		Font = UIKit.Theme.FontBold,
		TextColor3 = UIKit.Theme.Text,
		TextSize = 18,
	}
	for key, value in pairs(props) do
		defaults[key] = value
	end
	local button = UIKit.new("TextButton", defaults, { UIKit.Corner(10) })
	local scale = UIKit.new("UIScale", { Parent = button })

	button.MouseEnter:Connect(function()
		UIKit.Tween(scale, 0.15, { Scale = 1.05 })
	end)
	button.MouseLeave:Connect(function()
		UIKit.Tween(scale, 0.15, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		UIKit.Tween(scale, 0.08, { Scale = 0.94 })
	end)
	button.MouseButton1Up:Connect(function()
		UIKit.Tween(scale, 0.15, { Scale = 1.05 })
	end)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

-- 1250 -> "1.250"
function UIKit.FormatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if formatted:sub(1, 1) == "." then
		formatted = formatted:sub(2)
	end
	return formatted
end

return UIKit
