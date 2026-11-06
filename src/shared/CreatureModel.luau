-- Builds creature models. If ReplicatedStorage.CreatureModels.<SpeciesId> exists (a Model you made or
-- licensed), it is cloned; otherwise a stylised procedural placeholder is generated from the species'
-- shape and colours so the game is fully playable with zero imported assets.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Creatures = require(script.Parent.Creatures)

local CreatureModel = {}

local SHINY_TINT = Color3.fromRGB(255, 230, 120)

local function part(model, name, shape, size, offset, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = offset
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function eyes(model, headCf: CFrame, headRadius: number, s: number)
	local white = Color3.new(1, 1, 1)
	local black = Color3.fromRGB(20, 20, 30)
	for _, side in { -1, 1 } do
		local eyeCf = headCf * CFrame.new(side * headRadius * 0.4, headRadius * 0.15, -headRadius * 0.82)
		part(model, "Eye", Enum.PartType.Ball, Vector3.one * 0.32 * s, eyeCf, white)
		part(model, "Pupil", Enum.PartType.Ball, Vector3.one * 0.18 * s, eyeCf * CFrame.new(0, 0, -0.1 * s), black)
	end
end

local builders = {}

function builders.quad(model, sp, s)
	local body = part(model, "Body", Enum.PartType.Ball, Vector3.new(2.2, 1.6, 3) * s, CFrame.new(0, 1.6 * s, 0), sp.color)
	local headCf = CFrame.new(0, 2.4 * s, -1.6 * s)
	part(model, "Head", Enum.PartType.Ball, Vector3.one * 1.5 * s, headCf, sp.color)
	eyes(model, headCf, 0.75 * s, s)
	for _, side in { -1, 1 } do
		part(
			model,
			"Ear",
			Enum.PartType.Block,
			Vector3.new(0.3, 0.8, 0.3) * s,
			headCf * CFrame.new(side * 0.45 * s, 0.75 * s, 0) * CFrame.Angles(0, 0, -side * 0.3),
			sp.accent
		)
		for _, z in { -0.9, 0.9 } do
			part(
				model,
				"Leg",
				Enum.PartType.Cylinder,
				Vector3.new(1.0, 0.45, 0.45) * s,
				CFrame.new(side * 0.7 * s, 0.5 * s, z * s) * CFrame.Angles(0, 0, math.pi / 2),
				sp.color
			)
		end
	end
	part(
		model,
		"Tail",
		Enum.PartType.Ball,
		Vector3.new(0.6, 0.6, 1.4) * s,
		CFrame.new(0, 2.0 * s, 1.8 * s) * CFrame.Angles(0.6, 0, 0),
		sp.accent,
		Enum.Material.Neon
	)
	return body
end

function builders.biped(model, sp, s)
	local body = part(model, "Body", Enum.PartType.Ball, Vector3.new(1.8, 2.2, 1.6) * s, CFrame.new(0, 1.7 * s, 0), sp.color)
	local headCf = CFrame.new(0, 3.2 * s, 0)
	part(model, "Head", Enum.PartType.Ball, Vector3.one * 1.4 * s, headCf, sp.color)
	part(model, "Cap", Enum.PartType.Ball, Vector3.new(2.4, 0.9, 2.4) * s, headCf * CFrame.new(0, 0.6 * s, 0), sp.accent)
	eyes(model, headCf, 0.7 * s, s)
	for _, side in { -1, 1 } do
		part(
			model,
			"Leg",
			Enum.PartType.Cylinder,
			Vector3.new(0.9, 0.5, 0.5) * s,
			CFrame.new(side * 0.45 * s, 0.45 * s, 0) * CFrame.Angles(0, 0, math.pi / 2),
			sp.color
		)
		part(
			model,
			"Arm",
			Enum.PartType.Ball,
			Vector3.new(0.45, 1.1, 0.45) * s,
			CFrame.new(side * 1.0 * s, 1.9 * s, 0) * CFrame.Angles(0, 0, side * 0.4),
			sp.color
		)
	end
	return body
end

function builders.avian(model, sp, s)
	local body = part(model, "Body", Enum.PartType.Ball, Vector3.new(1.4, 1.3, 1.8) * s, CFrame.new(0, 2.6 * s, 0), sp.color)
	local headCf = CFrame.new(0, 3.3 * s, -0.8 * s)
	part(model, "Head", Enum.PartType.Ball, Vector3.one * 1.0 * s, headCf, sp.color)
	eyes(model, headCf, 0.5 * s, s * 0.8)
	part(model, "Beak", Enum.PartType.Block, Vector3.new(0.25, 0.25, 0.5) * s, headCf * CFrame.new(0, -0.1 * s, -0.55 * s), sp.accent)
	for _, side in { -1, 1 } do
		part(
			model,
			"Wing",
			Enum.PartType.Block,
			Vector3.new(1.8, 0.12, 1.0) * s,
			CFrame.new(side * 1.3 * s, 2.8 * s, 0) * CFrame.Angles(0, 0, side * 0.25),
			sp.accent,
			Enum.Material.Glass
		)
	end
	return body
end

function builders.serpent(model, sp, s)
	local root
	for i = 0, 4 do
		local r = (1.3 - i * 0.18) * s
		local p = part(
			model,
			i == 0 and "Body" or "Segment",
			Enum.PartType.Ball,
			Vector3.one * r,
			CFrame.new(math.sin(i * 0.9) * 0.4 * s, r / 2 + 0.2, i * 0.9 * s),
			i % 2 == 0 and sp.color or sp.accent
		)
		if i == 0 then
			root = p
		end
	end
	local headCf = CFrame.new(0, 1.4 * s, -0.9 * s)
	part(model, "Head", Enum.PartType.Ball, Vector3.one * 1.3 * s, headCf, sp.color)
	eyes(model, headCf, 0.65 * s, s)
	for _, side in { -1, 1 } do
		part(
			model,
			"Frill",
			Enum.PartType.Block,
			Vector3.new(0.1, 0.9, 0.5) * s,
			headCf * CFrame.new(side * 0.7 * s, 0.2 * s, 0.2 * s) * CFrame.Angles(0, 0, side * 0.5),
			sp.accent,
			Enum.Material.Neon
		)
	end
	return root
end

function builders.blob(model, sp, s)
	local headCf = CFrame.new(0, 1.0 * s, 0)
	local body = part(model, "Body", Enum.PartType.Ball, Vector3.new(2.0, 1.8, 2.0) * s, headCf, sp.color)
	eyes(model, headCf, 0.95 * s, s)
	part(model, "Spot", Enum.PartType.Ball, Vector3.one * 0.6 * s, headCf * CFrame.new(0.5 * s, 0.7 * s, 0.3 * s), sp.accent)
	return body
end

function CreatureModel.build(speciesId: string, shiny: boolean?): Model
	local library = ReplicatedStorage:FindFirstChild("CreatureModels")
	local custom = library and library:FindFirstChild(speciesId)
	if custom and custom:IsA("Model") then
		local m = custom:Clone()
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			end
		end
		return m
	end

	local sp = Creatures.get(speciesId)
	local model = Instance.new("Model")
	model.Name = speciesId
	local s = sp.size
	local spec = sp
	if shiny then
		spec = table.clone(sp)
		spec.color = sp.color:Lerp(SHINY_TINT, 0.6)
	end
	local body = (builders[sp.shape] or builders.blob)(model, spec, s)
	model.PrimaryPart = body
	-- Pivot at the feet so callers can place models directly on the ground.
	model.WorldPivot = CFrame.new(0, 0, 0)

	if shiny then
		local sparkle = Instance.new("Sparkles")
		sparkle.SparkleColor = SHINY_TINT
		sparkle.Parent = body
	end
	return model
end

return CreatureModel
