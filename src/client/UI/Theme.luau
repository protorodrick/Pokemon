-- Tiny UI helper library so every screen shares one look.
local Theme = {}

Theme.Font = Enum.Font.GothamBold
Theme.BodyFont = Enum.Font.Gotham
Theme.Bg = Color3.fromRGB(24, 28, 40)
Theme.Panel = Color3.fromRGB(36, 42, 60)
Theme.Accent = Color3.fromRGB(255, 170, 60)
Theme.Text = Color3.fromRGB(245, 245, 250)
Theme.Muted = Color3.fromRGB(170, 175, 195)
Theme.Good = Color3.fromRGB(90, 210, 120)
Theme.Warn = Color3.fromRGB(240, 200, 70)
Theme.Bad = Color3.fromRGB(235, 80, 80)

function Theme.corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 10)
	c.Parent = parent
	return c
end

function Theme.stroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(1, 1, 1)
	s.Transparency = 0.7
	s.Thickness = thickness or 1.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function Theme.frame(props)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Theme.Panel
	f.BorderSizePixel = 0
	for k, v in props do
		f[k] = v
	end
	Theme.corner(f)
	return f
end

function Theme.label(props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Theme.Font
	l.TextColor3 = Theme.Text
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in props do
		l[k] = v
	end
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = props.MaxTextSize or 22
	c.Parent = l
	return l
end

function Theme.button(props, onClick)
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = Theme.Accent
	b.BorderSizePixel = 0
	b.Font = Theme.Font
	b.TextColor3 = Color3.fromRGB(25, 25, 35)
	b.TextScaled = true
	b.AutoButtonColor = true
	local maxSize = props.MaxTextSize or 20
	props.MaxTextSize = nil
	for k, v in props do
		b[k] = v
	end
	Theme.corner(b, 8)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = b
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

function Theme.bar(parent, props)
	local back = Theme.frame({
		Size = props.Size,
		Position = props.Position,
		BackgroundColor3 = Color3.fromRGB(15, 15, 22),
		Parent = parent,
	})
	Theme.corner(back, 4)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = props.Color or Theme.Good
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = back
	Theme.corner(fill, 4)
	return back, fill
end

function Theme.hpColor(ratio: number)
	if ratio > 0.5 then
		return Theme.Good
	elseif ratio > 0.2 then
		return Theme.Warn
	end
	return Theme.Bad
end

function Theme.list(parent, padding, horizontal)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, padding or 6)
	l.FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = parent
	return l
end

function Theme.clear(parent)
	for _, c in parent:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

return Theme
