-- Single source of truth for remotes. The server creates them; clients wait for them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Events = {
	-- server -> client
	"ProfileUpdate", -- (profileView)
	"SpawnSnapshot", -- (list of nearby wild creatures)
	"BattleStart", -- (view, context)
	"BattleEvents", -- (events, view)
	"BattleEnd", -- (result)
	"PlazaRequest", -- (requestId, fromName, kind)
	"PlazaNotice", -- (text)
	"Greeting", -- (player, text)
	"TradeUpdate", -- (state)
	"Toast", -- (text)
	-- client -> server
	"ChooseStarter",
	"EngageCreature",
	"ThrowOrb",
	"BattleAction",
	"SetLead",
	"SetSprinting",
	"SendGreeting",
	"PlazaInvite", -- (targetPlayer, kind)
	"PlazaRespond", -- (requestId, accepted)
	"TradeOffer", -- (slot)
	"TradeConfirm",
	"TradeCancel",
	"UsePotion", -- (slot)
}

local FOLDER_NAME = "TidewildRemotes"

function Net.init()
	assert(RunService:IsServer(), "Net.init is server-only")
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for _, name in Net.Events do
		local r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

local cache = {}
function Net.get(name: string): RemoteEvent
	local r = cache[name]
	if r then
		return r
	end
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	r = folder:WaitForChild(name) :: RemoteEvent
	cache[name] = r
	return r
end

return Net
