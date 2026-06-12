local module = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Network = require(ReplicatedStorage.Modules.Network)
local DailyRewards = require(ReplicatedStorage.Modules.DailyRewards)
local ChairInfo = require(ReplicatedStorage.Modules.ChairInfo)
local Player = game.Players.LocalPlayer
local PlayerGui = Player.PlayerGui
local UI = PlayerGui.UI
local DailyFrame = UI.DailyRewards
local Days = DailyFrame.Days
local ClaimButton = DailyFrame.Claim
local SkipButton = DailyFrame.Skip.Btn

DailyFrame.Visible = true

function module.UpdateDaily()
	local currentDay = Player:WaitForChild("DailyDay").Value
	local lastClaim = Player:WaitForChild("DailyLastClaim").Value
	local currentTime = os.time()

	for i = 1, 7 do
		local dayFrame = Days:FindFirstChild(tostring(i))
		if dayFrame then
			local dayLabel = dayFrame.Day
			local reward = dayFrame.Reward
			local amnt = reward.Amnt
			local btn = reward.Btn

			dayLabel.Text = "Day " .. i

			local rewardInfo = DailyRewards[i]
			if rewardInfo.RewardType == "Cash" then
				amnt.Text = "$" .. rewardInfo.Amount
			elseif rewardInfo.RewardType == "Chair" then
				amnt.Text = rewardInfo.Name
				-- Show the chair's NEW boost string on the reward card (was "% Luck").
				local boostLabel = reward:FindFirstChild("Luck")
				if boostLabel then
					boostLabel.Text = ChairInfo.GetBoostString(rewardInfo.Name)
				end
			end

			if i < currentDay then
				btn.ImageColor3 = Color3.fromRGB(0, 255, 0)
				dayLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
			else
				btn.ImageColor3 = Color3.fromRGB(255, 255, 255)
				dayLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		end
	end

	if currentTime - lastClaim >= DailyRewards.DailyTimer then
		ClaimButton.txt.Text = "CLAIM!"
	else
		ClaimButton.txt.Text = "CLAIMED!"
	end
end

ClaimButton.MouseButton1Click:Connect(function()
	local currentTime = os.time()
	local lastClaim = Player.DailyLastClaim.Value

	if currentTime - lastClaim >= DailyRewards.DailyTimer then
		Network.send("ClaimDaily")
	end
end)

DailyFrame.Exit.MouseButton1Click:Connect(function()
	DailyFrame.Visible = false
end)

Network.onClient("DailyClaimResult",function(success)
	if success then
		module.UpdateDaily()
	end
end)

Player.DailyDay.Changed:Connect(function()
	module.UpdateDaily()
end)

Player.DailyLastClaim.Changed:Connect(function()
	module.UpdateDaily()
end)

task.spawn(function()
	while true do
		task.wait(1)
		local currentTime = os.time()
		local lastClaim = Player.DailyLastClaim.Value

		if currentTime - lastClaim >= DailyRewards.DailyTimer then
			if ClaimButton.txt.Text ~= "CLAIM!" then
				ClaimButton.txt.Text = "CLAIM!"
			end
		else
			if ClaimButton.txt.Text ~= "CLAIMED!" then
				ClaimButton.txt.Text = "CLAIMED!"
			end
		end
	end
end)

module.UpdateDaily()

return module