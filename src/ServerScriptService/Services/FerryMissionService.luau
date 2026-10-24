-- Ferry runs between parts tagged "FerryDock" (attribute Location = GameConfig.Locations key).
-- Board at one dock's prompt, drive your boat to the assigned dock, trigger its prompt to get paid.
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local RemoteEvents = require(ReplicatedStorage.Modules.Network.RemoteEvents)
local DataManager = require(script.Parent.DataStoreService)
local GachaService = require(script.Parent.GachaService)

-- [Player] = { From, To, Passengers, BoatId, Started }
local missions = {}

local FerryMissionService = {}

local function locationName(dock: BasePart): string
	local location = GameConfig.Locations[dock:GetAttribute("Location")]
	return location and location.Name or dock.Name
end

-- shortcut: passengers are NPC clones that appear for a few seconds to show boarding/unboarding; add walking when there are animations.
local function showPassengers(dock: BasePart, count: number, seconds: number)
	local template = ServerStorage:FindFirstChild("Passenger")
	if not template then
		return
	end
	for i = 1, math.min(count, 4) do
		local npc = template:Clone()
		npc:PivotTo(dock.CFrame * CFrame.new((i - 2.5) * 3, 3, 0))
		npc.Parent = workspace
		Debris:AddItem(npc, seconds)
	end
end

local function isDrivingOwnBoat(player: Player): boolean
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if not (seat and seat:IsA("VehicleSeat")) then
		return false
	end
	local boat = seat:FindFirstAncestorOfClass("Model")
	return boat ~= nil and boat:GetAttribute("OwnerUserId") == player.UserId
end

local function cancel(player: Player)
	if missions[player] then
		missions[player] = nil
		RemoteEvents.FerryUpdate:FireClient(player, "Cancelled")
	end
end

local function start(player: Player, dock: BasePart)
	local boatId = player:GetAttribute("ActiveBoat")
	local stats = boatId and GameConfig.Boats[boatId]
	if not stats then
		RemoteEvents.Notify:FireClient(player, "Spawn a boat first")
		return
	end
	local destinations = {}
	for _, other in CollectionService:GetTagged("FerryDock") do
		if other ~= dock and other:IsA("BasePart") then
			table.insert(destinations, other)
		end
	end
	if #destinations == 0 then
		return
	end

	local to = destinations[math.random(#destinations)]
	missions[player] = { From = dock, To = to, Passengers = stats.Capacity, BoatId = boatId, Started = os.clock() }
	showPassengers(dock, stats.Capacity, 2)
	RemoteEvents.FerryUpdate:FireClient(player, "Started", {
		Destination = locationName(to),
		Position = to.Position,
		Passengers = stats.Capacity,
	})
end

local function complete(player: Player, mission)
	if not isDrivingOwnBoat(player) then
		RemoteEvents.Notify:FireClient(player, "Arrive by boat to drop off passengers")
		return
	end
	local distance = (mission.From.Position - mission.To.Position).Magnitude
	local stats = GameConfig.Boats[mission.BoatId]
	if os.clock() - mission.Started < distance / (stats.MaxSpeed * GameConfig.Ferry.MinTripSpeedFactor) then
		cancel(player)
		return
	end

	missions[player] = nil
	local payout = math.floor(
		distance * mission.Passengers * GameConfig.Ferry.PayPerStudPerPassenger * GachaService.GetMultiplier(player)
	)
	DataManager.AddCash(player, payout)
	showPassengers(mission.To, mission.Passengers, 5)
	RemoteEvents.FerryUpdate:FireClient(player, "Completed", { Payout = payout })
end

local function addDock(dock: Instance)
	if not dock:IsA("BasePart") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Ferry passengers"
	prompt.ObjectText = locationName(dock)
	prompt.MaxActivationDistance = 30
	prompt.RequiresLineOfSight = false
	prompt.Parent = dock
	prompt.Triggered:Connect(function(player)
		local mission = missions[player]
		if not mission then
			start(player, dock)
		elseif mission.To == dock then
			complete(player, mission)
		else
			RemoteEvents.Notify:FireClient(player, "Passengers are going to " .. locationName(mission.To))
		end
	end)
end

function FerryMissionService.Start()
	CollectionService:GetInstanceAddedSignal("FerryDock"):Connect(addDock)
	for _, dock in CollectionService:GetTagged("FerryDock") do
		addDock(dock)
	end

	local function watchBoat(player: Player)
		player:GetAttributeChangedSignal("ActiveBoat"):Connect(function()
			cancel(player)
		end)
	end
	Players.PlayerAdded:Connect(watchBoat)
	for _, player in Players:GetPlayers() do
		watchBoat(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		missions[player] = nil
	end)
end

return FerryMissionService
