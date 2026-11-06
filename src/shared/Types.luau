-- Original elemental type system.
local Types = {}

Types.List = { "Normal", "Ember", "Tide", "Bloom", "Volt", "Stone", "Gale", "Frost", "Shade", "Spirit" }

Types.Colors = {
	Normal = Color3.fromRGB(190, 186, 170),
	Ember = Color3.fromRGB(242, 110, 60),
	Tide = Color3.fromRGB(70, 140, 240),
	Bloom = Color3.fromRGB(100, 200, 90),
	Volt = Color3.fromRGB(250, 210, 50),
	Stone = Color3.fromRGB(170, 140, 100),
	Gale = Color3.fromRGB(150, 200, 240),
	Frost = Color3.fromRGB(150, 230, 235),
	Shade = Color3.fromRGB(110, 80, 140),
	Spirit = Color3.fromRGB(240, 150, 220),
}

-- Chart[attacker][defender] = multiplier (missing entries = 1)
local Chart = {
	Normal = { Stone = 0.5, Spirit = 0 },
	Ember = { Bloom = 2, Frost = 2, Tide = 0.5, Stone = 0.5, Ember = 0.5 },
	Tide = { Ember = 2, Stone = 2, Tide = 0.5, Bloom = 0.5 },
	Bloom = { Tide = 2, Stone = 2, Ember = 0.5, Gale = 0.5, Bloom = 0.5 },
	Volt = { Tide = 2, Gale = 2, Stone = 0, Bloom = 0.5, Volt = 0.5 },
	Stone = { Ember = 2, Gale = 2, Frost = 2, Bloom = 0.5 },
	Gale = { Bloom = 2, Shade = 2, Volt = 0.5, Stone = 0.5 },
	Frost = { Bloom = 2, Gale = 2, Ember = 0.5, Tide = 0.5, Frost = 0.5 },
	Shade = { Spirit = 2, Shade = 0.5, Gale = 0.5 },
	Spirit = { Shade = 2, Normal = 0, Spirit = 0.5 },
}

function Types.effectiveness(attackType: string, defenderTypes: { string }): number
	local row = Chart[attackType] or {}
	local mult = 1
	for _, t in defenderTypes do
		local m = row[t]
		if m ~= nil then
			mult *= m
		end
	end
	return mult
end

return Types
