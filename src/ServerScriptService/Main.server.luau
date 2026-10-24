--[[
World setup the services expect (build these in Studio):
  workspace.Plots/<Model>        one Model per player plot; buttons inside are BaseParts with attribute UnlockId,
                                 plus an optional BasePart named "PartyFloor" for furniture
  ServerStorage.Unlocks/<id>     optional unlock models, authored around the origin
  ServerStorage.Boats/<boatId>   optional unanchored boat models with a PrimaryPart and a VehicleSeat
  ServerStorage.Passenger        optional NPC model for ferry passengers
  ReplicatedStorage.Pets/<id>, ReplicatedStorage.Furniture/<id>   optional models
  Tags: "FerryDock" and "BoatSpawn" parts (attribute Location), "SecretCollectible" parts (attribute SecretId)
Missing optional models fall back to plain parts.
If workspace.Plots doesn't exist, WorldBuilder generates all of the above.
]]
local Services = script.Parent.Services

-- Must run before services start: they scan the world for plots and tagged parts.
require(Services.WorldBuilder).Build()

local DataManager = require(Services.DataStoreService)
local services = {
	require(Services.GachaService),
	require(Services.TycoonService),
	require(Services.SecretDiscoveryService),
	require(Services.VehiclePhysicsService),
	require(Services.CustomizationService),
	require(Services.FerryMissionService),
	require(Services.YachtRentalService),
	require(Services.PartyModeService),
}

for _, service in services do
	service.Start()
end
-- Last, so every service is listening before the first PlayerLoaded fires.
DataManager.Start()
