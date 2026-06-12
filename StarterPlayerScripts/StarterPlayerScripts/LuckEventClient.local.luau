-- LuckEventClient  (LocalScript — place in StarterPlayerScripts)
-- Handles the client side of the server-wide 2x Luck event:
--   • Updates PlayerGui.UI.EventDisplay with "2X LUCK" or "2X LUCK IN M:SS"
--   • Swaps Lighting skies between Normal and LuckySky
--   • Counts down locally between server syncs so the display stays smooth

-- ─── Config (mirror these in DataHandler if you change them) ─────────────────
-- These are only used for the initial display before the first server sync
-- arrives. The server is always authoritative — these just prevent a blank label.
local EVENT_CYCLE    = 15 * 60   -- total cycle in seconds  (15 min = 900)
local EVENT_DURATION = 5 * 60    -- active duration in secs  (5 min  = 300)
-- ─────────────────────────────────────────────────────────────────────────────

local Players           = game:GetService("Players")
local Lighting          = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage:WaitForChild("Modules").Network)

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Wait for the UI and the label to be ready
local ui      = playerGui:WaitForChild("UI")
local display = ui:WaitForChild("Event")

-- ─── Sky references ──────────────────────────────────────────────────────────
-- Lighting
--   ├─ Normal        (Sky — active by default)
--   └─ SkyHolder     (Folder)
--        └─ LuckySky (Sky — swapped in during the event)
-- sky swap disabled
-- ─────────────────────────────────────────────────────────────────────────────

local isEventActive  = false
local timeRemaining  = 0   -- seconds until next state flip, maintained locally

-- ─── Sky helpers ─────────────────────────────────────────────────────────────
local function activateSky() end

local function deactivateSky() end
-- ─────────────────────────────────────────────────────────────────────────────

-- ─── Display helper ──────────────────────────────────────────────────────────
local function formatCountdown(secs)
	local s = math.max(0, math.floor(secs))
	local m = math.floor(s / 60)
	s = s % 60
	return string.format("%d:%02d", m, s)
end

local function refreshDisplay()
	if isEventActive then
		display.Text = "2X LUCK"
	else
		display.Text = "2X LUCK IN " .. formatCountdown(timeRemaining)
	end
end
-- ─────────────────────────────────────────────────────────────────────────────

-- ─── Server sync ─────────────────────────────────────────────────────────────
-- The server sends LuckEvent_Update whenever the state changes AND once on join.
-- active    : bool   — whether the 2x luck event is currently running
-- remaining : number — seconds until the next state flip
Network.onClient("LuckEvent_Update", function(active, remaining)
	local wasActive = isEventActive
	isEventActive  = active
	timeRemaining  = math.max(0, math.floor(remaining))

	refreshDisplay()

	if active and not wasActive then
		activateSky()
	elseif not active and wasActive then
		deactivateSky()
	end

	print("[LUCKEVENT] Synced from server | active:", active, "| remaining:", timeRemaining)
end)
-- ─────────────────────────────────────────────────────────────────────────────

-- ─── Local countdown ─────────────────────────────────────────────────────────
-- Ticks every second so the displayed countdown stays live between server syncs.
-- The server corrects any drift automatically on each state-change broadcast.
task.spawn(function()
	while true do
		task.wait(1)
		if timeRemaining > 0 then
			timeRemaining = timeRemaining - 1
		end
		refreshDisplay()
	end
end)
-- ─────────────────────────────────────────────────────────────────────────────

-- ─── Seed initial display before the first server packet arrives ──────────────
-- Uses the same UTC-based formula the server uses so the label isn't blank.
do
	local t       = os.time() % EVENT_CYCLE
	local active  = t < EVENT_DURATION
	local rem     = active and (EVENT_DURATION - t) or (EVENT_CYCLE - t)
	isEventActive = active
	timeRemaining = rem
	refreshDisplay()
	if active then
		activateSky()
	end
end
-- ─────────────────────────────────────────────────────────────────────────────

print("[LUCKEVENT] LuckEventClient loaded")