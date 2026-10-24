-- Server creates every remote under ReplicatedStorage.Remotes; clients wait for them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	"Notify", -- server -> client: (text)
	"FerryUpdate", -- server -> client: (kind, info)
	"SetRental", -- client -> server: (boatId, enabled)
	"HireManager", -- client -> server: ()
	"ApplyCustomization", -- client -> server: (boatId, custom)
	"EquipItem", -- client -> server: (itemId, equip)
	"SetPartyAccess", -- client -> server: (mode)
	"JoinParty", -- client -> server: (ownerUserId)
	"RemoveFurniture", -- client -> server: (index)
}
local FUNCTIONS = {
	"RollGacha", -- (poolName) -> result or nil, error
	"PlaceFurniture", -- (itemId, x, z, rotated) -> ok, error
}

local folder
if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in EVENTS do
		Instance.new("RemoteEvent", folder).Name = name
	end
	for _, name in FUNCTIONS do
		Instance.new("RemoteFunction", folder).Name = name
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

local RemoteEvents = {}
for _, name in EVENTS do
	RemoteEvents[name] = folder:WaitForChild(name)
end
for _, name in FUNCTIONS do
	RemoteEvents[name] = folder:WaitForChild(name)
end

return RemoteEvents
