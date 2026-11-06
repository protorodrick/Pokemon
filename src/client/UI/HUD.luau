-- Always-on HUD: party strip, currencies, target hint, toasts, starter picker.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Creatures = require(Shared.Creatures)
local Types = require(Shared.Types)
local Net = require(Shared.Net)

local Theme = require(script.Parent.Theme)

local HUD = {}
HUD.Profile = nil

local gui, partyFrame, currency, targetHint, toastHolder, starterFrame

function HUD.toast(text: string, color: Color3?)
	local t = Theme.frame({
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.15,
		Parent = toastHolder,
	})
	Theme.stroke(t, color or Theme.Accent)
	Theme.label({
		Size = UDim2.new(1, -20, 1, -10),
		Position = UDim2.fromOffset(10, 5),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = color or Theme.Text,
		Parent = t,
	})
	task.delay(3.5, function()
		TweenService:Create(t, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		task.wait(0.4)
		t:Destroy()
	end)
end

local function renderParty(profile)
	Theme.clear(partyFrame)
	Theme.list(partyFrame, 6)
	for i, mon in profile.party do
		local card = Theme.frame({
			Size = UDim2.new(1, 0, 0, 52),
			BackgroundColor3 = i == 1 and Color3.fromRGB(60, 54, 40) or Theme.Panel,
			BackgroundTransparency = 0.1,
			LayoutOrder = i,
			Parent = partyFrame,
		})
		local typeColor = Types.Colors[mon.types[1]] or Theme.Accent
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 5, 1, 0)
		stripe.BackgroundColor3 = typeColor
		stripe.BorderSizePixel = 0
		stripe.Parent = card
		Theme.label({
			Size = UDim2.new(1, -90, 0, 20),
			Position = UDim2.fromOffset(12, 4),
			Text = (mon.shiny and "★ " or "") .. mon.name .. "  Lv." .. mon.level,
			Parent = card,
			MaxTextSize = 16,
		})
		local ratio = mon.maxHp > 0 and mon.hp / mon.maxHp or 0
		local _, fill = Theme.bar(card, {
			Size = UDim2.new(1, -100, 0, 8),
			Position = UDim2.fromOffset(12, 30),
			Color = Theme.hpColor(ratio),
		})
		fill.Size = UDim2.fromScale(ratio, 1)
		Theme.label({
			Size = UDim2.new(0, 80, 0, 14),
			Position = UDim2.new(1, -170, 0, 38),
			Text = mon.hp .. "/" .. mon.maxHp,
			TextColor3 = Theme.Muted,
			Parent = card,
			MaxTextSize = 12,
		})
		if i ~= 1 then
			Theme.button(
				{ Size = UDim2.fromOffset(38, 22), Position = UDim2.new(1, -84, 0, 15), Text = "Lead", Parent = card, MaxTextSize = 12 },
				function()
					Net.get("SetLead"):FireServer(i)
				end
			)
		end
		if mon.hp > 0 and mon.hp < mon.maxHp and profile.potions > 0 then
			Theme.button({
				Size = UDim2.fromOffset(38, 22),
				Position = UDim2.new(1, -42, 0, 15),
				Text = "Heal",
				BackgroundColor3 = Theme.Good,
				Parent = card,
				MaxTextSize = 12,
			}, function()
				Net.get("UsePotion"):FireServer(i)
			end)
		end
	end
end

