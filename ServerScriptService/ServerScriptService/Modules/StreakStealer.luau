local module = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local Network           = require(ReplicatedStorage.Modules.Network)

Network.define("StealCash_Request")
Network.define("StealCashSuccess")
Network.define("StealCashVictim")

local STEAL_PERCENT = 1.0  -- steal 25% of target's cash

local pendingTargets   = {}
local requestCooldowns = {}
local DataHandler

function module.SetDataHandler(handler)
	DataHandler = handler
end

function module.GetAndClearTarget(buyer)
	local target = pendingTargets[buyer.UserId]
	pendingTargets[buyer.UserId] = nil
	return target
end

-- Keep these stubs so old DataHandler references don't break
function module.IsPlayerInGame(player) return false end
function module.SetPlayerInGame(player, inGame) end

Network.onServer("StealCash_Request", function(buyer, data)
	local targetUserId = data and data.targetUserId
	if not targetUserId then return end

	local uid = buyer.UserId
	if requestCooldowns[uid] then return end
	requestCooldowns[uid] = true
	task.delay(3, function() requestCooldowns[uid] = nil end)

	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == buyer then return end

	local cashVal = target:FindFirstChild("leaderstats") and target.leaderstats:FindFirstChild("Cash")
	if not cashVal or cashVal.Value <= 0 then
		Network.sendToClient(buyer, "Notify", "💰 They have no cash!", "Warning")
		return
	end

	pendingTargets[buyer.UserId] = target
end)

function module.ExecuteSteal(buyer, target)
	if not target or not target.Parent then return end
	if not DataHandler then return end

	local targetProfile = DataHandler.GetProfile(target)
	if not targetProfile or targetProfile.Data.Cash <= 0 then return end

	local stolen = math.max(1, math.floor(targetProfile.Data.Cash * STEAL_PERCENT))

	-- Remove from target
	DataHandler.RemoveCurrency(target, stolen, "Cash")

	-- Add to buyer without applying their cash multiplier (raw transfer)
	local buyerProfile = DataHandler.GetProfile(buyer)
	if buyerProfile then
		buyerProfile.Data.Cash += stolen
		local ls = buyer:FindFirstChild("leaderstats")
		if ls and ls:FindFirstChild("Cash") then
			ls.Cash.Value = buyerProfile.Data.Cash
		end
	end

	Network.sendToClient(buyer, "StealCashSuccess", { amount = stolen, fromName = target.Name })
	Network.sendToClient(target, "StealCashVictim", { byName = buyer.Name })
end

Players.PlayerRemoving:Connect(function(player)
	pendingTargets[player.UserId]   = nil
	requestCooldowns[player.UserId] = nil
end)

return module
