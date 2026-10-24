-- Player data lifecycle on standard DataStores. Exports DataManager.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)

local store = DataStoreService:GetDataStore("PlayerData_v1")
local profiles: { [Player]: any } = {}
local loaded = Instance.new("BindableEvent")

local DataManager = {}
DataManager.PlayerLoaded = loaded.Event -- (player, data)

local function template()
	return {
		Cash = GameConfig.StartingCash,
		Unlocks = {}, -- [unlockId] = true
		Boats = { [GameConfig.StartingBoat] = true }, -- [boatId] = true
		Customizations = {}, -- [boatId] = { Color, LedEnabled, LedColor, Flag, Interior }
		Secrets = {}, -- [secretId] = true
		Inventory = {}, -- array of gacha item ids
		Equipped = {}, -- array of gacha item ids
		Managers = 0,
		Rentals = {}, -- [boatId] = true
		PartyAccess = GameConfig.Party.DefaultAccess,
		Furniture = {}, -- array of { Id, X, Z, R }
	}
end

local function key(player: Player)
	return "Player_" .. player.UserId
end

local function retry(fn)
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn("DataStore attempt " .. attempt .. " failed: " .. tostring(result))
		task.wait(attempt * 2)
	end
	return false, nil
end

local function updateLeaderstats(player: Player)
	local stats = player:FindFirstChild("leaderstats")
	local cash = stats and stats:FindFirstChild(GameConfig.Currency.Cash)
	if cash then
		cash.Value = math.floor(profiles[player].Cash)
	end
end

local function load(player: Player)
	local ok, saved = retry(function()
		return store:GetAsync(key(player))
	end)
	if not ok then
		-- Never fall back to defaults here: saving them would wipe the real data.
		player:Kick("Could not load your data. Please rejoin.")
		return
	end
	if not player.Parent then
		return
	end

	local data = template()
	for k, v in saved or {} do
		data[k] = v
	end
	profiles[player] = data

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = GameConfig.Currency.Cash
	cash.Parent = stats
	stats.Parent = player
	updateLeaderstats(player)

	loaded:Fire(player, data)
end

local function save(player: Player)
	local data = profiles[player]
	if data then
		-- shortcut: no session locking, fast server hops can lose a few seconds of progress; move to ProfileService if that shows up.
		retry(function()
			store:SetAsync(key(player), data)
		end)
	end
end

function DataManager.Get(player: Player)
	return profiles[player]
end

function DataManager.AddCash(player: Player, amount: number)
	local data = profiles[player]
	if data then
		-- Kept fractional so small multiplier bonuses on low income still add up.
		data.Cash += amount
		updateLeaderstats(player)
	end
end

function DataManager.TrySpend(player: Player, amount: number): boolean
	local data = profiles[player]
	if not data or data.Cash < amount then
		return false
	end
	data.Cash -= amount
	updateLeaderstats(player)
	return true
end

function DataManager.Start()
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		save(player)
		profiles[player] = nil
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				save(player)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(GameConfig.AutosaveSeconds)
			for player in profiles do
				task.spawn(save, player)
			end
		end
	end)
end

return DataManager
