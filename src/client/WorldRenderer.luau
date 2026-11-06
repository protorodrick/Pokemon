-- Client-side rendering of everything creature-related:
--   * wild creatures from server snapshots (interpolated every frame, culled by distance)
--   * every player's lead creature following them around (from replicated attributes)
--   * in-world battle staging (your creature hops out in front of you)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Creatures = require(Shared.Creatures)
local CreatureModel = require(Shared.CreatureModel)

local LocalPlayer = Players.LocalPlayer

local Renderer = {}
Renderer.Wild = {} :: { [number]: any }
Renderer.Followers = {} :: { [Player]: any }
Renderer.BattleModel = nil :: Model?

local container = Instance.new("Folder")
container.Name = "ClientCreatures"
container.Parent = Workspace

local function headingCf(pos: Vector3, heading: number)
	return CFrame.new(pos) * CFrame.Angles(0, heading, 0)
end

local function makeTag(model: Model, text: string, color: Color3?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Size = UDim2.fromOffset(140, 28)
	gui.StudsOffsetWorldSpace = Vector3.new(0, model:GetExtentsSize().Y + 1, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 60
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.4
	l.Text = text
	l.Parent = gui
	gui.Adornee = model.PrimaryPart
	gui.Parent = model
	return gui
end

------------------------------------------------------------------ Wild creatures
function Renderer.applySnapshot(list)
	local seen = {}
	for _, row in list do
		local id, species, x, y, z, heading, level, shiny, state = table.unpack(row)
		seen[id] = true
		local w = Renderer.Wild[id]
		local pos = Vector3.new(x, y, z)
		if not w then
			if Creatures.get(species) then
				local model = CreatureModel.build(species, shiny)
				model:PivotTo(headingCf(pos, heading))
				model.Parent = container
				makeTag(model, ("%s  Lv.%d"):format(Creatures.get(species).name, level), shiny and Color3.fromRGB(255, 230, 120) or nil)
				w = {
					id = id,
					species = species,
					model = model,
					from = pos,
					to = pos,
					heading = heading,
					t = 1,
					state = state,
					level = level,
					shiny = shiny,
				}
				Renderer.Wild[id] = w
			end
		else
			w.from = w.model:GetPivot().Position
			w.to = pos
			w.heading = heading
			w.t = 0
			w.state = state
		end
	end
	for id, w in Renderer.Wild do
		if not seen[id] then
			w.model:Destroy()
			Renderer.Wild[id] = nil
		end
	end
end

function Renderer.getWild(id: number)
	return Renderer.Wild[id]
end

------------------------------------------------------------------ Followers
local function rootOf(p: Player)
	return p.Character and p.Character:FindFirstChild("HumanoidRootPart")
end

local function refreshFollower(p: Player)
	local species = p:GetAttribute("LeadSpecies")
	local shiny = p:GetAttribute("LeadShiny")
	local f = Renderer.Followers[p]
	if f and (f.species ~= species or f.shiny ~= shiny) then
		f.model:Destroy()
		Renderer.Followers[p] = nil
		f = nil
	end
	if not f and species and species ~= "" and Creatures.get(species) then
		local model = CreatureModel.build(species, shiny)
		model.Parent = container
		Renderer.Followers[p] = { species = species, shiny = shiny, model = model, pos = nil }
	end
end

local function watchPlayer(p: Player)
	refreshFollower(p)
	p:GetAttributeChangedSignal("LeadSpecies"):Connect(function()
		refreshFollower(p)
	end)
	p:GetAttributeChangedSignal("LeadShiny"):Connect(function()
		refreshFollower(p)
	end)
end

------------------------------------------------------------------ Battle staging
function Renderer.stageBattle(speciesId: string?, shiny: boolean?, foePos: Vector3?)
	Renderer.clearBattle()
	local root = rootOf(LocalPlayer)
	if not root or not speciesId or not Creatures.get(speciesId) then
		return
	end
	local model = CreatureModel.build(speciesId, shiny)
	local target = foePos or (root.Position + root.CFrame.LookVector * 12)
	local mid = root.Position:Lerp(target, 0.45)
	local flat = Vector3.new(target.X, mid.Y, target.Z)
	local cf = CFrame.lookAt(Vector3.new(mid.X, root.Position.Y - 3, mid.Z), Vector3.new(flat.X, root.Position.Y - 3, flat.Z))
	model:PivotTo(cf)
	model.Parent = container
	Renderer.BattleModel = model
	-- Hide own follower during battle so there aren't two copies.
	local f = Renderer.Followers[LocalPlayer]
	if f then
		f.model.Parent = nil
	end
	-- Face the player toward the foe
	if foePos then
		root.CFrame = CFrame.lookAt(root.Position, Vector3.new(foePos.X, root.Position.Y, foePos.Z))
	end
end

function Renderer.clearBattle()
	if Renderer.BattleModel then
		Renderer.BattleModel:Destroy()
		Renderer.BattleModel = nil
	end
	local f = Renderer.Followers[LocalPlayer]
	if f then
		f.model.Parent = container
	end
end

function Renderer.hitFlash(model: Model?)
	if not model then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local h = Instance.new("Highlight")
			h.FillColor = Color3.new(1, 1, 1)
			h.FillTransparency = 0.2
			h.OutlineTransparency = 1
			h.Parent = model
			task.delay(0.15, function()
				h:Destroy()
			end)
			break
		end
	end
end

------------------------------------------------------------------ Frame loop
function Renderer.start()
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(p)
		local f = Renderer.Followers[p]
		if f then
			f.model:Destroy()
			Renderer.Followers[p] = nil
		end
	end)

	local camera = Workspace.CurrentCamera
	local clock = 0
	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		local camPos = camera.CFrame.Position

		-- Wild: interpolate between 5 Hz server ticks; skip work for far-away models.
		for _, w in Renderer.Wild do
			local dist = (w.to - camPos).Magnitude
			if dist < 260 then
				w.t = math.min(1, w.t + dt / 0.2)
				local pos = w.from:Lerp(w.to, w.t)
				local moving = (w.to - w.from).Magnitude > 0.05
				local bob = moving and math.abs(math.sin(clock * 10 + w.id)) * 0.35 or math.sin(clock * 2 + w.id) * 0.08
				w.model:PivotTo(headingCf(pos + Vector3.new(0, bob, 0), w.heading))
			end
		end

		-- Followers trail ~5 studs behind and to the side of their trainer.
		for p, f in Renderer.Followers do
			local root = rootOf(p)
			if root and f.model.Parent then
				local goal = (root.CFrame * CFrame.new(3.5, -3, 4)).Position
				f.pos = f.pos and f.pos:Lerp(goal, math.min(1, dt * 6)) or goal
				local look = root.Position - f.pos
				local heading = math.atan2(-look.X, -look.Z)
				local speed = root.AssemblyLinearVelocity.Magnitude
				local bob = speed > 1 and math.abs(math.sin(clock * 12)) * 0.4 or 0
				f.model:PivotTo(headingCf(f.pos + Vector3.new(0, bob, 0), heading))
			end
		end

		if Renderer.BattleModel then
			local cf = Renderer.BattleModel:GetPivot()
			Renderer.BattleModel:PivotTo(cf * CFrame.new(0, math.sin(clock * 3) * 0.01, 0))
		end
	end)
end

return Renderer
