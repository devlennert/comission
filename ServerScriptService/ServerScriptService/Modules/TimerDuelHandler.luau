--[[
	TimerDuelHandler  (ServerScriptService.Modules)
	2-player timer duel + optional AI opponent disguised as a random friend.

	Both seats fill -> pre-game countdown -> "GO" -> alternating turns (camera to the
	active side, 3-2-1, climbing timer the player slams to stop) -> bust (over TARGET)
	or exact (on TARGET) ends the round -> best-of-3 -> payout.

	When a player is alone at a table they can request an AI duel (RequestAIDuel):
	we pull a random friend, spawn an NPC wearing that friend's avatar/name in the
	opposite seat, and the server plays that side automatically.

	Self-initialises on require (the Loader requires every module in this folder).
]]

local RS        = game:GetService("ReplicatedStorage")
local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris    = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local Network    = require(RS.Modules.Network)

local module = {}
local DataHandler  -- resolved at the bottom
local ChairsFolder = RS:WaitForChild("Assets"):WaitForChild("Chairs")

-- ═════ CONFIG ═════
local CONFIG = {
	TARGET_MIN      = 5,      -- per-round target is randomized in [MIN, MAX] (whole seconds)
	TARGET_MAX      = 12,
	EXACT_TOL       = 0.05,
	PRE_COUNTDOWN   = 7,
	WINS_NEEDED     = 2,      -- best-of-3
	TURN_TIMEOUT    = 15,
	REWARD_CASH     = 100,
	VS_INTRO_HOLD   = 5.4,    -- seconds the VS reveal stays up before turn 1 (5-piece assemble)
	AUTO_SLAM_OVERSHOOT = 3,  -- if a human lingers this many seconds past TARGET, server force-slams (bust)
	FOLDERS         = {"Tables"},
	-- AI opponent tuning (per AI turn). Higher difficulty = the AI busts less
	-- (gives away fewer free rounds) and plays its "safe" stops much closer to the
	-- target (leaves you less room), and threatens the on-the-dot win more often.
	AI_BUST_CHANCE  = 0.07,   -- chance it overshoots and busts (lowered: fewer gifts)
	AI_EXACT_CHANCE = 0.08,   -- chance it lands on-the-dot (raised: more pressure)
	AI_SAFE_MIN     = 0.05,   -- safe stop lands at least this far under target
	AI_SAFE_MAX     = 0.9,    -- ...and at most this far under (tight margin = hard)
	AI_CLUTCH_BONUS = 0.05,   -- extra exact-chance per round the AI is BEHIND
	-- Solo "Risk" mode (RiskMode tables): one shot, must land on the dot.
	RISK_FOLDER      = "RiskMode",
	RISK_REWARD_MULT = 3,      -- win pays this x REWARD_CASH (3 x 100 = 300)
	RISK_EXACT_TOL   = 0.08,   -- on-the-dot tolerance for risk (duel uses 0.05)
	BUST_SOUND_ID     = "",  -- empty: LostSFX sting covers the bust sound. Put an id here for an EXTRA positional boom.
	BUST_SOUND_VOLUME = 1,
}

local function pickRandomTarget()
	return math.random(CONFIG.TARGET_MIN, CONFIG.TARGET_MAX)
end

local COLOR_P1_HEX = "rgb(225,55,55)"
local COLOR_P2_HEX = "rgb(70,130,240)"
local COLOR_P1 = Color3.fromRGB(225, 55, 55)
local COLOR_P2 = Color3.fromRGB(70, 130, 240)

for _, r in ipairs({
	"DuelPreGame", "DuelGo", "DuelShowSide", "DuelTurnCountdown",
	"DuelTimerStart", "DuelTimerStop", "DuelEnd", "DuelReset",
	"DuelRoundStart", "DuelSlam", "RequestAIDuel", "DuelLostSfx", "DuelVsIntro",
	"DuelAwaitStart", "DuelStart", "RiskStart", "DuelCircle",
}) do
	Network.define(r)
end

local matches     = {}  -- [group]  = match
local playerMatch = {}  -- [player] = match

local function other(s) return s == "Seat1" and "Seat2" or "Seat1" end

local function playerInSeat(seat)
	local occ = seat and seat.Occupant
	if not occ then return nil end
	return Players:GetPlayerFromCharacter(occ.Parent)
end

local function displayName(match, seatName)
	local p = match.players[seatName]
	if p then return p.DisplayName end
	if match.isAI and seatName == match.botSeat and match.botInfo then return match.botInfo.displayName end
	return seatName == "Seat1" and "Player 1" or "Player 2"
end

local function avatarUserId(match, seatName)
	local p = match.players[seatName]
	if p then return p.UserId end
	if match.isAI and seatName == match.botSeat and match.botInfo then return match.botInfo.userId end
	return nil
end

-- Snapshot for the VS reveal cards: headshot id, name, and the player's record
-- (total Wins + current Streak -- the only persisted record stats we have).
local function seatIntroData(match, seatName)
	local p = match.players[seatName]
	local wins, streak, losses = 0, 0, 0
	if p then
		local ls = p:FindFirstChild("leaderstats")
		local w  = ls and ls:FindFirstChild("Wins")
		if w then wins = w.Value end
		local st = p:FindFirstChild("Streak")
		if st then streak = st.Value end
		local lo = p:FindFirstChild("Losses")
		if lo then losses = lo.Value end
	end
	return {
		seat   = seatName,
		userId = avatarUserId(match, seatName),
		name   = displayName(match, seatName),
		wins   = wins,
		losses = losses,
		streak = streak,
		isAI   = (match.isAI and seatName == match.botSeat) or false,
	}
end

local function sendBoth(match, remote, ...)
	for _, sn in ipairs({ "Seat1", "Seat2" }) do
		local p = match.players[sn]
		if p then Network.sendToClient(p, remote, ...) end
	end
end

local function bothSeated(match)
	return match.players.Seat1 ~= nil and match.players.Seat2 ~= nil
		and playerInSeat(match.seats.Seat1) == match.players.Seat1
		and playerInSeat(match.seats.Seat2) == match.players.Seat2
end

local function matchAlive(match)
	if match.isRisk then
		local sn = match.currentSeat
		return match.players[sn] ~= nil and playerInSeat(match.seats[sn]) == match.players[sn]
	end
	if match.isAI then
		local hs = other(match.botSeat)
		return match.players[hs] ~= nil and playerInSeat(match.seats[hs]) == match.players[hs]
	end
	return bothSeated(match)
end

-- ═════ seat-lock & bust effects ═════
-- Roblox humanoid defaults we restore when releasing players from a match.
local DEFAULT_JUMP_POWER  = 50
local DEFAULT_JUMP_HEIGHT = 7.2

local function getHumanoid(player)
	local char = player and player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

