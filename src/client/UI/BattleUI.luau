-- Overworld battle UI. The world keeps running around you; this is just an overlay with the
-- command menu, HP cards and a scrolling log that plays server events back with short delays.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)

local Theme = require(script.Parent.Theme)
local Renderer = require(script.Parent.Parent.WorldRenderer)

local BattleUI = {}
BattleUI.Active = false
BattleUI.OnStateChanged = nil :: ((boolean) -> ())?

local gui, root, foeCard, myCard, logLabel, menu
local view, context
local busy = false

local STAT_NAMES = { atk = "Attack", def = "Defense", spa = "Sp. Atk", spd = "Sp. Def", spe = "Speed" }

local function card(parent, pos, anchor)
	local c = Theme.frame({
		Size = UDim2.fromOffset(300, 64),
		Position = pos,
		AnchorPoint = anchor,
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.1,
		Parent = parent,
	})
	Theme.stroke(c, Theme.Accent)
	local name = Theme.label({ Name = "Name", Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 6), Parent = c })
	local back, fill = Theme.bar(c, { Size = UDim2.new(1, -20, 0, 10), Position = UDim2.fromOffset(10, 36) })
	back.Name = "Bar"
	local hp = Theme.label({
		Name = "HP",
		Size = UDim2.new(1, -20, 0, 14),
		Position = UDim2.fromOffset(10, 48),
		TextColor3 = Theme.Muted,
		Parent = c,
		MaxTextSize = 12,
	})
	return { frame = c, name = name, fill = fill, hp = hp }
end

local function setCard(cardRef, data)
	if not data then
		return
	end
	local types = table.concat(data.types or {}, "/")
	cardRef.name.Text = ("%s%s  Lv.%d  ·  %s"):format(data.shiny and "★ " or "", data.name, data.level, types)
	local ratio = data.maxHp > 0 and data.hp / data.maxHp or 0
	TweenService:Create(cardRef.fill, TweenInfo.new(0.4), { Size = UDim2.fromScale(ratio, 1), BackgroundColor3 = Theme.hpColor(ratio) })
		:Play()
	cardRef.hp.Text = ("HP %d / %d"):format(data.hp, data.maxHp)
end

local function myActive()
	return view and view.party[view.active]
end

local function log(text)
	logLabel.Text = text
end

local function act(action)
	if busy or not BattleUI.Active then
		return
	end
	busy = true
	log("…")
	Net.get("BattleAction"):FireServer(action)
end

local showRoot

local function showMoves()
	Theme.clear(menu)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -6, 0.33, -6)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.Parent = menu
	local mon = myActive()
	for i, m in mon.moves do
		local b = Theme.button({
			Text = ("%s  %d/%d"):format(m.name, m.pp, m.maxPp),
			BackgroundColor3 = Types.Colors[m.type] or Theme.Accent,
			LayoutOrder = i,
			Parent = menu,
			MaxTextSize = 16,
		}, function()
			act({ type = "move", index = i })
		end)
		b.AutoButtonColor = m.pp > 0
	end
	Theme.button({ Text = "Back", BackgroundColor3 = Theme.Muted, LayoutOrder = 10, Parent = menu }, showRoot)
end

local function showParty()
	Theme.clear(menu)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -6, 0.25, -6)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.Parent = menu
	for i, mon in view.party do
		local usable = mon.hp > 0 and i ~= view.active
		Theme.button({
			Text = ("%s Lv.%d  %d/%d"):format(mon.name, mon.level, mon.hp, mon.maxHp),
			BackgroundColor3 = usable and Theme.Accent or Color3.fromRGB(80, 80, 90),
			LayoutOrder = i,
			Parent = menu,
			MaxTextSize = 14,
		}, function()
			if usable then
				act({ type = "switch", slot = i })
			end
		end)
	end
	Theme.button({ Text = "Back", BackgroundColor3 = Theme.Muted, LayoutOrder = 10, Parent = menu }, showRoot)
