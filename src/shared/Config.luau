-- Global tuning values. Everything gameplay-related that you may want to tweak lives here.
local Config = {
	GameName = "Tidewild",

	-- Player
	WalkSpeed = 18,
	SprintSpeed = 32,
	SprintFov = 78,
	BaseFov = 70,

	-- Party / progression
	MaxParty = 6,
	StarterLevel = 5,
	StartingOrbs = 10,
	StartingPotions = 3,
	StartingMoney = 500,
	ShinyOdds = 512, -- 1 in N

	-- Overworld spawning (Scarlet/Violet-style visible encounters)
	SpawnTickRate = 0.2, -- seconds between server AI ticks (5 Hz)
	SnapshotRadius = 220, -- creatures farther than this aren't sent to a client (interest management)
	ZoneActiveRadius = 260, -- zones only spawn while a player is this close
	DespawnAfter = 180, -- seconds a creature lives if nobody battles it
	WanderSpeed = 6,
	ChaseSpeed = 14,
	FleeSpeed = 20,
	NoticeRadius = 26,
	TouchBattleRadius = 6, -- aggressive creatures start a battle when this close

	-- Interaction
	InteractDistance = 16,
	ThrowDistance = 45,
	UnawareCatchBonus = 1.75, -- Legends-style sneak catch bonus

	-- Battles
	TurnTimeout = 30,
	PvPLevel = 50, -- plaza battles are level-normalised for fairness

	-- Plaza / social
	GreetCooldown = 4,
	PairGreetRewardCooldown = 300,
	PlazaCoinsPerGreet = 2,
	PlazaCoinsPerBattle = 10,
	PlazaCoinsPerTrade = 15,
	RequestTimeout = 20,

	-- Shop
	OrbPrice = 20,
	PotionPrice = 30,

	-- Persistence
	DataStoreName = "TidewildSave_v1",
	AutosaveInterval = 120,
}

return Config