-- locked=true: pin the player to the seat (no jump, no eject). false: restore
-- normal humanoid values AND forcibly eject from the chair.
local function setSeatLocked(player, locked)
	local hum = getHumanoid(player)
	if not hum then return end
	if locked then
		hum.JumpPower  = 0
		hum.JumpHeight = 0
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	else
		hum.JumpPower  = DEFAULT_JUMP_POWER
		hum.JumpHeight = DEFAULT_JUMP_HEIGHT
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		-- Forcible eject: clearing Sit alone sometimes fails to release the seat
		-- weld (notably after AI matches), leaving the player stuck seated. Worse,
		-- even after the weld is destroyed the character is still physically
		-- touching the seat, so Roblox instantly RE-SEATS them. So: briefly disable
		-- the seat (so it can't re-grab), destroy the SeatWeld on both ends, clear
		-- Sit, and pop a jump; the seat re-enables 1.5s later, after they're clear.
		local seatPart = hum.SeatPart
		if seatPart then
			if seatPart:IsA("Seat") or seatPart:IsA("VehicleSeat") then
				seatPart.Disabled = true
				task.delay(1.5, function()
					if seatPart and seatPart.Parent then seatPart.Disabled = false end
				end)
			end
			local sw = seatPart:FindFirstChild("SeatWeld")
			if sw then sw:Destroy() end
		end
		local char = player.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			for _, w in ipairs(hrp:GetChildren()) do
				if w:IsA("Weld") and w.Name == "SeatWeld" then w:Destroy() end
			end
		end
		hum.Sit = false
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
		-- Deterministic stand-up: even with the weld gone and the seat disabled,
		-- the character falls straight back ONTO the seat and gets re-grabbed when
		-- it re-enables. So physically place them standing behind their chair,
		-- facing the table — like getting up from the seat.
		if seatPart and char and char.Parent then
			local standPos = seatPart.Position - seatPart.CFrame.LookVector * 4 + Vector3.new(0, 2.5, 0)
			char:PivotTo(CFrame.lookAt(standPos, Vector3.new(seatPart.Position.X, standPos.Y, seatPart.Position.Z)))
			if hrp then
				hrp.AssemblyLinearVelocity  = Vector3.zero
				hrp.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
end

-- Invisible barrier around the table while a match runs. Built as a HOLLOW
-- enclosure — four perimeter walls plus a solid floor cap UNDER the table — not
-- one filled box. The interior stays open so the seated players, chairs and rig
-- never fight a collision, while the walls + under-cap seal every way in:
-- bystanders can't stand on the table, walk in from the side, OR crawl in
-- underneath it (the old single-box version left the legs/underside reachable).
local BARRIER_ABOVE = 14   -- studs the walls rise above the tabletop
local BARRIER_BELOW = 30   -- studs the walls + floor cap extend below the table base
local BARRIER_THICK = 2    -- wall thickness (thick enough that fast walkers can't clip through)
local BARRIER_PAD   = 0.5  -- how far outside the table footprint the walls sit

local function makeBarrierPart(parent, cframe, size)
	local p = Instance.new("Part")
	p.Name         = "MatchBarrier"
	p.Anchored     = true
	p.CanCollide   = true
	p.CanQuery     = false
	p.CanTouch     = false
	p.Transparency = 1
	p.Size         = size
	p.CFrame       = cframe
	p.Parent       = parent
	return p
end

local function setTableBarrier(match, enabled)
	if enabled then
		if match.barrier and match.barrier.Parent then return end
		local tbl = match.group:FindFirstChild("table") or match.group
		local ok, cf, size = pcall(function()
			local c, s = tbl:GetBoundingBox()
			return c, s
		end)
		if not ok or not cf then return end
		local cx, cz  = cf.Position.X, cf.Position.Z
		local topY    = cf.Position.Y + size.Y / 2 + BARRIER_ABOVE
		local bottomY = cf.Position.Y - size.Y / 2 - BARRIER_BELOW
		local wallH   = topY - bottomY
		local wallCY  = (topY + bottomY) / 2
		-- Outer footprint the walls enclose.
		local halfX = size.X / 2 + BARRIER_PAD
		local halfZ = size.Z / 2 + BARRIER_PAD
		local spanX = halfX * 2 + BARRIER_THICK * 2   -- so corner walls overlap (no gaps)
		local spanZ = halfZ * 2 + BARRIER_THICK * 2

		-- A folder holds all barrier parts so cleanup is one Destroy.
		local holder = Instance.new("Folder")
		holder.Name   = "MatchBarrier"
		holder.Parent = match.group

		-- Four perimeter walls (+X, -X, +Z, -Z).
		makeBarrierPart(holder, CFrame.new(cx + halfX + BARRIER_THICK / 2, wallCY, cz),
			Vector3.new(BARRIER_THICK, wallH, spanZ))
		makeBarrierPart(holder, CFrame.new(cx - halfX - BARRIER_THICK / 2, wallCY, cz),
			Vector3.new(BARRIER_THICK, wallH, spanZ))
		makeBarrierPart(holder, CFrame.new(cx, wallCY, cz + halfZ + BARRIER_THICK / 2),
			Vector3.new(spanX, wallH, BARRIER_THICK))
		makeBarrierPart(holder, CFrame.new(cx, wallCY, cz - halfZ - BARRIER_THICK / 2),
			Vector3.new(spanX, wallH, BARRIER_THICK))
		-- Solid floor cap UNDER the table: seals the underside so nobody can crawl in
		-- below the legs. Sits a couple studs beneath the table's base.
		local capY = cf.Position.Y - size.Y / 2 - 2
		makeBarrierPart(holder, CFrame.new(cx, capY, cz),
			Vector3.new(spanX, BARRIER_THICK, spanZ))

		match.barrier = holder
		-- Remember the volume so the watchdog can detect + evict anyone who clips in.
		match.barrierMin = Vector3.new(cx - halfX, bottomY, cz - halfZ)
		match.barrierMax = Vector3.new(cx + halfX, topY,    cz + halfZ)
	else
		if match.barrier then
			pcall(function() match.barrier:Destroy() end)
			match.barrier = nil
		end
		match.barrierMin, match.barrierMax = nil, nil
	end
end

-- Is this player one of the match's seated participants? Participants are MEANT
-- to be inside the table footprint, so the watchdog must never evict them.
local function isParticipant(match, player)
	for _, sn in ipairs({ "Seat1", "Seat2" }) do
		if match.players[sn] == player then return true end
	end
	return false
end

-- A point is inside the barrier volume (with a little padding) — used to catch
-- anyone who somehow clipped through the wall, above OR below the table.
local function insideBarrier(match, pos)
	local lo, hi = match.barrierMin, match.barrierMax
	if not lo or not hi then return false end
	local pad = 0.5
	return pos.X >= lo.X - pad and pos.X <= hi.X + pad
		and pos.Y >= lo.Y - pad and pos.Y <= hi.Y + pad
		and pos.Z >= lo.Z - pad and pos.Z <= hi.Z + pad
end

-- A safe spot just OUTSIDE the table footprint to eject clipped-in bystanders to.
local function ejectPoint(match)
	local lo, hi = match.barrierMin, match.barrierMax
	if not lo or not hi then return nil end
	local cx = (lo.X + hi.X) / 2
	local cz = (lo.Z + hi.Z) / 2
	local halfX = (hi.X - lo.X) / 2
	-- Push them out past the +X face and drop them on top of the table base level.
	local tbl = match.group:FindFirstChild("table") or match.group
	local ok, cf, size = pcall(function() local c, s = tbl:GetBoundingBox(); return c, s end)
	local topY = (ok and cf) and (cf.Position.Y + size.Y / 2) or hi.Y
	return Vector3.new(cx + halfX + 6, topY + 5, cz)
end

-- While a match is locked, watch for NON-participants who have wound up inside
-- the barrier volume (clipped through, walked under the table, exploit, etc.)
-- and teleport them back outside. Participants are left alone (they're pinned to
-- their seats anyway). Self-disposes when the barrier comes down.
local startBarrierWatch, stopBarrierWatch

function startBarrierWatch(match)
	if match.barrierConn then return end
	match.barrierConn = task.spawn(function()
		while match.barrier and match.barrier.Parent do
			local evictTo = ejectPoint(match)
			if evictTo then
				for _, plr in ipairs(Players:GetPlayers()) do
					if not isParticipant(match, plr) then
						local char = plr.Character
						local hrp  = char and char:FindFirstChild("HumanoidRootPart")
						if hrp and insideBarrier(match, hrp.Position) then
							char:PivotTo(CFrame.new(evictTo))
						end
					end
				end
			end
			task.wait(0.25)
		end
		match.barrierConn = nil
	end)
end

function stopBarrierWatch(match)
	-- The loop self-exits once match.barrier is gone; just clear the handle.
	match.barrierConn = nil
end

-- ═════ equipped-chair visual swap ═════
-- Each seat has a "Display" model (the one nearest that seat) that IS the visible
-- static chair (a "Chairbase" sub-model plus sibling backrest parts). When a
-- player sits we hide that WHOLE Display chair and drop a clone of the player's
-- equipped chair (ReplicatedStorage.Assets.Chairs.<Name>) in its place; when they
-- stand we destroy the clone and un-hide the static chair. The swap is keyed to
-- seat occupancy (sit/stand), independent of whether a match is running. Basic =
-- the default static chair, so no clone is spawned for it.
--
-- Per-group chair state lives here (not on the match), so it survives across the
-- whole table lifetime regardless of match state.
local chairState = {}  -- [group] = { Seat1 = {clone=Model?, owner=Player?}, Seat2 = {...} }

local function chairSlot(group, seatName)
	local g = chairState[group]
	if not g then g = {}; chairState[group] = g end
	local s = g[seatName]
	if not s then s = {}; g[seatName] = s end
	return s
end

-- The Display model closest to a given seat (each table has one Display per seat).
local function displayForSeat(group, seat)
	if not seat then return nil end
	local closest, closestDist = nil, math.huge
	for _, child in ipairs(group:GetChildren()) do
		if child.Name == "Display" and child:IsA("Model") then
			local bp = child:FindFirstChildWhichIsA("BasePart", true)
			if bp then
				local d = (bp.Position - seat.Position).Magnitude
				if d < closestDist then closestDist = d; closest = child end
			end
		end
	end
	return closest
end

-- Show/hide the WHOLE static chair for a seat: every BasePart/Decal/Texture in
-- that seat's Display model (the Chairbase seat AND the sibling backrest parts —
-- hiding only Chairbase left the backrest floating). Falls back to a Chair<N>
-- mount part for any older table layout without a Display.
local function setStaticChairVisible(group, seatName, visible)
	local seat = group:FindFirstChild(seatName)
	local display = displayForSeat(group, seat)
	if display then
		for _, d in ipairs(display:GetDescendants()) do
			if d:IsA("BasePart") then d.Transparency = visible and (d:GetAttribute("OrigT") or 0) or 1 end
			if d:IsA("Decal") or d:IsA("Texture") then d.Transparency = visible and (d:GetAttribute("OrigT") or 0) or 1 end
		end
		return
	end
	local idx = seatName == "Seat1" and "1" or "2"
	local part = group:FindFirstChild("Chair" .. idx)
	if part and part:IsA("BasePart") then part.Transparency = visible and 0 or 1 end
end

-- Remove any equipped-chair clone for a seat and restore the static chair.
local function clearChairForSeat(group, seatName)
	local slot = chairSlot(group, seatName)
	if slot.clone then
		pcall(function() slot.clone:Destroy() end)
		slot.clone = nil
	end
	slot.owner = nil
	setStaticChairVisible(group, seatName, true)
end

-- Bounding box of all VISIBLE parts of a model (ignores invisible mount/anchor
-- parts like "Base"), returned as (centerCFrame_atBottom, size). We align by the
-- visible footprint so chairs whose hidden Base sits at an odd offset still rest
-- on the floor instead of sinking.
local function visibleBottomCenter(model)
	local minv = Vector3.new(math.huge, math.huge, math.huge)
	local maxv = Vector3.new(-math.huge, -math.huge, -math.huge)
	local any = false
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			any = true
			local p, s = d.Position, d.Size
			-- Axis-aligned approximation (good enough; chairs are roughly axis-aligned).
			minv = Vector3.new(math.min(minv.X, p.X - s.X/2), math.min(minv.Y, p.Y - s.Y/2), math.min(minv.Z, p.Z - s.Z/2))
			maxv = Vector3.new(math.max(maxv.X, p.X + s.X/2), math.max(maxv.Y, p.Y + s.Y/2), math.max(maxv.Z, p.Z + s.Z/2))
		end
	end
	if not any then return nil end
	local center = (minv + maxv) / 2
	return Vector3.new(center.X, minv.Y, center.Z), (maxv - minv)
end

-- Spawn the player's equipped chair clone at a seat, hiding the static chair.
--
-- Each chair template in ReplicatedStorage.Assets.Chairs was modeled with its own
-- conventions (different facing direction, different Base-to-seat-surface offset).
-- The algorithm below adapts to each chair's geometry:
--
--   ROTATION (auto-detected): the chair's "front" is the OPPOSITE of its backrest
--   direction. We compute the backrest by finding the centroid of visible parts
--   ABOVE the Base's top surface — that's the mass of the backrest. Chairs without
--   a backrest (Rock, Football, Pumpkin, Beanbag, etc.) default to a fixed front
--   direction; for those, rotation doesn't visually matter much since the object
--   is mostly symmetric. Per-chair override available via `FrontYaw` attribute
--   (degrees: 0 = +Z, 90 = +X, 180 = -Z, 270 = -X) for any chair the heuristic
--   gets wrong.
--
--   VERTICAL PLACEMENT: the player visually sits ON the chair, so the chair's
--   "seat surface" must line up with Seat1.CFrame.Y. The seat surface is:
--     • Chairs WITH a backrest: the top of the Base part (the seat pad). The
--       backrest extends upward FROM the seat, so visTop is the backrest top,
--       not the seat. → seatSurfaceY = Base.TopY.
--     • Chairs WITHOUT a backrest: the player sits ON TOP of the visible object,
--       so the visible bounding-box top IS the seat surface.
--       → seatSurfaceY = visTopY.
--   Per-chair override via `SeatYOffset` attribute (studs; negative = push chair
--   down, positive = raise it).
local function applyChairForSeat(group, seatName, player)
	clearChairForSeat(group, seatName)  -- clear any leftover first
	local seat = group:FindFirstChild(seatName)
	if not player or not seat then return end
	local equippedVal = player:FindFirstChild("EquippedChair")
	local chairName   = equippedVal and equippedVal.Value or "Basic"
	local slot = chairSlot(group, seatName)
	slot.owner = player
	if chairName == "Basic" then return end  -- Basic uses the default static chair
	local template = ChairsFolder:FindFirstChild(chairName)
	if not template then return end

	local ok, err = pcall(function()
		local clone = template:Clone()
		clone.Name = "EquippedChairModel"
		for _, part in ipairs(clone:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
			end
		end

		-- Locate the chair's Base (every template has Chairbase.Base; fallback to
		-- any BasePart for safety).
		local basePart
		local cb = clone:FindFirstChild("Chairbase")
		if cb then basePart = cb:FindFirstChild("Base") or cb:FindFirstChildWhichIsA("BasePart", true) end
		if not basePart then basePart = clone:FindFirstChildWhichIsA("BasePart", true) end
		if not basePart then return end  -- chair has no parts; nothing to place

		-- Detect the chair's "backrest direction" by finding the volume-weighted
		-- centroid of visible parts whose BOTTOM sits ABOVE the Base's top. That
		-- centroid points from the Base toward the backrest; the chair's FRONT is
		-- the opposite of that.
		local baseTopY = basePart.Position.Y + basePart.Size.Y/2
		local bx, bz = basePart.Position.X, basePart.Position.Z
		local sumX, sumZ, weight = 0, 0, 0
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 and d ~= basePart then
				local p, s = d.Position, d.Size
				if (p.Y - s.Y/2) > baseTopY - 0.1 then
					local w = math.max(0.01, s.X * s.Y * s.Z)
					sumX += (p.X - bx) * w
					sumZ += (p.Z - bz) * w
					weight += w
				end
			end
		end

		local chairFrontX, chairFrontZ = 1, 0  -- arbitrary default for backrest-less chairs
		local hasBackrest = false
		local frontYawOverride = template:GetAttribute("FrontYaw")
		if frontYawOverride then
			-- FrontYaw in degrees, where the chair's local +Z is 0°. So 90° = +X, etc.
			local rad = math.rad(frontYawOverride)
			chairFrontX = math.sin(rad)
			chairFrontZ = math.cos(rad)
		elseif weight > 0.01 then
			local backX, backZ = sumX/weight, sumZ/weight
			local mag = math.sqrt(backX*backX + backZ*backZ)
			if mag > 0.05 then
				chairFrontX = -backX/mag
				chairFrontZ = -backZ/mag
				hasBackrest = true
			end
		end

		-- Target direction: chair faces the table (= opposite of seat's outward look).
		local seatFwd = seat.CFrame.LookVector
		local targetX, targetZ = -seatFwd.X, -seatFwd.Z
		local tmag = math.sqrt(targetX*targetX + targetZ*targetZ)
		if tmag < 0.05 then
			targetX, targetZ = 0, 1
		else
			targetX, targetZ = targetX/tmag, targetZ/tmag
		end

		-- Y-axis rotation that swings chairFront onto targetDir.
		local dot   = chairFrontX*targetX + chairFrontZ*targetZ
		local cross = chairFrontX*targetZ - chairFrontZ*targetX
		local yawAngle = math.atan2(cross, dot)
		local yawRot = CFrame.Angles(0, yawAngle, 0)

		-- Rigid yaw about the model's current pivot position: keeps the pivot put
		-- and spins everything else around it on the Y axis.
		local pivot = clone:GetPivot()
		clone:PivotTo(CFrame.new(pivot.Position) * yawRot * pivot.Rotation)

		-- Determine the seat surface Y (after rotation; rotation around vertical
		-- doesn't change Y values for axis-aligned parts, but re-read to be safe).
		local baseTopAfterRot = basePart.Position.Y + basePart.Size.Y/2
		local seatSurfaceY
		if hasBackrest then
			-- Player sits at the seat pad = Base.TopY.
			seatSurfaceY = baseTopAfterRot
		else
			-- Player sits ON TOP of the object = visible bbox top.
			local maxY = -math.huge
			for _, d in ipairs(clone:GetDescendants()) do
				if d:IsA("BasePart") and d.Transparency < 1 then
					local top = d.Position.Y + d.Size.Y/2
					if top > maxY then maxY = top end
				end
			end
			seatSurfaceY = (maxY ~= -math.huge) and maxY or baseTopAfterRot
		end

		-- Per-chair fine-tune knob: negative pushes the chair DOWN, positive raises it.
		local seatYOffset = template:GetAttribute("SeatYOffset") or 0

		-- Translate so the seat surface lands on Seat1.Y and the chair is centered
		-- under the player on XZ (Base position = Seat1 XZ).
		local seatPos = seat.Position
		local delta = Vector3.new(
			seatPos.X - basePart.Position.X,
			(seatPos.Y + seatYOffset) - seatSurfaceY,
			seatPos.Z - basePart.Position.Z
		)
		clone:PivotTo(clone:GetPivot() + delta)

		setStaticChairVisible(group, seatName, false)
		clone.Parent = group
		slot.clone = clone
	end)
	if not ok then warn("[DUEL CHAIR] apply failed for", player.Name, ":", err) end
end

-- Sit/stand-driven swap: called from the seat monitor whenever a seat's occupant
-- changes. Swaps to the occupant's equipped chair on sit; restores on stand. The
-- `owner` guard avoids re-cloning on redundant occupancy signals.
local function refreshSeatChair(group, seatName)
	local seat = group:FindFirstChild(seatName)
	if not seat then return end
	local occupantPlayer = playerInSeat(seat)
	local slot = chairSlot(group, seatName)
	if occupantPlayer then
		if slot.owner ~= occupantPlayer then
			applyChairForSeat(group, seatName, occupantPlayer)
		end
	else
		if slot.owner ~= nil or slot.clone then
			clearChairForSeat(group, seatName)
		end
	end
end
module._refreshSeatChair = refreshSeatChair

local function lockMatchPlayers(match, locked)
	for _, sn in ipairs({ "Seat1", "Seat2" }) do
		local p = match.players[sn]
		if p then
			setSeatLocked(p, locked)
			-- Replicated flag all clients can read: hides steal prompts (and any
			-- other interaction) on/for players who are mid-match.
			p:SetAttribute("InMatch", locked or nil)
			-- NOTE: chair-swap is no longer done here. Chairs now swap on sit/stand via
			-- the seat monitor (refreshSeatChair), so the equipped chair is already in
			-- place from the moment the player sat down — well before the match locks,
			-- and it persists correctly until they actually stand up.
		end
	end
	setTableBarrier(match, locked)
	if locked then
		startBarrierWatch(match)
	else
		stopBarrierWatch(match)
	end
end

local function matchCharacter(match, seatName)
	local p = match.players[seatName]
	if p then return p.Character end
	if match.isAI and seatName == match.botSeat and match.botInfo then
		return match.botInfo.character
	end
end

-- Visual-only explosion for a bust: no damage, no force, no joint destruction.
local function bustExplosion(character)
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local boom = Instance.new("Explosion")
	boom.Position                  = hrp.Position
	boom.BlastRadius               = 6
	boom.BlastPressure             = 0
	boom.DestroyJointRadiusPercent = 0
	boom.ExplosionType             = Enum.ExplosionType.NoCraters
	boom.Visible                   = true
	boom.Parent                    = Workspace
	Debris:AddItem(boom, 3)

	-- Explosions are visual-only in Roblox, so we emit a positional boom ourselves.
	if CONFIG.BUST_SOUND_ID and CONFIG.BUST_SOUND_ID ~= "" then
		local emitter = Instance.new("Part")
		emitter.Anchored, emitter.CanCollide, emitter.CanQuery, emitter.CanTouch = true, false, false, false
		emitter.Transparency = 1
		emitter.Size = Vector3.new(1, 1, 1)
		emitter.CFrame = CFrame.new(hrp.Position)
		emitter.Parent = Workspace
		local snd = Instance.new("Sound")
		snd.SoundId = CONFIG.BUST_SOUND_ID
		snd.Volume = CONFIG.BUST_SOUND_VOLUME or 1
		snd.RollOffMaxDistance = 120
		snd.Parent = emitter
		snd:Play()
		Debris:AddItem(emitter, 5)
	end
end

-- Pick a random Sound from SoundService.LostSFX. Returns the sound's Name so the
-- client can resolve and clone it. nil if the folder is missing or empty.
local function lostSfxFolder()
	local de = SoundService:FindFirstChild("DuelSoundEffects")
	return (de and de:FindFirstChild("LostSFX")) or SoundService:FindFirstChild("LostSFX")
end

local function pickLostSfxName()
	local folder = lostSfxFolder()
	if not folder then return nil end
	local names = {}
	for _, c in ipairs(folder:GetChildren()) do
		if c:IsA("Sound") then table.insert(names, c.Name) end
	end
	if #names == 0 then return nil end
	return names[math.random(1, #names)]
end

local function playLostSfxForMatch(match)
	local name = pickLostSfxName()
	if not name then return end
	for _, sn in ipairs({ "Seat1", "Seat2" }) do
		local p = match.players[sn]
		if p then Network.sendToClient(p, "DuelLostSfx", name) end
	end
end

-- ═════ slam button press ═════
local SLAM_SOUND_ID = "rbxassetid://132465969238702"
local SLAM_DEPTH    = 0.15   -- studs the dome travels down
local SLAM_DOWN_T   = 0.07
local SLAM_UP_T     = 0.22

local function animateSlamButton(match, seatName)
	local rig = match.group and match.group:FindFirstChild("TimerRig")
	if not rig then return end
	local btn  = rig:FindFirstChild("Button_" .. seatName)
	local dome = btn and btn:FindFirstChild("Dome")
	if not dome or not dome:IsA("BasePart") then return end

	-- Positional click sound at the dome — anyone in earshot hears it.
	local sound = Instance.new("Sound")
	sound.SoundId = SLAM_SOUND_ID
	sound.Volume  = 1
	sound.Parent  = dome
	sound:Play()
	Debris:AddItem(sound, 5)

	-- Press down, then bounce back. Snapshot CFrame fresh each call so we never
	-- drift if a previous animation was interrupted.
	local restCF = dome.CFrame
	local downCF = restCF - Vector3.new(0, SLAM_DEPTH, 0)
	TweenService:Create(dome,
		TweenInfo.new(SLAM_DOWN_T, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = downCF }):Play()
	task.delay(SLAM_DOWN_T, function()
		if dome.Parent then
			TweenService:Create(dome,
				TweenInfo.new(SLAM_UP_T, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ CFrame = restCF }):Play()
		end
	end)
end

-- ═════ rig screens ═════
local function setScreens(group, text)
	local rig = group:FindFirstChild("TimerRig")
	if not rig then return end
	for _, sn in ipairs({ "Screen_Seat1", "Screen_Seat2" }) do
		local scr = rig:FindFirstChild(sn)
		local lbl = scr and scr:FindFirstChild("TimeLabel", true)
		if lbl then lbl.Text = text end
	end
end

-- ═════ billboard ═════
local function getTemplate()
	local ui = RS:FindFirstChild("Assets") and RS.Assets:FindFirstChild("UI")
	return ui and ui:FindFirstChild("DuelBillboard")
end

local function bbFind(match, name)
	return match.billboard and match.billboard:FindFirstChild(name, true) or nil
end

local function setupBillboard(match)
	local core = match.group.TimerRig:FindFirstChild("Core")
	if not core then return end
	local existing = core:FindFirstChild("DuelBillboard")
	if existing then existing:Destroy() end
	local tmpl = getTemplate()
	if not tmpl then return end
	local bb = tmpl:Clone()
	bb.Enabled = true
	bb.Parent  = core
	match.billboard = bb
	setScreens(match.group, "00.00")
end

local function updateBoard(match)
	if not match.billboard then return end
	local versus = bbFind(match, "Versus")
	if versus then
		versus.Text = string.format(
			'<font color="%s">%s</font>  <font color="rgb(255,220,70)">VS</font>  <font color="%s">%s</font>',
			COLOR_P1_HEX, displayName(match, "Seat1"), COLOR_P2_HEX, displayName(match, "Seat2"))
	end
	local roundLbl = bbFind(match, "Round")
	if roundLbl then roundLbl.Text = "Round " .. match.round end
	local targetLbl = bbFind(match, "Target")
	if targetLbl then
		targetLbl.Text = string.format('Don\'t Go Above <font color="rgb(95,255,95)">%g</font>', match.target)
	end
end

local function setCircle(match, index, winnerSeat)
	local circ = bbFind(match, "Circle" .. index)
	if circ then
		circ.BackgroundColor3 = (winnerSeat == "Seat1") and COLOR_P1 or COLOR_P2
		local avatar = circ:FindFirstChild("Avatar")
		local uid = avatarUserId(match, winnerSeat)
		if avatar and uid then
			avatar.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", uid)
			avatar.ImageTransparency = 0
		end
	end
	-- Also push the round-win to each player's screen HUD circles.
	local uid = avatarUserId(match, winnerSeat)
	sendBoth(match, "DuelCircle", index, winnerSeat, uid)
end

local function showSide(match, seatName)
	sendBoth(match, "DuelShowSide", match.group, seatName)
end

-- ═════ cleanup / abort ═════
local function clearMatch(match)
	if match.billboard then match.billboard:Destroy(); match.billboard = nil end
	if match.barrier then pcall(function() match.barrier:Destroy() end); match.barrier = nil end
	-- Chairs are managed by the seat monitor now, not the match. We refresh each
	-- seat AFTER the match tears down (via the HandleSeatChange call in endMatch /
	-- the occupancy signals) so a still-seated player keeps their equipped chair
	-- and an empty seat restores the static chair. Nothing to clear here.
	if match.botInfo and match.botInfo.character then
		pcall(function() match.botInfo.character:Destroy() end)
		match.botInfo.character = nil
	end
	for _, sn in ipairs({ "Seat1", "Seat2" }) do
		local p = match.players[sn]
		if p then playerMatch[p] = nil end
	end
	matches[match.group] = nil
	Network.broadcast("DuelReset", match.group)
	setScreens(match.group, "00.00")
end

local function abortMatch(match)
	match.status = "ending"
	lockMatchPlayers(match, false)  -- restore jumping in case anyone was locked
	clearMatch(match)
end

-- ═════ AI slam time ═════
-- Returns the elapsed time at which the AI "slams". `clutch` is how many rounds
-- the AI is currently BEHIND its opponent (0 if tied/ahead); when behind it
-- chases the on-the-dot win a little harder. The harder the AI, the tighter it
-- plays to the target on a safe pass (small margin under) and the rarer it busts.
local function aiSlamTime(target, clutch)
	clutch = math.max(0, clutch or 0)
	local exactChance = CONFIG.AI_EXACT_CHANCE + clutch * CONFIG.AI_CLUTCH_BONUS
	local r = math.random()
	if r < CONFIG.AI_BUST_CHANCE then
		-- Overshoot -> bust. Keep the overshoot small so it reads as a near-miss.
		return target + (0.05 + math.random() * 0.4)
	elseif r < CONFIG.AI_BUST_CHANCE + exactChance then
		-- Lands so the rig DISPLAYS exactly the target -> on-the-dot round win.
		return target + (math.random() * 0.004)
	else
		-- Safe pass, but tight: stop only a little under the target so the human
		-- inherits a small window. Margin in [AI_SAFE_MIN, AI_SAFE_MAX]; when the AI
		-- is behind, it shaves the margin even thinner (plays riskier to catch up).
		local lo = CONFIG.AI_SAFE_MIN
		local hi = math.max(lo + 0.05, CONFIG.AI_SAFE_MAX - clutch * 0.2)
		local margin = lo + math.random() * (hi - lo)
		return math.max(0.4, target - margin)
	end
end

-- ═════ turn ═════
local function runTurn(match)
	local seat = match.currentSeat
	local isBotTurn = match.isAI and seat == match.botSeat
	local carry = match.carryElapsed or 0
	local firstTurn = carry <= 0     -- first turn of the round = fresh climb from 0

	showSide(match, seat)
	task.wait(0.7)
	if not matchAlive(match) then return "abort" end

	if isBotTurn or firstTurn then
		-- First turn of the round (and every bot turn): 3-2-1, then auto-start.
		sendBoth(match, "DuelTurnCountdown")
		task.wait(2.4)
		if not matchAlive(match) then return "abort" end
	else
		-- Later human turns: the player must click to START their run. Freeze the
		-- carried value on the rig and wait for their start input (or time out).
		match.awaitingStart = true
		sendBoth(match, "DuelAwaitStart", match.group, seat, carry)
		local sdeadline = Workspace:GetServerTimeNow() + CONFIG.TURN_TIMEOUT
		while match.status == "playing" and match.awaitingStart
			and matchAlive(match) and Workspace:GetServerTimeNow() < sdeadline do
			task.wait()
		end
		match.awaitingStart = false
		if not matchAlive(match) then return "abort" end
	end

	-- Carry-over timer: the run continues the climb from wherever the previous
	-- player stopped. timerStart is shifted back by `carry` so (now - timerStart)
	-- starts at `carry` and climbs from there.
	match.timerStart      = Workspace:GetServerTimeNow() - carry
	match.turnStartTime   = Workspace:GetServerTimeNow()  -- when this run's climb began (0.01 guard)
	match.slammed         = false
	match.reportedElapsed = nil
	Network.broadcast("DuelTimerStart", match.timerStart, match.target, match.group, seat)

	local elapsed
	if isBotTurn then
		-- How many rounds the AI is behind (0 if tied or ahead) -> drives clutch play.
		local botWins = match.wins[match.botSeat] or 0
		local humanWins = match.wins[other(match.botSeat)] or 0
		local clutch = math.max(0, humanWins - botWins)
		local aiTotal = math.min(aiSlamTime(match.target, clutch), CONFIG.TURN_TIMEOUT)
		-- Never let the AI insta-slam at the exact carry value — give it at least
		-- 0.4s of "thinking" on top of the current carry.
		aiTotal = math.max(aiTotal, carry + 0.4)
		local deadline = match.timerStart + aiTotal
		while match.status == "playing" and matchAlive(match) and Workspace:GetServerTimeNow() < deadline do
			task.wait()
		end
		if not matchAlive(match) then return "abort" end
		elapsed = aiTotal
	else
		match.awaitingSlam = true
		local deadline = Workspace:GetServerTimeNow() + CONFIG.TURN_TIMEOUT
		local autoSlamAt = match.target + CONFIG.AUTO_SLAM_OVERSHOOT
		while match.status == "playing" and not match.slammed
			and matchAlive(match) and Workspace:GetServerTimeNow() < deadline do
			local cur = Workspace:GetServerTimeNow() - match.timerStart
			if cur >= autoSlamAt then
				-- Player lingered more than CONFIG.AUTO_SLAM_OVERSHOOT s past the
				-- target without slamming — force the slam so the round resolves.
				match.slammed         = true
				match.reportedElapsed = cur
				break
			end
			task.wait()
		end
		match.awaitingSlam = false
		if not matchAlive(match) then return "abort" end
		elapsed = match.slammed and match.reportedElapsed or (Workspace:GetServerTimeNow() - match.timerStart)
	end

	-- Classify by the value the PLAYERS SEE. The rig displays two decimals
	-- (%05.2f, which rounds), so we round the elapsed to hundredths and compare
	-- with the target as integers. The round ONLY ends when the displayed time
	-- is exactly ON the target ("on the dot") or ABOVE it — a displayed value
	-- under the target is always a pass, no hidden tolerance window.
	local shownCents  = math.floor(elapsed * 100 + 0.5)
	local targetCents = math.floor(match.target * 100 + 0.5)
	local result
	if shownCents > targetCents then
		result = "bust"            -- displayed time went above the target
	elseif shownCents == targetCents then
		result = "exact"           -- displayed time reads exactly the target
	else
		result = "pass"            -- displayed time is under -> carry to the other player
	end
	Network.broadcast("DuelTimerStop", elapsed, result, match.group, seat)
	print(string.format("[DUEL DEBUG] seat=%s isBot=%s carry=%.3f elapsed=%.3f shown=%.2f target=%s -> %s",
		tostring(seat), tostring(isBotTurn), carry, elapsed or -1, shownCents / 100, tostring(match.target), result))
	animateSlamButton(match, seat)
	return result, elapsed
end

-- ═════ end ═════
local function endMatch(match, winnerSeat)
	match.status = "ending"
	local winnerPlayer = match.players[winnerSeat]
	local loserPlayer  = match.players[other(winnerSeat)]
	if DataHandler then
		if winnerPlayer then
			pcall(function()
				-- Base win reward (CashMult from the chair is applied inside AddCurrency).
				DataHandler.AddCurrency(winnerPlayer, CONFIG.REWARD_CASH, "Cash")
				-- StreakBonus chair boost: extra raw cash scaled by the streak the player
				-- is ON after this win. Computed before the +1 Streak below using the
				-- current streak value, then awarded raw so it's exactly what's intended.
				local streakPct = DataHandler.GetChairStreakBonus(winnerPlayer)
				if streakPct > 0 then
					local streakVal = 0
					local sv = winnerPlayer:FindFirstChild("Streak")
					if sv then streakVal = sv.Value end
					local bonus = math.floor(CONFIG.REWARD_CASH * (streakPct / 100) * streakVal)
					if bonus > 0 then DataHandler.AddCurrencyRaw(winnerPlayer, bonus, "Cash") end
				end
				DataHandler.AddCurrency(winnerPlayer, 1, "Wins")
				DataHandler.AddCurrency(winnerPlayer, 1, "Streak")
			end)
		end
		if loserPlayer then pcall(function()
			-- Capture the loser's pre-reset streak BEFORE we zero it, so a later
			-- "Remove Loss" purchase can restore it.
			local preStreak = 0
			local sv = loserPlayer:FindFirstChild("Streak")
			if sv then preStreak = sv.Value end

			DataHandler.SetCurrency(loserPlayer, 0, "Streak")
			DataHandler.AddCurrency(loserPlayer, 1, "Losses")

			-- Stash data the Remove-Loss / Troll products act on, then pop the
			-- button up on the loser's screen for ~10s.
			DataHandler.SetRevengePending(loserPlayer.UserId, {
				winnerUserId = winnerPlayer and winnerPlayer.UserId or nil,
				loserStreak  = preStreak,
				cash         = CONFIG.REWARD_CASH,
			})
			-- Second arg tells the client whether a HUMAN won (Troll has a target).
			-- Losing to the AI hides the Troll button so nobody pays to jumpscare a bot.
			Network.sendToClient(loserPlayer, "ShowRevenge", winnerPlayer ~= nil)
		end) end
	end
	sendBoth(match, "DuelEnd", displayName(match, winnerSeat), winnerSeat)
	playLostSfxForMatch(match)  -- both players hear the lost sting on match end
	-- Match is over — pop everyone out of their chairs and restore jumping.
	lockMatchPlayers(match, false)
	task.wait(5)
	local group = match.group
	clearMatch(match)
	task.delay(1.5, function() module.HandleSeatChange(group) end)
end

-- ═════ match loop ═════
local function runMatch(match)
	match.status = "countdown"
	match.target = pickRandomTarget()  -- round 1's target; each subsequent round rolls again
	setupBillboard(match)
	updateBoard(match)

	for s = CONFIG.PRE_COUNTDOWN, 1, -1 do
		if not matchAlive(match) then abortMatch(match); return end
		sendBoth(match, "DuelPreGame", s, 2, 2, match.group)
		task.wait(1)
	end
	if not matchAlive(match) then abortMatch(match); return end

	sendBoth(match, "DuelGo", match.target)
	task.wait(1.25)                                  -- let the GO black-slam fade back out
	if not matchAlive(match) then abortMatch(match); return end

	-- VS reveal: camera pans to the side of the table (both players framed) and a
	-- photo+record card for each flies in one-by-one. Participants only.
	sendBoth(match, "DuelVsIntro", match.group,
		seatIntroData(match, "Seat1"), seatIntroData(match, "Seat2"))

	match.status      = "playing"
	match.currentSeat = (math.random() < 0.5) and "Seat1" or "Seat2"
	match.carryElapsed = 0
	lockMatchPlayers(match, true)  -- pin players to their chairs until end/abort
	task.wait(CONFIG.VS_INTRO_HOLD)                  -- cards on screen before turn 1
	if not matchAlive(match) then abortMatch(match); return end

	showSide(match, match.currentSeat)
	task.wait(1.3)

	while match.status == "playing" do
		local result, elapsed = runTurn(match)
		if result == "abort" or not matchAlive(match) then abortMatch(match); return end
		if result == "pass" then
			match.carryElapsed = elapsed or 0
			match.currentSeat = other(match.currentSeat)
		else
			local rw = (result == "exact") and match.currentSeat or other(match.currentSeat)
			match.wins[rw] += 1
			setCircle(match, match.round, rw)
			-- Round-win chair boost: CashPerRound pays out raw (unmultiplied) cash
			-- to the round winner each round they take.
			local rwPlayer = match.players[rw]
			if DataHandler and rwPlayer then
				local perRound = DataHandler.GetChairCashPerRound(rwPlayer)
				if perRound > 0 then
					pcall(function() DataHandler.AddCurrencyRaw(rwPlayer, perRound, "Cash") end)
				end
			end
			-- Round-loser feedback:
			--   bust  -> the current player overshot: THEY explode + lost sting.
			--   exact -> the current player nailed the dot: their OPPONENT lost the
			--            round, so the opponent explodes + the lost sting plays.
			if result == "bust" then
				bustExplosion(matchCharacter(match, match.currentSeat))
				playLostSfxForMatch(match)
			elseif result == "exact" then
				bustExplosion(matchCharacter(match, other(match.currentSeat)))
				playLostSfxForMatch(match)
			end
			task.wait(2.5)
			if match.wins[rw] >= CONFIG.WINS_NEEDED then
				endMatch(match, rw)
				return
			else
				match.round += 1
				match.target = pickRandomTarget()  -- fresh random target for the new round
				match.carryElapsed  = 0          -- fresh timer for the new round
				updateBoard(match)
				match.currentSeat   = other(rw)  -- round loser goes first next round
				sendBoth(match, "DuelRoundStart", match.round, match.target)
				task.wait(1.5)
			end
		end
	end
end

-- ═════ starts ═════
local function startMatch(group, p1, p2)
	local match = {
		group = group,
		seats = { Seat1 = group:FindFirstChild("Seat1"), Seat2 = group:FindFirstChild("Seat2") },
		players = { Seat1 = p1, Seat2 = p2 },
		status = "countdown", round = 1, wins = { Seat1 = 0, Seat2 = 0 },
		currentSeat = "Seat1", target = CONFIG.TARGET,
	}
	matches[group] = match
	playerMatch[p1] = match
	playerMatch[p2] = match
	match.thread = task.spawn(runMatch, match)
end

local function pickRandomFriend(player)
	local friends = {}
	pcall(function()
		local pages = Players:GetFriendsAsync(player.UserId)
		local guard = 0
		while true do
			for _, f in ipairs(pages:GetCurrentPage()) do
				table.insert(friends, { userId = f.Id, name = f.Username, displayName = f.DisplayName or f.Username })
			end
			guard += 1
			if pages.IsFinished or guard >= 4 then break end
			pages:AdvanceToNextPageAsync()
		end
	end)
	if #friends > 0 then return friends[math.random(1, #friends)] end
	return { userId = 1, name = "Rival", displayName = "Rival" }  -- fallback if no friends / API fails
end

local function spawnBot(match, info)
	local aiSeat = match.seats[match.botSeat]
	if not aiSeat then return nil end
	local ok, char = pcall(function() return Players:CreateHumanoidModelFromUserId(info.userId) end)
	if not ok or not char then return nil end
	char.Name = info.name
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") then p.CanCollide = false end
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then pcall(function() hum.DisplayName = info.displayName end) end

	-- Snapshot every part/decal/texture's transparency and hide it. We fade these
	-- back to the originals once the bot is seated so the avatar materializes in
	-- instead of popping into existence.
	local originalT = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			originalT[d] = d.Transparency; d.Transparency = 1
		elseif d:IsA("Decal") or d:IsA("Texture") then
			originalT[d] = d.Transparency; d.Transparency = 1
		end
	end

	char.Parent = Workspace
	-- Record on the match right away so an abort during seating still destroys the bot.
	if match.botInfo then match.botInfo.character = char end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then hrp.CFrame = aiSeat.CFrame * CFrame.new(0, 2, 0) end
	task.wait(0.1)
	if hum and aiSeat and not aiSeat.Occupant then pcall(function() aiSeat:Sit(hum) end) end

	-- Play the default sit pose. CreateHumanoidModelFromUserId returns a model
	-- without the auto-inserted Animate script, so Humanoid.Sit doesn't trigger a
	-- pose on its own — we drive it manually so the NPC actually looks seated.
	if hum then
		local animator = hum:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = hum
		end
		local sitAnim = Instance.new("Animation")
		sitAnim.AnimationId = (hum.RigType == Enum.HumanoidRigType.R15)
			and "rbxassetid://2506281703" or "rbxassetid://178130996"
		local okAnim, track = pcall(function() return animator:LoadAnimation(sitAnim) end)
		if okAnim and track then
			track.Priority = Enum.AnimationPriority.Idle
			track.Looped = true
			track:Play()
		end
	end

	-- Materialize the bot. Side-task so spawnBot can return and the pre-game
	-- countdown begins; the fade plays during the first ~half-second of it.
	task.spawn(function()
		local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for inst, origT in pairs(originalT) do
			if inst.Parent then
				TweenService:Create(inst, tweenInfo, { Transparency = origT }):Play()
			end
		end
	end)

	return char
end

local function startAIMatch(group, human, humanSeatName)
	local botSeatName = other(humanSeatName)
	local match = {
		group = group,
		seats = { Seat1 = group:FindFirstChild("Seat1"), Seat2 = group:FindFirstChild("Seat2") },
		players = { [humanSeatName] = human },
		isAI = true, botSeat = botSeatName,
		status = "countdown", round = 1, wins = { Seat1 = 0, Seat2 = 0 },
		currentSeat = "Seat1", target = CONFIG.TARGET,
	}
	matches[group] = match
	playerMatch[human] = match
	task.spawn(function()
		local info = pickRandomFriend(human)
		match.botInfo = info
		if not matchAlive(match) then abortMatch(match); return end
		local char = spawnBot(match, info)
		if not char or not matchAlive(match) then
			if char then pcall(function() char:Destroy() end) end
			abortMatch(match); return
		end
		match.botInfo.character = char
		match.thread = task.spawn(runMatch, match)
	end)
end

-- ═════ remotes from clients ═════
Network.onServer("DuelSlam", function(player, clientElapsed)
	local match = playerMatch[player]
	if not match or not match.awaitingSlam then return end
	if match.players[match.currentSeat] ~= player then return end
	-- At least 0.01s must elapse after the timer starts before a stop registers.
	if match.turnStartTime and (Workspace:GetServerTimeNow() - match.turnStartTime) < 0.01 then return end
	local serverElapsed = Workspace:GetServerTimeNow() - match.timerStart
	clientElapsed = tonumber(clientElapsed) or serverElapsed
	match.reportedElapsed = math.clamp(clientElapsed, 0, serverElapsed + 0.1)
	match.awaitingSlam = false
	match.slammed = true
end)

Network.onServer("DuelStart", function(player)
	local match = playerMatch[player]
	if not match or not match.awaitingStart then return end
	if match.players[match.currentSeat] ~= player then return end
	animateSlamButton(match, match.currentSeat)  -- press the dome + click sound on the start click too
	match.awaitingStart = false   -- runTurn proceeds to start the climb
end)

Network.onServer("RequestAIDuel", function(player)
	local char = player.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if not seat or (seat.Name ~= "Seat1" and seat.Name ~= "Seat2") then return end
	local group = seat.Parent
	if not group or not group:FindFirstChild("TimerRig") then return end
	if not group:FindFirstChild("Seat1") or not group:FindFirstChild("Seat2") then return end
	if matches[group] then return end
	if playerInSeat(seat) ~= player then return end
	local oppSeat = group:FindFirstChild(other(seat.Name))
	if not oppSeat or oppSeat.Occupant then return end
	startAIMatch(group, player, seat.Name)
end)

-- ═════ solo risk mode ═════
-- RiskMode tables: a single on-the-dot attempt. Land exactly on the target to
-- win 3x the normal cash; anything else (under or over) ejects you from the chair.
-- Reuses the duel cinematics (GO slam, timer rig, slam button, camera) and the
-- shared DuelSlam handler, so no client changes are needed beyond the Start button.
local function startRiskMatch(group, player, seatName)
	local match = {
		group = group,
		-- Solo mode: RiskMode tables only have Seat1 (1-player game).
		seats = { Seat1 = group:FindFirstChild("Seat1") },
		players = { [seatName] = player },
		isRisk = true,
		status = "countdown", round = 1, wins = { Seat1 = 0, Seat2 = 0 },
		currentSeat = seatName, carryElapsed = 0,
		exactTol = CONFIG.RISK_EXACT_TOL,
	}
	matches[group] = match
	playerMatch[player] = match
	match.thread = task.spawn(function()
		match.target = pickRandomTarget()
		-- Light pre-game: hides HUD/quickplay, sets InDuel, then the GO slam.
		for s = 3, 1, -1 do
			if not matchAlive(match) then abortMatch(match) return end
			sendBoth(match, "DuelPreGame", s, 1, 1, match.group)
			task.wait(1)
		end
		if not matchAlive(match) then abortMatch(match) return end
		sendBoth(match, "DuelGo", match.target, true)  -- true = risk "On The Dot" label
		task.wait(1.25)
		if not matchAlive(match) then abortMatch(match) return end

		match.status = "playing"
		lockMatchPlayers(match, true)
		match.carryElapsed = 0

		-- Single turn: first-turn path auto-runs 3-2-1 then the player slams.
		local result = runTurn(match)
		if result == "abort" or not matchAlive(match) then abortMatch(match) return end

		match.status = "ending"
		local won = (result == "exact")
		local p = match.players[match.currentSeat]
		if DataHandler and p then
			if won then
				pcall(function()
					DataHandler.AddCurrencyRaw(p, CONFIG.REWARD_CASH * CONFIG.RISK_REWARD_MULT, "Cash")
					DataHandler.AddCurrency(p, 1, "Wins")
					DataHandler.AddCurrency(p, 1, "Streak")
				end)
			else
				pcall(function()
					DataHandler.SetCurrency(p, 0, "Streak")
					DataHandler.AddCurrency(p, 1, "Losses")
				end)
			end
		end
		if won then
			sendBoth(match, "DuelEnd", displayName(match, match.currentSeat), match.currentSeat)
		else
			if result == "bust" then bustExplosion(matchCharacter(match, match.currentSeat)) end
			playLostSfxForMatch(match)
		end
		lockMatchPlayers(match, false)          -- eject from the chair
		task.wait(won and 4 or 1.5)
		clearMatch(match)                       -- broadcasts DuelReset -> client reverts UI
	end)
end

Network.onServer("RiskStart", function(player)
	local char = player.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if not seat or seat.Name ~= "Seat1" then return end
	local group = seat.Parent
	local riskFolder = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild(CONFIG.RISK_FOLDER)
	if not group or not riskFolder or group.Parent ~= riskFolder then return end
	if not group:FindFirstChild("TimerRig") then return end
	if matches[group] then return end
	if playerMatch[player] then return end
	if playerInSeat(seat) ~= player then return end
	startRiskMatch(group, player, "Seat1")
end)

-- ═════ seat monitor ═════
function module.HandleSeatChange(group)
	local s1 = group:FindFirstChild("Seat1")
	local s2 = group:FindFirstChild("Seat2")
	if not s1 or not s2 then return end
	local p1, p2 = playerInSeat(s1), playerInSeat(s2)

	-- Equipped-chair visual swap runs on EVERY seat change, regardless of match
	-- state, so the chair appears the instant a player sits and reverts the instant
	-- they stand. (The `owner` guard inside makes redundant calls cheap no-ops.)
	refreshSeatChair(group, "Seat1")
	refreshSeatChair(group, "Seat2")

	local match = matches[group]
	if match then
		if match.status == "countdown" or match.status == "playing" then
			if not matchAlive(match) then abortMatch(match) end
		end
		return
	end
	if p1 and p2 then startMatch(group, p1, p2) end
end

function module.Init()
	local map = Workspace:WaitForChild("Map")
	for _, folderName in ipairs(CONFIG.FOLDERS) do
		local folder = map:FindFirstChild(folderName)
		if folder then
			for _, group in ipairs(folder:GetChildren()) do
				if group:FindFirstChild("TimerRig")
					and group:FindFirstChild("Seat1") and group:FindFirstChild("Seat2") then
					local function onChange() module.HandleSeatChange(group) end
					group.Seat1:GetPropertyChangedSignal("Occupant"):Connect(onChange)
					group.Seat2:GetPropertyChangedSignal("Occupant"):Connect(onChange)
				end
			end
		end
	end
	Players.PlayerRemoving:Connect(function(plr)
		local match = playerMatch[plr]
		if match then
			playerMatch[plr] = nil
			local group = match.group
			task.defer(function() module.HandleSeatChange(group) end)
		end
	end)
	print("[TimerDuel] ready on folders:", table.concat(CONFIG.FOLDERS, ", "))
end

local ok, dh = pcall(function() return require(script.Parent.DataHandler) end)
if ok then DataHandler = dh else warn("[TimerDuel] DataHandler unavailable:", dh) end
module.Init()

return module
