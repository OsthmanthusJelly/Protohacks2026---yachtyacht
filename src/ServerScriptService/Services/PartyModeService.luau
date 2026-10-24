-- Party access (Public/Friends/Private), guest teleports, and server-validated furniture grid placement
-- on the "PartyFloor" part inside each player's plot. Grid cell (0,0) is the floor's -X/-Z corner.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local RemoteEvents = require(ReplicatedStorage.Modules.Network.RemoteEvents)
local DataManager = require(script.Parent.DataStoreService)
local TycoonService = require(script.Parent.TycoonService)

local PARTY = GameConfig.Party

local PartyModeService = {}

local function floorOf(player: Player): BasePart?
	local plot = TycoonService.GetPlot(player)
	local floor = plot and plot:FindFirstChild("PartyFloor", true)
	return if floor and floor:IsA("BasePart") then floor else nil
end

local function footprint(item, rotated: boolean): (number, number)
	if rotated then
		return item.Size.Y, item.Size.X
	end
	return item.Size.X, item.Size.Y
end

-- Keep in sync with PartyPlacementController.cellCFrame.
local function cellCFrame(floor: BasePart, x: number, z: number, w: number, d: number, height: number, rotated: boolean)
	local cell = PARTY.CellSize
	local offset = Vector3.new(
		-floor.Size.X / 2 + (x + w / 2) * cell,
		floor.Size.Y / 2 + height / 2,
		-floor.Size.Z / 2 + (z + d / 2) * cell
	)
	return floor.CFrame * CFrame.new(offset) * CFrame.Angles(0, rotated and math.pi / 2 or 0, 0)
end

local function rebuild(player: Player)
	local plot = TycoonService.GetPlot(player)
	local floor = floorOf(player)
	local data = DataManager.Get(player)
	if not plot or not floor or not data then
		return
	end
	local old = plot.Built:FindFirstChild("Furniture")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Furniture"

	local templates = ReplicatedStorage:FindFirstChild("Furniture")
	for index, record in data.Furniture do
		local item = PARTY.Furniture[record.Id]
		if item then
			local w, d = footprint(item, record.R)
			local cframe = cellCFrame(floor, record.X, record.Z, w, d, item.Height, record.R)
			local template = templates and templates:FindFirstChild(record.Id)
			local model
			if template then
				model = template:Clone()
				model:PivotTo(cframe)
			else
				model = Instance.new("Part")
				model.Anchored = true
				model.Size = Vector3.new(item.Size.X * PARTY.CellSize, item.Height, item.Size.Y * PARTY.CellSize)
				model.CFrame = cframe
			end
			model.Name = record.Id
			model:SetAttribute("FurnitureIndex", index)
			model.Parent = folder
		end
	end
	folder.Parent = plot.Built
end

local function place(player: Player, itemId: unknown, x: unknown, z: unknown, rotated: unknown)
	local data = DataManager.Get(player)
	local floor = floorOf(player)
	local item = type(itemId) == "string" and PARTY.Furniture[itemId]
	if not data or not floor or not item then
		return false, "Nothing to place on"
	end
	if type(x) ~= "number" or type(z) ~= "number" or x % 1 ~= 0 or z % 1 ~= 0 or type(rotated) ~= "boolean" then
		return false, "Invalid placement"
	end
	if #data.Furniture >= PARTY.MaxFurniture then
		return false, "Furniture limit reached"
	end

	local w, d = footprint(item, rotated)
	local cols, rows = math.floor(floor.Size.X / PARTY.CellSize), math.floor(floor.Size.Z / PARTY.CellSize)
	if x < 0 or z < 0 or x + w > cols or z + d > rows then
		return false, "Out of bounds"
	end
	for _, record in data.Furniture do
		local other = PARTY.Furniture[record.Id]
		if other then
			local ow, od = footprint(other, record.R)
			if x < record.X + ow and record.X < x + w and z < record.Z + od and record.Z < z + d then
				return false, "Space is taken"
			end
		end
	end
	if not DataManager.TrySpend(player, item.Price) then
		return false, "Need $" .. item.Price
	end

	table.insert(data.Furniture, { Id = itemId, X = x, Z = z, R = rotated })
	rebuild(player)
	return true
end

local function remove(player: Player, index: unknown)
	local data = DataManager.Get(player)
	if data and type(index) == "number" and data.Furniture[index] then
		-- shortcut: no refund on removal, add a partial refund if rearranging feels punishing.
		table.remove(data.Furniture, index)
		rebuild(player)
	end
end

local function setAccess(player: Player, mode: unknown)
	local data = DataManager.Get(player)
	if data and table.find(PARTY.AccessModes, mode) then
		data.PartyAccess = mode
		player:SetAttribute("PartyAccess", mode)
	end
end

local function join(guest: Player, ownerUserId: unknown)
	local owner = type(ownerUserId) == "number" and Players:GetPlayerByUserId(ownerUserId)
	local data = owner and DataManager.Get(owner)
	local floor = owner and floorOf(owner)
	local character = guest.Character
	if not owner or owner == guest or not data or not floor or not character then
		return
	end

	local allowed = data.PartyAccess == "Public"
	if data.PartyAccess == "Friends" then
		local ok, isFriend = pcall(guest.IsFriendsWith, guest, owner.UserId)
		allowed = ok and isFriend
	end
	if not allowed then
		RemoteEvents.Notify:FireClient(guest, owner.DisplayName .. "'s party is " .. data.PartyAccess:lower())
		return
	end
	character:PivotTo(floor.CFrame + Vector3.new(0, floor.Size.Y / 2 + 4, 0))
	RemoteEvents.Notify:FireClient(owner, guest.DisplayName .. " joined your party")
end

function PartyModeService.Start()
	RemoteEvents.PlaceFurniture.OnServerInvoke = place
	RemoteEvents.RemoveFurniture.OnServerEvent:Connect(remove)
	RemoteEvents.SetPartyAccess.OnServerEvent:Connect(setAccess)
	RemoteEvents.JoinParty.OnServerEvent:Connect(join)
	TycoonService.PlotClaimed:Connect(function(player)
		player:SetAttribute("PartyAccess", DataManager.Get(player).PartyAccess)
		rebuild(player)
	end)
end

return PartyModeService