local function showStarterPicker()
	if starterFrame then
		return
	end
	starterFrame = Theme.frame({
		Size = UDim2.fromOffset(560, 300),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Bg,
		Parent = gui,
	})
	Theme.stroke(starterFrame, Theme.Accent, 2)
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(560, 300)
	sizeLimit.Parent = starterFrame
	starterFrame.Size = UDim2.new(0.95, 0, 0, 300)
	Theme.label({
		Size = UDim2.new(1, -20, 0, 36),
		Position = UDim2.fromOffset(10, 10),
		Text = "Choose your partner",
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = starterFrame,
		MaxTextSize = 28,
	})
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -20, 1, -70)
	row.Position = UDim2.fromOffset(10, 56)
	row.Parent = starterFrame
	local layout = Theme.list(row, 10, true)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	for i, id in Creatures.starters() do
		local sp = Creatures.get(id)
		local card = Theme.frame({ Size = UDim2.new(0.31, 0, 1, 0), LayoutOrder = i, Parent = row })
		Theme.stroke(card, Types.Colors[sp.types[1]], 2)
		Theme.label({
			Size = UDim2.new(1, -16, 0, 30),
			Position = UDim2.fromOffset(8, 8),
			Text = sp.name,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = card,
		})
		Theme.label({
			Size = UDim2.new(1, -16, 0, 20),
			Position = UDim2.fromOffset(8, 40),
			Text = sp.types[1],
			TextColor3 = Types.Colors[sp.types[1]],
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = card,
			MaxTextSize = 16,
		})
		local desc = Theme.label({
			Size = UDim2.new(1, -16, 0, 80),
			Position = UDim2.fromOffset(8, 66),
			Text = sp.description,
			Font = Theme.BodyFont,
			TextWrapped = true,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = card,
			MaxTextSize = 14,
		})
		desc.TextYAlignment = Enum.TextYAlignment.Top
		Theme.button({ Size = UDim2.new(1, -16, 0, 34), Position = UDim2.new(0, 8, 1, -42), Text = "Choose", Parent = card }, function()
			Net.get("ChooseStarter"):FireServer(id)
		end)
	end
end

function HUD.setTarget(w)
	if w then
		local sp = Creatures.get(w.species)
		targetHint.Text = ("%s%s Lv.%d   [E] Battle   [Q] Throw Orb"):format(w.shiny and "★ " or "", sp.name, w.level)
		targetHint.Visible = true
	else
		targetHint.Visible = false
	end
end

function HUD.setVisible(on: boolean)
	partyFrame.Visible = on
end

function HUD.start()
	local player = Players.LocalPlayer
	gui = Instance.new("ScreenGui")
	gui.Name = "TidewildHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = player:WaitForChild("PlayerGui")

	partyFrame = Instance.new("Frame")
	partyFrame.Name = "Party"
	partyFrame.BackgroundTransparency = 1
	partyFrame.Size = UDim2.fromOffset(240, 360)
	partyFrame.Position = UDim2.fromOffset(12, 60)
	partyFrame.Parent = gui

	currency = Theme.frame({
		Size = UDim2.fromOffset(300, 34),
		Position = UDim2.new(1, -12, 0, 12),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.2,
		Parent = gui,
	})
	local currencyText = Theme.label({
		Name = "Text",
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = currency,
		MaxTextSize = 16,
	})

	targetHint = Theme.label({
		Size = UDim2.fromOffset(420, 32),
		Position = UDim2.new(0.5, 0, 1, -150),
		AnchorPoint = Vector2.new(0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		Visible = false,
		Parent = gui,
	})

	toastHolder = Instance.new("Frame")
	toastHolder.BackgroundTransparency = 1
	toastHolder.Size = UDim2.fromOffset(420, 200)
	toastHolder.Position = UDim2.new(0.5, 0, 0, 60)
	toastHolder.AnchorPoint = Vector2.new(0.5, 0)
	toastHolder.Parent = gui
	Theme.list(toastHolder, 6)

	Net.get("ProfileUpdate").OnClientEvent:Connect(function(profile)
		HUD.Profile = profile
		currencyText.Text = ("◎ %d Orbs   ✚ %d   ¢ %d   ✦ %d PC (Rank %d)"):format(
			profile.orbs,
			profile.potions,
			profile.money,
			profile.plazaCoins,
			profile.plazaRank
		)
		renderParty(profile)
		if profile.needsStarter then
			showStarterPicker()
		elseif starterFrame then
			starterFrame:Destroy()
			starterFrame = nil
		end
	end)
	Net.get("Toast").OnClientEvent:Connect(function(text)
		HUD.toast(text)
	end)
	Net.get("PlazaNotice").OnClientEvent:Connect(function(text)
		HUD.toast(text, Color3.fromRGB(255, 200, 120))
	end)
end

return HUD
