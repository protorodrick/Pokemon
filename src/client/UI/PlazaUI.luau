-- Social layer: greeting wheel, chat bubbles, player interaction menu (battle / trade invites),
-- incoming request popups and the two-step trade window.
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Theme = require(script.Parent.Theme)

local LocalPlayer = Players.LocalPlayer

local PlazaUI = {}

-- Must match PlazaService.Greetings order on the server.
local GREETINGS = {
	"Hello!",
	"Nice to meet you!",
	"Want to battle?",
	"Want to trade?",
	"Thank you!",
	"Good game!",
	"Cool creature!",
	"Let's explore together!",
	"See you later!",
	"I'm hunting shinies!",
}

local gui, greetPanel, playerMenu, requestHolder, tradeWindow
local getProfile

local function showBubble(player: Player, text: string)
	local head = player.Character and player.Character:FindFirstChild("Head")
	if head then
		pcall(function()
			TextChatService:DisplayBubble(head, text)
		end)
	end
end

------------------------------------------------------------------ Greeting wheel
local function buildGreetPanel()
	greetPanel = Theme.frame({
		Size = UDim2.fromOffset(240, 330),
		Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = gui,
	})
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
	pad.Parent = greetPanel
	Theme.list(greetPanel, 4)
	for i, text in GREETINGS do
		Theme.button({ Size = UDim2.new(1, 0, 0, 27), Text = text, LayoutOrder = i, Parent = greetPanel, MaxTextSize = 14 }, function()
			Net.get("SendGreeting"):FireServer(i)
			greetPanel.Visible = false
		end)
	end
end

------------------------------------------------------------------ Player menu
local function openPlayerMenu(target: Player)
	if playerMenu then
		playerMenu:Destroy()
	end
	playerMenu = Theme.frame({
		Size = UDim2.fromOffset(240, 150),
		Position = UDim2.fromScale(0.5, 0.45),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Bg,
		Parent = gui,
	})
	Theme.stroke(playerMenu, Theme.Accent, 2)
	Theme.label({
		Size = UDim2.new(1, -20, 0, 28),
		Position = UDim2.fromOffset(10, 8),
		Text = ("%s  ·  Rank %d"):format(target.DisplayName, target:GetAttribute("PlazaRank") or 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = playerMenu,
	})
	Theme.button({ Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 42), Text = "Invite to Battle" }, function()
		Net.get("PlazaInvite"):FireServer(target, "battle")
		playerMenu:Destroy()
	end).Parent =
		playerMenu
	Theme.button(
		{ Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 78), Text = "Invite to Trade", BackgroundColor3 = Theme.Good },
		function()
			Net.get("PlazaInvite"):FireServer(target, "trade")
			playerMenu:Destroy()
		end
	).Parent =
		playerMenu
	Theme.button({
		Size = UDim2.new(1, -20, 0, 26),
		Position = UDim2.fromOffset(10, 116),
		Text = "Close",
		BackgroundColor3 = Theme.Muted,
		MaxTextSize = 14,
	}, function()
		playerMenu:Destroy()
	end).Parent =
		playerMenu
end

local function playerFromPart(part: Instance?)
	while part and part ~= Workspace do
		local p = Players:GetPlayerFromCharacter(part)
		if p then
			return p
		end
		part = part.Parent
	end
	return nil
end

------------------------------------------------------------------ Requests
local function showRequest(id, fromName, kind)
	local f = Theme.frame({ Size = UDim2.new(1, 0, 0, 70), BackgroundColor3 = Theme.Bg, Parent = requestHolder })
	Theme.stroke(f, Theme.Accent, 2)
	Theme.label({
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.fromOffset(8, 4),
		Text = ("%s wants to %s!"):format(fromName, kind),
		Parent = f,
		MaxTextSize = 16,
	})
	local function respond(ok)
		Net.get("PlazaRespond"):FireServer(id, ok)
		f:Destroy()
	end
	Theme.button(
		{ Size = UDim2.new(0.5, -12, 0, 30), Position = UDim2.new(0, 8, 0, 34), Text = "Accept", BackgroundColor3 = Theme.Good, Parent = f },
		function()
			respond(true)
		end
	)
	Theme.button({
		Size = UDim2.new(0.5, -12, 0, 30),
		Position = UDim2.new(0.5, 4, 0, 34),
		Text = "Decline",
		BackgroundColor3 = Theme.Bad,
		Parent = f,
	}, function()
		respond(false)
	end)
	task.delay(20, function()
		if f.Parent then
			f:Destroy()
		end
	end)
end