end

function showRoot()
	Theme.clear(menu)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -6, 0.33, -6)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.Parent = menu
	Theme.button({ Text = "Fight", LayoutOrder = 1, Parent = menu }, showMoves)
	Theme.button({ Text = "Party", LayoutOrder = 2, Parent = menu, BackgroundColor3 = Theme.Good }, showParty)
	if view.kind == "wild" then
		Theme.button({ Text = "Throw Orb", LayoutOrder = 3, Parent = menu, BackgroundColor3 = Color3.fromRGB(110, 170, 255) }, function()
			act({ type = "catch" })
		end)
	end
	Theme.button({ Text = "Potion", LayoutOrder = 4, Parent = menu, BackgroundColor3 = Color3.fromRGB(150, 230, 160) }, function()
		act({ type = "item", item = "Potion" })
	end)
	Theme.button(
		{ Text = view.kind == "wild" and "Run" or "Forfeit", LayoutOrder = 5, Parent = menu, BackgroundColor3 = Theme.Bad },
		function()
			act({ type = "run" })
		end
	)
end

local function refreshCards()
	setCard(myCard, myActive())
	setCard(foeCard, view.foe)
end

local function describe(ev): string?
	local t = ev.t
	if t == "move" then
		local s = ("%s used %s!"):format(ev.user, ev.move)
		if ev.miss then
			return s .. " It missed."
		end
		if ev.eff == 0 then
			return s .. " It had no effect…"
		elseif ev.eff and ev.eff > 1 then
			s ..= " It's super effective!"
		elseif ev.eff and ev.eff < 1 then
			s ..= " It's not very effective."
		end
		if ev.crit then
			s ..= " Critical hit!"
		end
		return s
	elseif t == "faint" then
		return ev.name .. " fainted!"
	elseif t == "switch" then
		return (ev.forced and "Go, " or "Come back! Go, ") .. ev.name .. "!"
	elseif t == "catch" then
		return ev.success and ("Gotcha! %s was caught!"):format(ev.name)
			or ({ "Oh no! It broke free!", "Argh! Almost had it!", "So close!" })[ev.shakes + 1]
			or "It broke free!"
	elseif t == "run" then
		return ev.success and "Got away safely!" or "Couldn't get away!"
	elseif t == "stat" then
		if ev.delta == 0 then
			return ev.name .. "'s " .. STAT_NAMES[ev.stat] .. " won't go any further!"
		end
		return ("%s's %s %s!"):format(ev.name, STAT_NAMES[ev.stat], ev.delta > 0 and "rose" or "fell")
	elseif t == "heal" then
		return ("%s restored %d HP%s."):format(ev.name, ev.amount, ev.item and " with a Potion" or "")
	elseif t == "recoil" then
		return ev.name .. " is hurt by recoil!"
	elseif t == "xp" then
		return ("%s gained %d XP."):format(ev.name, ev.amount)
	elseif t == "levelup" then
		return ("%s grew to Lv.%d!"):format(ev.name, ev.level)
	elseif t == "learn" then
		return ("%s learned %s!"):format(ev.name, ev.move)
	elseif t == "evolve" then
		return ("What? %s evolved into %s!"):format(ev.from, ev.to)
	elseif t == "forfeit" then
		return "A trainer forfeited."
	end
	return nil
end

local function playEvents(events, newView)
	local mySide = context and context.side or 1
	for _, ev in events do
		local text = describe(ev)
		if text then
			log(text)
		end
		if ev.t == "move" and ev.damage and ev.damage > 0 then
			if ev.side == mySide then
				view.foe.hp = ev.targetHp
				setCard(foeCard, view.foe)
			else
				local mine = myActive()
				if mine then
					mine.hp = ev.targetHp
					setCard(myCard, mine)
				end
				Renderer.hitFlash(Renderer.BattleModel)
			end
		elseif ev.t == "switch" and ev.side == mySide then
			local mon = view.party[ev.slot]
			if mon then
				Renderer.stageBattle(mon.species, mon.shiny, context and context.foePos)
			end
		end
		if text then
			task.wait(1.1)
		end
	end
	if newView then
		view = newView
		refreshCards()
	end
