-- Weighted crew/pet rolls, inventory, equipping, and the income multiplier from equipped items.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local RemoteEvents = require(ReplicatedStorage.Modules.Network.RemoteEvents)
local DataManager = require(script.Parent.DataStoreService)

local GACHA = GameConfig.Gacha
local rng = Random.new()

-- [itemId] = { Pool, Name, Rarity, IncomeBonus }
local ITEMS = {}
for poolName, pool in GACHA.Pools do
	for id, item in pool.Items do
		assert(not ITEMS[id], "Duplicate gacha item id " .. id)
		assert(GACHA.Rarities[item.Rarity], id .. " has unknown rarity " .. tostring(item.Rarity))
		ITEMS[id] = table.clone(item)
		ITEMS[id].Pool = poolName
	end
	for rarity in GACHA.Rarities do
		local found = false
		for _, item in pool.Items do
			found = found or item.Rarity == rarity
		end
		assert(found, poolName .. " has no " .. rarity .. " item")
	end
end

local GachaService = {}

local function pickWeighted(weights: { [string]: number }): string
	local total = 0
	for _, weight in weights do
		total += weight
	end
	local roll = rng:NextNumber() * total
	local last
	for key, weight in weights do
		if roll < weight then
			return key
		end
		roll -= weight
		last = key
	end
	return last -- float rounding fallback
end

local function setPetAttribute(player: Player, data)
	local pets = {}
	for _, id in data.Equipped do
		if ITEMS[id] and ITEMS[id].Pool == "Pets" then
			table.insert(pets, id)
		end
	end
	-- PetFollowerController reads this on every client.
	player:SetAttribute("EquippedPets", table.concat(pets, ","))
end

function GachaService.GetMultiplier(player: Player): number
	local data = DataManager.Get(player)
	local multiplier = 1
	for _, id in data and data.Equipped or {} do
		if ITEMS[id] then
			multiplier += ITEMS[id].IncomeBonus
		end
	end
	return multiplier
end

local function roll(player: Player, poolName: unknown)
	local data = DataManager.Get(player)
	local pool = type(poolName) == "string" and GACHA.Pools[poolName]
	if not data or not pool then
		return nil, "Invalid pool"
	end
	if #data.Inventory >= GACHA.MaxInventory then
		return nil, "Inventory full"
	end
	if not DataManager.TrySpend(player, pool.Cost) then
		return nil, "Not enough cash"
	end

	local rarity = pickWeighted(GACHA.Rarities)
	local candidates = {}
	for id, item in pool.Items do
		if item.Rarity == rarity then
			table.insert(candidates, id)
		end
	end
	local id = candidates[rng:NextInteger(1, #candidates)]
	table.insert(data.Inventory, id)
	return { Id = id, Name = ITEMS[id].Name, Rarity = rarity }
end

local function equip(player: Player, itemId: unknown, shouldEquip: unknown)
	local data = DataManager.Get(player)
	if not data or type(itemId) ~= "string" or type(shouldEquip) ~= "boolean" then
		return
	end
	local equippedIndex = table.find(data.Equipped, itemId)
	if shouldEquip then
		if equippedIndex or #data.Equipped >= GACHA.MaxEquipped or not table.find(data.Inventory, itemId) then
			return
		end
		table.insert(data.Equipped, itemId)
	elseif equippedIndex then
		table.remove(data.Equipped, equippedIndex)
	end
	setPetAttribute(player, data)
end

function GachaService.Start()
	RemoteEvents.RollGacha.OnServerInvoke = roll
	RemoteEvents.EquipItem.OnServerEvent:Connect(equip)
	DataManager.PlayerLoaded:Connect(setPetAttribute)
end

return GachaService