------------------------------------------------------------------ Trade window
local function renderTrade(state)
	if tradeWindow then
		tradeWindow:Destroy()
		tradeWindow = nil
	end
	if not state.open then
		return
	end
	tradeWindow = Theme.frame({
		Size = UDim2.fromOffset(520, 340),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Bg,
		Parent = gui,
	})
	Theme.stroke(tradeWindow, Theme.Accent, 2)
	Theme.label({
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.fromOffset(10, 8),
		Text = "Trading with " .. state.partner,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = tradeWindow,
	})

	local function offerText(o)
		return o and ("%s%s Lv.%d"):format(o.shiny and "★ " or "", o.name, o.level) or "(nothing yet)"
	end
	Theme.label({
		Size = UDim2.new(0.5, -15, 0, 24),
		Position = UDim2.fromOffset(10, 44),
		Text = "You offer: " .. offerText(state.myOffer),
		Parent = tradeWindow,
		MaxTextSize = 16,
	})
	Theme.label({
		Size = UDim2.new(0.5, -15, 0, 24),
		Position = UDim2.new(0.5, 5, 0, 44),
		Text = "They offer: " .. offerText(state.theirOffer) .. (state.theirConfirm and "  ✔" or ""),
		Parent = tradeWindow,
		MaxTextSize = 16,
	})

	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(1, -20, 0, 190)
	list.Position = UDim2.fromOffset(10, 76)
	list.Parent = tradeWindow
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -6, 0, 54)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.Parent = list
	local profile = getProfile()
	for i, mon in profile and profile.party or {} do
		Theme.button({
			Text = ("%s%s Lv.%d"):format(mon.shiny and "★ " or "", mon.name, mon.level),
			BackgroundColor3 = (state.myOffer and state.myOffer.uid == mon.uid) and Theme.Good or Theme.Panel,
			TextColor3 = Theme.Text,
			LayoutOrder = i,
			Parent = list,
			MaxTextSize = 16,
		}, function()
			Net.get("TradeOffer"):FireServer(i)
		end)
	end

	Theme.button({
		Size = UDim2.new(0.5, -15, 0, 40),
		Position = UDim2.new(0, 10, 1, -50),
		Text = state.myConfirm and "Waiting for partner…" or "Confirm Trade",
		BackgroundColor3 = Theme.Good,
		Parent = tradeWindow,
	}, function()
		Net.get("TradeConfirm"):FireServer()
	end)
	Theme.button({
		Size = UDim2.new(0.5, -15, 0, 40),
		Position = UDim2.new(0.5, 5, 1, -50),
		Text = "Cancel",
		BackgroundColor3 = Theme.Bad,
		Parent = tradeWindow,
	}, function()
		Net.get("TradeCancel"):FireServer()
	end)
end

function PlazaUI.start(profileGetter, toast)
	getProfile = profileGetter
	gui = Instance.new("ScreenGui")
	gui.Name = "TidewildPlaza"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	buildGreetPanel()

	Theme.button({
		Size = UDim2.fromOffset(110, 36),
		Position = UDim2.new(1, -12, 0, 54),
		AnchorPoint = Vector2.new(1, 0),
		Text = "Greet [G]",
		Parent = gui,
	}, function()
		greetPanel.Visible = not greetPanel.Visible
	end)

	requestHolder = Instance.new("Frame")
	requestHolder.BackgroundTransparency = 1
	requestHolder.Size = UDim2.fromOffset(300, 240)
	requestHolder.Position = UDim2.new(1, -12, 0, 100)
	requestHolder.AnchorPoint = Vector2.new(1, 0)
	requestHolder.Parent = gui
	Theme.list(requestHolder, 6)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.G then
			greetPanel.Visible = not greetPanel.Visible
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			-- Click / tap another player's avatar to open their interaction menu.
			local cam = Workspace.CurrentCamera
			local ray = cam:ViewportPointToRay(input.Position.X, input.Position.Y)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { LocalPlayer.Character }
			local hit = Workspace:Raycast(ray.Origin, ray.Direction * 120, params)
			local target = hit and playerFromPart(hit.Instance)
			if target and target ~= LocalPlayer then
				openPlayerMenu(target)
			end
		end
	end)

	Net.get("Greeting").OnClientEvent:Connect(function(player, text)
		showBubble(player, text)
	end)
	Net.get("PlazaRequest").OnClientEvent:Connect(showRequest)
	Net.get("TradeUpdate").OnClientEvent:Connect(function(state)
		renderTrade(state)
		if not state.open and state.reason and toast then
			toast(state.reason)
		end
	end)
end

return PlazaUI