end

function BattleUI.open(v, ctx)
	view, context = v, ctx or {}
	context.side = context.side or 1 -- server tells us which side of the battle we are
	BattleUI.Active = true
	busy = false
	root.Visible = true
	refreshCards()
	local mon = myActive()
	Renderer.stageBattle(mon and mon.species, mon and mon.shiny, context.foePos)
	log(v.kind == "wild" and ("A wild %s appeared!"):format(v.foe.name) or ("%s wants to battle!"):format(v.foeName))
	showRoot()
	if BattleUI.OnStateChanged then
		BattleUI.OnStateChanged(true)
	end
end

function BattleUI.close()
	BattleUI.Active = false
	root.Visible = false
	Renderer.clearBattle()
	if BattleUI.OnStateChanged then
		BattleUI.OnStateChanged(false)
	end
end

function BattleUI.start(toast)
	gui = Instance.new("ScreenGui")
	gui.Name = "TidewildBattle"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = false
	root.Parent = gui

	foeCard = card(root, UDim2.new(1, -16, 0, 60), Vector2.new(1, 0))
	myCard = card(root, UDim2.new(0, 16, 1, -250), Vector2.new(0, 0))

	local bottom = Theme.frame({
		Size = UDim2.new(1, -32, 0, 170),
		Position = UDim2.new(0.5, 0, 1, -16),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.1,
		Parent = root,
	})
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(900, 170)
	limit.Parent = bottom

	logLabel = Theme.label({
		Size = UDim2.new(0.45, -16, 1, -20),
		Position = UDim2.fromOffset(12, 10),
		TextWrapped = true,
		Font = Theme.BodyFont,
		Parent = bottom,
	})
	logLabel.TextYAlignment = Enum.TextYAlignment.Top

	menu = Instance.new("Frame")
	menu.BackgroundTransparency = 1
	menu.Size = UDim2.new(0.55, -12, 1, -20)
	menu.Position = UDim2.new(0.45, 0, 0, 10)
	menu.Parent = bottom

	Net.get("BattleStart").OnClientEvent:Connect(function(v, ctx)
		BattleUI.open(v, ctx)
	end)

	Net.get("BattleEvents").OnClientEvent:Connect(function(events, newView)
		if not BattleUI.Active then
			-- Overworld throw result (no battle open)
			for _, ev in events do
				if ev.t == "catch" and not ev.success and toast then
					toast(({ "Oh no! It broke free!", "Argh! Almost had it!", "So close!" })[ev.shakes + 1] or "It broke free!")
				elseif ev.t == "overworldThrow" and ev.bonus and toast then
					toast("Sneak bonus! It didn't see you coming.")
				end
			end
			return
		end
		task.spawn(function()
			playEvents(events, newView)
			busy = false
			if BattleUI.Active and view and not view.ended then
				showRoot()
			end
		end)
	end)

	Net.get("BattleEnd").OnClientEvent:Connect(function(result)
		task.spawn(function()
			while busy do
				task.wait(0.1)
			end
			task.wait(0.6)
			BattleUI.close()
			if not toast then
				return
			end
			if result.caught then
				toast(("%s joined your %s!"):format(result.caught, result.where == "box" and "box" or "party"), Theme.Good)
			elseif result.won and result.kind == "wild" then
				toast(("Victory! +%d coins"):format(result.money or 0), Theme.Good)
			elseif result.lost then
				toast("You blacked out and hurried back to the plaza…", Theme.Bad)
			elseif result.kind == "pvp" then
				toast(result.won and ("You beat %s!"):format(result.opponent) or ("%s won this time. GG!"):format(result.opponent))
			end
		end)
	end)
end

return BattleUI
