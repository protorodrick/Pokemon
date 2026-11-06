-- Original move list.
-- category: "Physical" | "Special" | "Status"
-- effect (optional): { kind = "stat", target = "self"|"foe", stat = "atk"|"def"|"spa"|"spd"|"spe", stages = n }
--                    { kind = "heal", fraction = 0.5 }
--                    { kind = "drain", fraction = 0.5 }
local Moves = {
	Bonk = { name = "Bonk", type = "Normal", category = "Physical", power = 40, accuracy = 100, pp = 35 },
	QuickDash = { name = "Quick Dash", type = "Normal", category = "Physical", power = 40, accuracy = 100, pp = 30, priority = 1 },
	Bellow = {
		name = "Bellow",
		type = "Normal",
		category = "Status",
		power = 0,
		accuracy = 100,
		pp = 30,
		effect = { kind = "stat", target = "foe", stat = "atk", stages = -1 },
	},
	Harden = {
		name = "Harden",
		type = "Normal",
		category = "Status",
		power = 0,
		accuracy = 100,
		pp = 30,
		effect = { kind = "stat", target = "self", stat = "def", stages = 1 },
	},
	HyperRam = { name = "Hyper Ram", type = "Normal", category = "Physical", power = 90, accuracy = 85, pp = 10 },

	Spark = { name = "Cinder Spit", type = "Ember", category = "Special", power = 40, accuracy = 100, pp = 25 },
	FlameRush = { name = "Flame Rush", type = "Ember", category = "Physical", power = 75, accuracy = 95, pp = 15 },
	Inferno = { name = "Sunflare", type = "Ember", category = "Special", power = 95, accuracy = 90, pp = 10 },

	Squirt = { name = "Squirt", type = "Tide", category = "Special", power = 40, accuracy = 100, pp = 25 },
	RipTide = { name = "Riptide", type = "Tide", category = "Physical", power = 75, accuracy = 95, pp = 15 },
	Tsunami = { name = "Breaker Wave", type = "Tide", category = "Special", power = 95, accuracy = 90, pp = 10 },

	LeafFlick = { name = "Leaf Flick", type = "Bloom", category = "Special", power = 40, accuracy = 100, pp = 25 },
	SapDrain = {
		name = "Sap Drain",
		type = "Bloom",
		category = "Special",
		power = 60,
		accuracy = 100,
		pp = 15,
		effect = { kind = "drain", fraction = 0.5 },
	},
	ThornLash = { name = "Thorn Lash", type = "Bloom", category = "Physical", power = 85, accuracy = 95, pp = 10 },
	Photosynth = {
		name = "Sunbathe",
		type = "Bloom",
		category = "Status",
		power = 0,
		accuracy = 100,
		pp = 10,
		effect = { kind = "heal", fraction = 0.5 },
	},

	Zap = { name = "Zap", type = "Volt", category = "Special", power = 40, accuracy = 100, pp = 30 },
	ArcBolt = { name = "Arc Bolt", type = "Volt", category = "Special", power = 80, accuracy = 95, pp = 15 },

	PebbleToss = { name = "Pebble Toss", type = "Stone", category = "Physical", power = 45, accuracy = 95, pp = 25 },
	Boulder = { name = "Boulder Drop", type = "Stone", category = "Physical", power = 85, accuracy = 90, pp = 10 },

	Gust = { name = "Gust", type = "Gale", category = "Special", power = 40, accuracy = 100, pp = 35 },
	SkyDive = { name = "Sky Dive", type = "Gale", category = "Physical", power = 80, accuracy = 95, pp = 15 },
	Tailwind = {
		name = "Tailwind",
		type = "Gale",
		category = "Status",
		power = 0,
		accuracy = 100,
		pp = 15,
		effect = { kind = "stat", target = "self", stat = "spe", stages = 2 },
	},

	Chill = { name = "Chill Breath", type = "Frost", category = "Special", power = 45, accuracy = 100, pp = 25 },
	Glacier = { name = "Glacier Spike", type = "Frost", category = "Physical", power = 85, accuracy = 90, pp = 10 },

	Nibble = { name = "Shadow Nip", type = "Shade", category = "Physical", power = 50, accuracy = 100, pp = 25 },
	Eclipse = { name = "Eclipse", type = "Shade", category = "Special", power = 80, accuracy = 100, pp = 15 },
	Taunt = {
		name = "Sneer",
		type = "Shade",
		category = "Status",
		power = 0,
		accuracy = 100,
		pp = 20,
		effect = { kind = "stat", target = "foe", stat = "spd", stages = -1 },
	},

	Twinkle = { name = "Twinkle", type = "Spirit", category = "Special", power = 45, accuracy = 100, pp = 25 },
	Radiance = { name = "Radiance", type = "Spirit", category = "Special", power = 85, accuracy = 100, pp = 10 },
	Charm = {
		name = "Lullaby",
		type = "Spirit",
		category = "Status",
		power = 0,
		accuracy = 100,
		pp = 20,
		effect = { kind = "stat", target = "foe", stat = "atk", stages = -2 },
	},

	Struggle = { name = "Struggle", type = "Normal", category = "Physical", power = 50, accuracy = 100, pp = 999, recoil = 0.25 },
}

for id, m in Moves do
	m.id = id
end

return Moves
