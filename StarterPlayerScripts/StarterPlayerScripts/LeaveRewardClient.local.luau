-- LeaveRewardClient  (LocalScript — place in StarterPlayerScripts or StarterGui)
-- Handles the ESC / leave-detection UI flow:
--   • ESC pressed → Roblox default menu opens AND we show our frame on top:
--       canClaim = true  → LeaveRewardFrame (Claim button)
--       canClaim = false → LeaveFrame
--   • Player clicks Resume in the default Roblox ESC menu → GuiService.MenuClosed
--       fires and we hide whichever frame is showing.
--   • Player clicks Claim → reward sent to server, frame hides.
--
-- Network events consumed:
--   LeaveReward_Status(canClaim: bool)   ← server on join / after claim
--   LeaveReward_Result(success: bool)    ← server after claim attempt
-- Network events sent:
--   LeaveReward_Claim                    → server

local Players    = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local RS         = game:GetService("ReplicatedStorage")

local player  = Players.LocalPlayer
local Network = require(RS:WaitForChild("Modules"):WaitForChild("Network"))

-- ─── UI References ────────────────────────────────────────────────────────────

local ui               = player.PlayerGui:WaitForChild("UI")
local leaveFrame       = ui:WaitForChild("LeaveFrame")
local leaveRewardFrame = ui:WaitForChild("LeaveRewardFrame")
local claimBtn         = leaveRewardFrame:WaitForChild("Claim")

leaveFrame.Visible       = false
leaveRewardFrame.Visible = false

-- ─── State ────────────────────────────────────────────────────────────────────

local canClaim = false  -- set by server on join / after claim

-- ─── Menu open → show our frame ──────────────────────────────────────────────

GuiService.MenuOpened:Connect(function()
	if canClaim then
		leaveRewardFrame.Visible = true
		leaveFrame.Visible       = false
	else
		leaveFrame.Visible       = true
		leaveRewardFrame.Visible = false
	end
end)

-- ─── Menu closed (Resume clicked) → hide our frame ───────────────────────────

GuiService.MenuClosed:Connect(function()
	leaveFrame.Visible       = false
	
end)

-- ─── Claim Button ─────────────────────────────────────────────────────────────

claimBtn.MouseButton1Click:Connect(function()
	if not canClaim then return end
	canClaim = false
	leaveRewardFrame.Visible = false
	Network.send("LeaveReward_Claim")
end)

-- ─── Network: status from server ─────────────────────────────────────────────

Network.onClient("LeaveReward_Status", function(claimable)
	canClaim = claimable
end)

Network.onClient("LeaveReward_Result", function(success)
	if not success then
		canClaim = false
		leaveFrame.Visible       = false
		leaveRewardFrame.Visible = false
	end
end)