-- Plot ownership, physical unlock buttons (wooden dock -> private island), and passive income.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local RemoteEvents = require(ReplicatedStorage.Modules.Network.RemoteEvents)
local DataManager = require(script.Parent.DataStoreService)
local GachaService = require(script.Parent.GachaService)

-- [unlockId] = { unlock, requires = previous unlock id }
local UNLOCKS = {}
for i, unlock in GameConfig.DockUnlocks do
	local previous = GameConfig.DockUnlocks[i - 1]
	UNLOCKS[unlock.Id] = { unlock = unlock, requires = previous and previous.Id }
end

local plots: { [Player]: Model } = {}
local claimed = Instance.new("BindableEvent")

local TycoonService = {}
TycoonService.PlotClaimed = claimed.Event -- (player, plot)

function TycoonService.GetPlot(player: Player): Model?
	return plots[player]
end

function TycoonService.GetIncome(player: Player): number
	local data = DataManager.Get(player)
	if not data then
		return 0
	end
	local income = 0
	for _, unlock in GameConfig.DockUnlocks do
		if data.Unlocks[unlock.Id] then
			income += unlock.Income
		end
	end
	return income * GachaService.GetMultiplier(player)
end

local function buttonsOf(plot: Model)
	local buttons = {}
	for _, part in plot:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("UnlockId") then
			table.insert(buttons, part)
		end
	end
	return buttons
end

local function refreshButtons(plot: Model, data)
	for _, button in buttonsOf(plot) do
		local entry = UNLOCKS[button:GetAttribute("UnlockId")]
		local available = data ~= nil
			and entry ~= nil
			and not data.Unlocks[entry.unlock.Id]
			and (entry.requires == nil or data.Unlocks[entry.requires] == true)
		button.Transparency = available and 0 or 1
		button.CanCollide = available
		button.CanTouch = available
	end
end

local function build(plot: Model, unlockId: string)
	-- Templates are authored around the origin and placed relative to the plot pivot.
	local folder = ServerStorage:FindFirstChild("Unlocks")
	local template = folder and folder:FindFirstChild(unlockId)
	if template then
		local model = template:Clone()
		model:PivotTo(plot:GetPivot() * template:GetPivot())
		model.Parent = plot.Built
	end
end

function TycoonService.Purchase(player: Player, unlockId: string): boolean
	local data = DataManager.Get(player)
	local entry = UNLOCKS[unlockId]
	local plot = plots[player]
	if not data or not entry or not plot or data.Unlocks[unlockId] then
		return false
	end
	if entry.requires and not data.Unlocks[entry.requires] then
		return false
	end
	if not DataManager.TrySpend(player, entry.unlock.Price) then
		RemoteEvents.Notify:FireClient(player, "Need $" .. entry.unlock.Price .. " for " .. entry.unlock.Name)
		return false
	end

	data.Unlocks[unlockId] = true
	if entry.unlock.Boat then
		data.Boats[entry.unlock.Boat] = true
		RemoteEvents.Notify:FireClient(player, "New boat unlocked: " .. GameConfig.Boats[entry.unlock.Boat].Name)
	end
	build(plot, unlockId)
	refreshButtons(plot, data)
	return true
end

local function claimPlot(player: Player, data)
	local plotsFolder = workspace:FindFirstChild("Plots")
	for _, plot in plotsFolder and plotsFolder:GetChildren() or {} do
		if plot:IsA("Model") and not plot:GetAttribute("Owner") then
			plot:SetAttribute("Owner", player.UserId)
			plots[player] = plot

			local built = Instance.new("Folder")
			built.Name = "Built"
			built.Parent = plot
			for _, unlock in GameConfig.DockUnlocks do
				if data.Unlocks[unlock.Id] then
					build(plot, unlock.Id)
				end
			end
			refreshButtons(plot, data)
			claimed:Fire(player, plot)
			return
		end
	end
	warn("No free plot for " .. player.Name)
end

local function releasePlot(player: Player)
	local plot = plots[player]
	if plot then
		plots[player] = nil
		plot:SetAttribute("Owner", nil)
		plot.Built:Destroy()
		refreshButtons(plot, nil)
	end
end

function TycoonService.Start()
	local plotsFolder = workspace:FindFirstChild("Plots")
	for _, plot in plotsFolder and plotsFolder:GetChildren() or {} do
		refreshButtons(plot, nil)
		for _, button in buttonsOf(plot) do
			local debounce = {}
			button.Touched:Connect(function(hit)
				local player = Players:GetPlayerFromCharacter(hit.Parent)
				if player and plots[player] == plot and not debounce[player] then
					debounce[player] = true
					TycoonService.Purchase(player, button:GetAttribute("UnlockId"))
					task.wait(0.5)
					debounce[player] = nil
				end
			end)
		end
	end

	DataManager.PlayerLoaded:Connect(claimPlot)
	Players.PlayerRemoving:Connect(releasePlot)

	task.spawn(function()
		while true do
			task.wait(GameConfig.IncomeTickSeconds)
			for _, player in Players:GetPlayers() do
				DataManager.AddCash(player, TycoonService.GetIncome(player) * GameConfig.IncomeTickSeconds)
			end
		end
	end)
end

return TycoonService
