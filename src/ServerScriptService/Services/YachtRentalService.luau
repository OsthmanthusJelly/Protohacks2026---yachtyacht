-- Passive rentals: a rented boat can't be driven but pays every rental tick.
-- Income = RentalIncome * (1 + customization bonus + booking manager bonus) * gacha multiplier.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local RemoteEvents = require(ReplicatedStorage.Modules.Network.RemoteEvents)
local CustomizationService = require(script.Parent.CustomizationService)
local DataManager = require(script.Parent.DataStoreService)
local GachaService = require(script.Parent.GachaService)

local MANAGER = GameConfig.NPC.BookingManager

local YachtRentalService = {}

function YachtRentalService.GetIncome(player: Player): number
	local data = DataManager.Get(player)
	if not data then
		return 0
	end
	local income = 0
	for boatId in data.Rentals do
		local stats = GameConfig.Boats[boatId]
		if stats then
			local customBonus = CustomizationService.CountFields(data.Customizations[boatId])
				* GameConfig.Rental.CustomizationBonusPerField
			income += stats.RentalIncome * (1 + customBonus + data.Managers * MANAGER.RentalBonus)
		end
	end
	return income * GachaService.GetMultiplier(player)
end

local function setRental(player: Player, boatId: unknown, enabled: unknown)
	local data = DataManager.Get(player)
	if not data or type(boatId) ~= "string" or type(enabled) ~= "boolean" or not data.Boats[boatId] then
		return
	end
	if not enabled then
		data.Rentals[boatId] = nil
		return
	end
	if GameConfig.Boats[boatId].RentalIncome <= 0 then
		RemoteEvents.Notify:FireClient(player, "Nobody wants to rent that boat")
	elseif player:GetAttribute("ActiveBoat") == boatId then
		RemoteEvents.Notify:FireClient(player, "Dock that boat before renting it out")
	else
		data.Rentals[boatId] = true
	end
end

local function hireManager(player: Player)
	local data = DataManager.Get(player)
	if not data or data.Managers >= MANAGER.Max then
		return
	end
	if DataManager.TrySpend(player, MANAGER.Cost) then
		data.Managers += 1
		RemoteEvents.Notify:FireClient(player, "Hired booking manager " .. data.Managers .. "/" .. MANAGER.Max)
	else
		RemoteEvents.Notify:FireClient(player, "Need $" .. MANAGER.Cost .. " to hire a booking manager")
	end
end

function YachtRentalService.Start()
	RemoteEvents.SetRental.OnServerEvent:Connect(setRental)
	RemoteEvents.HireManager.OnServerEvent:Connect(hireManager)

	task.spawn(function()
		while true do
			task.wait(GameConfig.Rental.TickSeconds)
			for _, player in Players:GetPlayers() do
				local income = YachtRentalService.GetIncome(player)
				if income > 0 then
					DataManager.AddCash(player, income)
					RemoteEvents.Notify:FireClient(player, "Rental income: +$" .. math.floor(income))
				end
			end
		end
	end)
end

return YachtRentalService
