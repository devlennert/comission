local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")

local GROUP_ID = 895193298 -- 🔴 Replace with your Group ID
local WAIT_TIME = 120   -- 2 minutes in seconds

local player = Players.LocalPlayer

-- Check if the player is already in the group
local function isInGroup()
	local success, inGroup = pcall(function()
		return GroupService:IsInGroup(player.UserId, GROUP_ID)
	end)
	return success and inGroup
end

-- Wait 2 minutes, then prompt if not in group
task.wait(WAIT_TIME)

if not isInGroup() then
	local success, result = pcall(function()
		return GroupService:PromptJoinAsync(GROUP_ID)
	end)

	if success then
		if result == Enum.GroupMembershipStatus.Joined then
			print("Player joined the group!")
		elseif result == Enum.GroupMembershipStatus.JoinRequestPending then
			print("Join request sent")
		elseif result == Enum.GroupMembershipStatus.AlreadyMember then
			print("Already a member")
		else
			print("Did not join or not eligible")
		end
	else
		warn("Prompt failed:", result)
	end
end