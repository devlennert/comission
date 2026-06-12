local module = {}

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Network             = require(ReplicatedStorage.Modules.Network)
local PlaytimeRewardsInfo = require(ReplicatedStorage.Modules.PlaytimeRewards)

local Player        = game.Players.LocalPlayer
local PlayerGui     = Player.PlayerGui
local UI            = PlayerGui.UI
local PlaytimeFrame = UI.PlaytimeFrame
local RewardsList   = PlaytimeFrame.RewardsList

local sessionStart    = os.time()
local claimedRewards  = {}   -- [index] = true once claimed this session
local notifiedRewards = {}   -- [index] = true once we've fired the "ready" notify

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function formatTime(totalSeconds)
	local m = math.floor(totalSeconds / 60)
	local s = totalSeconds % 60
	return string.format("%02d:%02d", m, s)
end

local function getAmountText(info)
	if info.RewardType == "Cash" then
		return "$" .. tostring(info.Amount)
	elseif info.RewardType == "OPRoll" then
		return info.Amount .. "x OP Roll"
	elseif info.RewardType == "SuperRoll" then
		return info.Amount .. "x Super Roll"
	elseif info.RewardType == "Chair" then
		return info.ChairName .. " Chair"
	end
	return "Reward"
end

-- ── Display update ────────────────────────────────────────────────────────────

local function updateDisplay()
	local elapsed = os.time() - sessionStart

	for i = 1, 12 do
		local rewardFrame = RewardsList:FindFirstChild(tostring(i))
		if not rewardFrame then continue end

		local claimBtn      = rewardFrame:FindFirstChild("ClaimButton")
		local amntLabel     = rewardFrame:FindFirstChild("Amount")
		local timeLabel     = claimBtn and claimBtn:FindFirstChild("TimeRemaining")
		local rewardInfo    = PlaytimeRewardsInfo[i]

		if not rewardInfo then continue end

		-- Always set the reward label
		if amntLabel then
			amntLabel.Text = getAmountText(rewardInfo)
		end

		if claimedRewards[i] then
			-- ── Claimed ──────────────────────────────────────────────────────
			if timeLabel  then timeLabel.Text  = "✓ DONE" end
			if claimBtn   then claimBtn.ImageColor3 = Color3.fromRGB(0, 200, 0) end

		elseif elapsed >= rewardInfo.TimeReq then
			-- ── Ready to claim ───────────────────────────────────────────────
			if timeLabel  then timeLabel.Text  = "CLAIM!" end
			if claimBtn   then claimBtn.ImageColor3 = Color3.fromRGB(255, 200, 0) end

			-- Fire one notification per reward
			if not notifiedRewards[i] then
				notifiedRewards[i] = true
				Network.send("PlaytimeNotify", i)
			end
		else
			-- ── Counting down ────────────────────────────────────────────────
			local remaining = rewardInfo.TimeReq - elapsed
			if timeLabel  then timeLabel.Text  = formatTime(remaining) end
			if claimBtn   then claimBtn.ImageColor3 = Color3.fromRGB(120, 120, 120) end
		end
	end
end

-- ── Claim buttons ─────────────────────────────────────────────────────────────

for i = 1, 12 do
	local rewardFrame = RewardsList:FindFirstChild(tostring(i))
	if not rewardFrame then continue end
	local claimBtn = rewardFrame:FindFirstChild("ClaimButton")
	if not claimBtn then continue end

	claimBtn.MouseButton1Click:Connect(function()
		if claimedRewards[i] then return end
		local elapsed = os.time() - sessionStart
		if elapsed >= PlaytimeRewardsInfo[i].TimeReq then
			Network.send("ClaimPlaytime", i)
		end
	end)
end

-- ── Network responses ─────────────────────────────────────────────────────────

Network.onClient("PlaytimeClaimResult", function(index, success)
	if success then
		claimedRewards[index] = true
		updateDisplay()
	end
end)

-- ── Update loop (1 s tick) ────────────────────────────────────────────────────

task.spawn(function()
	while true do
		task.wait(1)
		updateDisplay()
	end
end)

updateDisplay()

return module