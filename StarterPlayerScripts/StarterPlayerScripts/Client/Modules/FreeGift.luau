local module = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GroupService      = game:GetService("GroupService")
local Network           = require(ReplicatedStorage.Modules.Network)
local ButtonsHandler    = require(script.Parent.ButtonsHandler)

local player    = game.Players.LocalPlayer
local playerGui = player.PlayerGui
local UI        = playerGui:WaitForChild("UI")

-- UI references
local Right       = UI:WaitForChild("Right")
local FreeBtn     = Right:WaitForChild("Free")        -- TextButton in UI.Right
local FreeGift    = UI:WaitForChild("FreeGift")       -- gift frame in UI
local Container   = FreeGift:WaitForChild("Container")
local ClaimButton = Container:WaitForChild("ClaimButton")
local ButtonLabel = ClaimButton:WaitForChild("TextLabel")

local GROUP_ID = 1049098079

-- State
local inGame     = false
local hasClaimed = false
local inGroup    = false

-- ─────────────────────────────────────────────
-- Visibility helpers
-- ─────────────────────────────────────────────
local function updateVisibility()
	Right.Visible   = not inGame
	FreeBtn.Visible = not hasClaimed
end

-- Closes the FreeGift frame properly (blur off, FOV back, bottom bar hidden)
-- then hides the Free button permanently.
local function closeFreeGiftProperly()
	if FreeGift.Visible then
		ButtonsHandler.ShowButtons()
		ButtonsHandler.CloseFrame(FreeGift)
	end
	FreeBtn.Visible = false
end

-- ─────────────────────────────────────────────
-- Requirements / button label
-- ─────────────────────────────────────────────
local function setRequirementsDone()
	for _, child in Container:GetChildren() do
		if child.Name == "RequirementsFrame" then
			child.BackgroundColor3       = Color3.fromRGB(0, 255, 1)
			child.BackgroundTransparency = 0.4
		end
	end
	ButtonLabel.Text = "CLAIM"
end

local function setRequirementsPending()
	ButtonLabel.Text = "JOIN GROUP"
end

-- ─────────────────────────────────────────────
-- Group membership check
-- Runs on load and every 15s so the button flips
-- to CLAIM the moment the player joins the group,
-- whether the frame is open or not.
-- ─────────────────────────────────────────────
local function checkGroup()
	if inGroup or hasClaimed then return end
	local ok, result = pcall(function()
		return player:IsInGroup(GROUP_ID)
	end)
	if ok and result then
		inGroup = true
		setRequirementsDone()
		print("[FREEGIFT] In group — button set to CLAIM")
	end
end

task.spawn(checkGroup)

task.spawn(function()
	while true do
		task.wait(15)
		if hasClaimed then break end
		checkGroup()
	end
end)

-- ─────────────────────────────────────────────
-- Server → client events
-- ─────────────────────────────────────────────

-- Fired on join and again after claiming.
-- claimed = true  → already taken, close and hide everything permanently.
-- claimed = false → available, show Free button if not mid-game.
Network.onClient("FreeGiftStatus", function(claimed)
	if claimed then
		hasClaimed = true
		print("[FREEGIFT] Already claimed — hiding")
		closeFreeGiftProperly()
	else
		FreeBtn.Visible = not inGame
	end
end)

-- Game started → hide all of UI.Right
Network.onClient("Cases_CamToTableCam", function()
	inGame = true
	Right.Visible = false
end)

-- Game ended → restore UI.Right (Free only if not yet claimed)
Network.onClient("Cases_TpToTable", function()
	inGame = false
	updateVisibility()
end)

Network.onClient("Cases_CamToNormal", function()
	inGame = false
	updateVisibility()
end)

-- ─────────────────────────────────────────────
-- Claim button
-- ─────────────────────────────────────────────
ClaimButton.MouseButton1Click:Connect(function()
	if hasClaimed then return end

	if ButtonLabel.Text == "CLAIM" then
		Network.send("GiveFreeGift")
		-- server will send FreeGiftStatus=true on success, or a Notify warning on failure

	elseif ButtonLabel.Text == "JOIN GROUP" then
		-- Prompt join; flip to CLAIM immediately if they accept
		local ok, result = pcall(function()
			return GroupService:PromptJoinAsync(GROUP_ID)
		end)
		if ok and result then
			inGroup = true
			setRequirementsDone()
		end
	end
end)

-- ─────────────────────────────────────────────
-- Initial state — hidden until FreeGiftStatus arrives from the server
-- so already-claimed players never see a flash of the gift UI
-- ─────────────────────────────────────────────
FreeGift.Visible = false
FreeBtn.Visible  = false
setRequirementsPending()

print("[FREEGIFT] LocalScript loaded")

return module