-- One-time cash rewards for touching hidden parts tagged "SecretCollectible" (attribute SecretId).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local RemoteEvents = require(ReplicatedStorage.Modules.Network.RemoteEvents)
local DataManager = require(script.Parent.DataStoreService)

local SecretDiscoveryService = {}

-- Touched by the player's character, or by a boat they own.
local function playerFromHit(hit: BasePart): Player?
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	local boatOwner = model:GetAttribute("OwnerUserId")
	if boatOwner then
		return Players:GetPlayerByUserId(boatOwner)
	end
	return Players:GetPlayerFromCharacter(model)
end

local function watch(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	part.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		local data = player and DataManager.Get(player)
		local id = part:GetAttribute("SecretId")
		local secret = GameConfig.Secrets[id]
		if not data or not secret or data.Secrets[id] then
			return
		end
		data.Secrets[id] = true
		DataManager.AddCash(player, secret.Cash)
		RemoteEvents.Notify:FireClient(player, "Secret found: " .. secret.Name .. "! +$" .. secret.Cash)
	end)
end

function SecretDiscoveryService.Start()
	CollectionService:GetInstanceAddedSignal("SecretCollectible"):Connect(watch)
	for _, part in CollectionService:GetTagged("SecretCollectible") do
		watch(part)
	end
end

return SecretDiscoveryService
