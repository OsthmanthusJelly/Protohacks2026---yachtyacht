-- Server-side boat spawning and VehicleSeat-driven VectorForce/AngularVelocity physics.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local RemoteEvents = require(ReplicatedStorage.Modules.Network.RemoteEvents)
local DataManager = require(script.Parent.DataStoreService)

local ACCELERATION = 1.5 -- how fast speed converges on the throttle target, per second
local MAX_TORQUE_PER_MASS = 2000

-- [Player] = { Model, Root, Seat, Force, Turn, Stats }
local boats = {}
local spawned = Instance.new("BindableEvent")

local VehiclePhysicsService = {}
VehiclePhysicsService.BoatSpawned = spawned.Event -- (player, model, boatId)

function VehiclePhysicsService.GetBoat(player: Player): Model?
	return boats[player] and boats[player].Model
end

-- Plain hull for boats that have no model in ServerStorage.Boats yet.
local function buildFallbackHull(stats): Model
	local model = Instance.new("Model")
	local scale = 1 + (stats.Tier - 1) * 0.5
	local hull = Instance.new("Part")
	hull.Name = "Hull"
	hull.Size = Vector3.new(6, 2, 14) * Vector3.new(scale, 1, scale)
	hull.Color = Color3.fromRGB(245, 245, 245)
	hull.Parent = model

	local seat = Instance.new("VehicleSeat")
	seat.Size = Vector3.new(2, 1, 2)
	seat.CFrame = hull.CFrame * CFrame.new(0, hull.Size.Y / 2 + 0.5, hull.Size.Z / 4)
	seat.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hull
	weld.Part1 = seat
	weld.Parent = hull

	model.PrimaryPart = hull
	return model
end

local function spawnCFrame(player: Player): CFrame?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for _, part in CollectionService:GetTagged("BoatSpawn") do
		local distance = (part.Position - root.Position).Magnitude
		if distance < bestDistance then
			best, bestDistance = part, distance
		end
	end
	return if best then best.CFrame else root.CFrame * CFrame.new(0, 0, -25)
end

function VehiclePhysicsService.Despawn(player: Player)
	local boat = boats[player]
	if boat then
		boats[player] = nil
		boat.Model:Destroy()
	end
	player:SetAttribute("ActiveBoat", nil)
end

function VehiclePhysicsService.Spawn(player: Player, boatId: string): boolean
	local data = DataManager.Get(player)
	local stats = GameConfig.Boats[boatId]
	if not data or not stats or not data.Boats[boatId] or data.Rentals[boatId] then
		return false
	end
	local cframe = spawnCFrame(player)
	if not cframe then
		return false
	end
	VehiclePhysicsService.Despawn(player)

	local templates = ServerStorage:FindFirstChild("Boats")
	local template = templates and templates:FindFirstChild(boatId)
	local model = if template then template:Clone() else buildFallbackHull(stats)
	local root = model.PrimaryPart
	local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
	if not root or not seat then
		warn("Boat " .. boatId .. " needs a PrimaryPart and a VehicleSeat")
		model:Destroy()
		return false
	end

	model:PivotTo(cframe + Vector3.new(0, 4, 0))
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("BoatId", boatId)

	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local force = Instance.new("VectorForce")
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.zero
	force.Attachment0 = attachment
	force.Parent = root
	local turn = Instance.new("AngularVelocity")
	turn.RelativeTo = Enum.ActuatorRelativeTo.World
	turn.AngularVelocity = Vector3.zero -- also holds X/Z at zero, which keeps the boat upright
	turn.Attachment0 = attachment
	turn.Parent = root

	local folder = workspace:FindFirstChild("Boats") or Instance.new("Folder")
	folder.Name = "Boats"
	folder.Parent = workspace
	model.Parent = folder
	turn.MaxTorque = root.AssemblyMass * MAX_TORQUE_PER_MASS

	boats[player] = { Model = model, Root = root, Seat = seat, Force = force, Turn = turn, Stats = stats }
	player:SetAttribute("ActiveBoat", boatId)
	spawned:Fire(player, model, boatId)
	return true
end

local function bestOwnedBoat(data): string?
	local bestId, bestTier = nil, 0
	for boatId in data.Boats do
		local stats = GameConfig.Boats[boatId]
		if stats and not data.Rentals[boatId] and stats.Tier > bestTier then
			bestId, bestTier = boatId, stats.Tier
		end
	end
	return bestId
end

local function addSpawnPrompt(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Spawn / dock boat"
	prompt.ObjectText = "Boat Spawn"
	prompt.MaxActivationDistance = 30 -- spawn points sit out in the water, reachable from the dock
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	-- shortcut: always spawns the best non-rented boat; add a boat picker UI when players want to choose.
	prompt.Triggered:Connect(function(player)
		if boats[player] then
			VehiclePhysicsService.Despawn(player)
			return
		end
		local data = DataManager.Get(player)
		local boatId = data and bestOwnedBoat(data)
		if not boatId then
			RemoteEvents.Notify:FireClient(player, "All your boats are rented out")
		elseif not VehiclePhysicsService.Spawn(player, boatId) then
			RemoteEvents.Notify:FireClient(player, "Could not spawn boat")
		end
	end)
end

local function step(dt: number)
	for player, boat in boats do
		if not boat.Model.Parent then
			boats[player] = nil
			player:SetAttribute("ActiveBoat", nil)
			continue
		end
		local root, seat, stats = boat.Root, boat.Seat, boat.Stats
		local look = root.CFrame.LookVector
		local forward = Vector3.new(look.X, 0, look.Z)
		if forward.Magnitude < 0.01 then
			continue
		end
		forward = forward.Unit
		local speed = root.AssemblyLinearVelocity:Dot(forward)
		local target = seat.ThrottleFloat * stats.MaxSpeed
		boat.Force.Force = forward * (target - speed) * root.AssemblyMass * ACCELERATION
		boat.Turn.AngularVelocity = Vector3.new(0, -seat.SteerFloat * stats.TurnSpeed, 0)
	end
end

function VehiclePhysicsService.Start()
	CollectionService:GetInstanceAddedSignal("BoatSpawn"):Connect(addSpawnPrompt)
	for _, part in CollectionService:GetTagged("BoatSpawn") do
		addSpawnPrompt(part)
	end
	Players.PlayerRemoving:Connect(VehiclePhysicsService.Despawn)
	RunService.Heartbeat:Connect(step)
end

return VehiclePhysicsService
