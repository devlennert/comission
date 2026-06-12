--[[
	TimerDuelCinematics  (LocalScript, StarterPlayerScripts)
	Server-driven duel presentation: pre-game countdown, black "GO" slam, per-turn
	3-2-1, cinematic camera on the active side, the climbing rig timer, slam input,
	and a winner banner. Driven by TimerDuelHandler via Network remotes.

	NOTE: every overlay label starts hidden (Visible=false) and its UIStroke tracks
	the text transparency, so nothing (not even an outline) shows until it's used.
]]

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")
local CAS          = game:GetService("ContextActionService")
local RunService   = game:GetService("RunService")
local Workspace    = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local Debris       = game:GetService("Debris")
local RS           = game:GetService("ReplicatedStorage")
local Network      = require(RS:WaitForChild("Modules"):WaitForChild("Network"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ═════ overlay GUI ═════
-- The cinematic overlay is a physical ScreenGui at StarterGui.DuelCinematics
-- so you can edit text, position, color, stroke, and panel tint in Studio.
-- Leave every label at its normal visible appearance (TextTransparency=0,
-- UIStroke.Transparency=0, panel BackgroundTransparency at the tint you
-- want, etc.) and just toggle Visible to preview — the script captures
-- those values as the "shown" targets at runtime and force-hides everything
-- on startup, so nothing flashes on join and your previews work in Studio.
local gui          = playerGui:WaitForChild("DuelCinematics")
local black        = gui:WaitForChild("Black")
local pregamePanel = gui:WaitForChild("PreGamePanel")
local panelStroke  = pregamePanel:FindFirstChildOfClass("UIStroke")
local startsIn     = pregamePanel:WaitForChild("StartsIn")
local readyCount   = pregamePanel:WaitForChild("ReadyCount")
local goLabel      = gui:WaitForChild("Go")
local goScale      = goLabel:FindFirstChildOfClass("UIScale")
local turnNum      = gui:WaitForChild("TurnCount")
local turnScale    = turnNum:FindFirstChildOfClass("UIScale")
local winner       = gui:WaitForChild("Winner")
local roundFlash   = gui:WaitForChild("RoundFlash")
local slamBtn      = gui:WaitForChild("SlamBtn")
local targetText   = gui:WaitForChild("TargetText")
local vignette     = gui:WaitForChild("Vignette")
local vEdges       = {
	vignette:WaitForChild("Top"),    vignette:WaitForChild("Bottom"),
	vignette:WaitForChild("Left"),   vignette:WaitForChild("Right"),
}
local roundCircles = gui:WaitForChild("RoundCircles")
local circleSlots  = { roundCircles:WaitForChild("Circle1"), roundCircles:WaitForChild("Circle2"), roundCircles:WaitForChild("Circle3") }
local circleEmptyBG = circleSlots[1].BackgroundColor3  -- snapshot of the "empty" tint

-- [label] = UIStroke, so we can fade the outline with the text.
local strokes = {}
for _, l in ipairs({ startsIn, readyCount, goLabel, turnNum, winner, roundFlash, targetText }) do
	strokes[l] = l:FindFirstChildOfClass("UIStroke")
end

-- ═════ visibility baseline ═════
-- Capture each label's "shown" TextTransparency and stroke transparency from
-- the Studio defaults, plus the panel's BG / stroke transparency, then force
-- everything to its hidden state. setVis / twVis below restore to these
-- captured values instead of hardcoding 0, so the editor can tweak them.
local shownTextT       = {}
local shownStrokeT     = {}
for _, l in ipairs({ startsIn, readyCount, goLabel, turnNum, winner, roundFlash, targetText }) do
	shownTextT[l] = l.TextTransparency
	local s = strokes[l]
	if s then shownStrokeT[s] = s.Transparency end
	l.TextTransparency = 1
	l.Visible = false
	if s then s.Transparency = 1 end
end
local shownPanelBG      = pregamePanel.BackgroundTransparency
local shownPanelStrokeT = panelStroke and panelStroke.Transparency or 1
local shownTargetBG     = targetText.BackgroundTransparency
pregamePanel.BackgroundTransparency = 1
pregamePanel.Visible = false
if panelStroke then panelStroke.Transparency = 1 end
targetText.BackgroundTransparency = 1
slamBtn.Visible = false
black.BackgroundTransparency = 1

-- ═════ mobile layout ═════
-- On phones the top cluster (round dots + target text) and the VS card stack
-- sit too close on the short viewport and overlap each other. Shrink the top
-- cluster and push the VS stack down so the duel HUD reads as a clean vertical
-- stack. Cards / VS / records are moved via Position+Size ONLY (never UIScale)
-- because the reveal animation drives their own UIScale.
do
	local isMobile = UIS.TouchEnabled and not UIS.KeyboardEnabled
	if isMobile then
		local function addScale(o, s)
			if not o then return end
			local sc = o:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
			sc.Scale = s
			sc.Parent = o
		end
		-- Top cluster: shrink the dots and drop the target clear of them.
		roundCircles.Position = UDim2.new(0.5, 0, 0.02, 0)
		addScale(roundCircles, 0.62)
		targetText.Position = UDim2.new(0.5, 0, 0.135, 0)
		addScale(targetText, 0.82)
		-- VS stack: push down + spread so its top clears the target text.
		local function place(name, pos, size)
			local o = gui:FindFirstChild(name)
			if not o then return end
			o.Position = pos
			if size then o.Size = size end
		end
		place("LeftCard",    UDim2.new(0.28, 0, 0.46, 0), UDim2.new(0.22, 0, 0.34, 0))
		place("RightCard",   UDim2.new(0.72, 0, 0.46, 0), UDim2.new(0.22, 0, 0.34, 0))
		place("VS",          UDim2.new(0.5,  0, 0.46, 0), nil)
		place("LeftRecord",  UDim2.new(0.28, 0, 0.70, 0), nil)
		place("RightRecord", UDim2.new(0.72, 0, 0.70, 0), nil)
		-- Lobby side-buttons read too small on phones — bump them up ~40%.
		local uiRoot = playerGui:FindFirstChild("UI")
		local leftButtons = uiRoot and uiRoot:FindFirstChild("LeftButtons")
		if leftButtons then
			leftButtons.Size = UDim2.new(
				leftButtons.Size.X.Scale * 1.4, 0,
				leftButtons.Size.Y.Scale * 1.4, 0)
		end
	end
end

-- ═════ tension fx (FOV pinch + edge vignette) ═════
-- intensity 0 = normal view, 1 = peak (reached at the target time)
local FOV_NORMAL      = 70
local FOV_MIN         = 55     -- FOV at peak intensity (smaller = more tunnel vision)
local VIGNETTE_PEAK_T = 0.15   -- frame BackgroundTransparency at intensity=1 (lower = more opaque)
local CURVE           = 2.4    -- (elapsed/target)^CURVE — higher pushes the effect later in the climb

-- Timer screen text colors (rig's SurfaceGui label), lerped by intensity 0..1.
local TIMER_COLOR_CLEAR  = Color3.fromRGB(60,  255, 90)   -- green at intensity=0
local TIMER_COLOR_DANGER = Color3.fromRGB(255, 42,  42)   -- red at intensity=1

-- Blind-challenge fade: the rig timer text fades toward invisible as the timer
-- climbs to the target, so you can read it early but must slam by feel near the
-- limit. Resets to fully visible when a turn ends.
local TIMER_FADE_MAX   = 1.0   -- text fully gone by the time you hit the target
local TIMER_FADE_CURVE = 0.32  -- <1 = fades out fast and early (blind well before the target)

-- FOV pinch + vignette ease smoothly toward a target instead of snapping. setTension
-- and clearTension just set the target; a self-disposing loop glides the camera FOV
-- and vignette toward it (frame-rate independent), then stops once settled — so no
-- zoom ever pops in/out, and the loop never lingers to fight other cameras.
local TENSION_RATE     = 7        -- higher = quicker glide (still smooth, no snap)
local tensionFOVTarget = FOV_NORMAL
local tensionVigTarget = 1
local tensionConn      = nil

local function tensionSettled()
	local cam = Workspace.CurrentCamera
	if cam and math.abs(cam.FieldOfView - tensionFOVTarget) > 0.05 then return false end
	for _, edge in ipairs(vEdges) do
		if math.abs(edge.BackgroundTransparency - tensionVigTarget) > 0.004 then return false end
	end
	return true
end

local function startTensionEase()
	if tensionConn then return end
	tensionConn = RunService.RenderStepped:Connect(function(dt)
		local cam = Workspace.CurrentCamera
		local a = 1 - math.exp(-dt * TENSION_RATE)   -- frame-rate-independent approach
		if cam then
			cam.FieldOfView = cam.FieldOfView + (tensionFOVTarget - cam.FieldOfView) * a
		end
		for _, edge in ipairs(vEdges) do
			edge.BackgroundTransparency = edge.BackgroundTransparency + (tensionVigTarget - edge.BackgroundTransparency) * a
		end
		if tensionSettled() then
			if cam then cam.FieldOfView = tensionFOVTarget end
			for _, edge in ipairs(vEdges) do edge.BackgroundTransparency = tensionVigTarget end
			tensionConn:Disconnect(); tensionConn = nil
		end
	end)
end

local function setTension(intensity)
	intensity = math.clamp(intensity, 0, 1)
	tensionFOVTarget = FOV_NORMAL + (FOV_MIN - FOV_NORMAL) * intensity
	tensionVigTarget = 1 + (VIGNETTE_PEAK_T - 1) * intensity  -- 1 → VIGNETTE_PEAK_T
	startTensionEase()
end

local function clearTension()
	tensionFOVTarget = FOV_NORMAL
	tensionVigTarget = 1
	startTensionEase()
end
clearTension()  -- baseline

-- ═════ helpers ═════
local function tw(obj, t, props, style, dir)
	local tween = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tween:Play(); return tween
end

-- t = 0 (shown) .. 1 (hidden). Toggles Visible and restores transparencies
-- to the captured Studio targets when shown, or 1 when hidden.
local function setVis(l, t)
	l.Visible = (t < 1)
	l.TextTransparency = (t < 1) and (shownTextT[l] or 0) or 1
	local s = strokes[l]
	if s then s.Transparency = (t < 1) and (shownStrokeT[s] or 0) or 1 end
end

local function twVis(l, time, t, style, dir)
	if t < 1 then l.Visible = true end
	local targetText = (t < 1) and (shownTextT[l] or 0) or 1
	tw(l, time, { TextTransparency = targetText }, style, dir)
	local s = strokes[l]
	if s then
		local targetStroke = (t < 1) and (shownStrokeT[s] or 0) or 1
		local tween = tw(s, time, { Transparency = targetStroke }, style, dir)
		if t >= 1 then tween.Completed:Connect(function() l.Visible = false end) end
	end
end

local Cinematics = {}

function Cinematics.SetPreGame(seconds, ready, needed)
	startsIn.Text = "GAME STARTS IN " .. tostring(seconds)
	readyCount.Text = string.format("%d/%d", ready or 2, needed or 2)
	pregamePanel.Visible = true
	pregamePanel.BackgroundTransparency = shownPanelBG
	if panelStroke then panelStroke.Transparency = shownPanelStrokeT end
	setVis(startsIn, 0)
	setVis(readyCount, 0)
end

function Cinematics.HidePreGame()
	setVis(startsIn, 1)
	setVis(readyCount, 1)
	pregamePanel.BackgroundTransparency = 1
	if panelStroke then panelStroke.Transparency = 1 end
	pregamePanel.Visible = false
end

function Cinematics.GoSlam(target, isRisk)
	Cinematics.HidePreGame()
	-- Diagonal swipe — the Black frame (Rotation -45, Anchor 0.5,0.5, Size 2.6×2.6)
	-- stays fully opaque and slides clean across the screen: in from the
	-- bottom-left to cover, holds for the GO, then continues out the top-right.
	-- No transparency fade, so it reads as a solid swipe rather than a dissolve.
	black.BackgroundTransparency = 0
	black.Position = UDim2.fromScale(-0.7, 1.7)            -- off bottom-left
	-- Swipe IN to cover.
	tw(black, 0.5, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	task.wait(0.5)
	-- Pop the GO while the screen is covered.
	setVis(goLabel, 0)
	goScale.Scale = 2.6
	tw(goScale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	task.wait(0.55)
	-- Reveal the target text, hide GO, then swipe OUT the top-right.
	Cinematics.ShowTarget(target or 7, isRisk)
	twVis(goLabel, 0.3, 1)
	tw(black, 0.5, { Position = UDim2.fromScale(1.7, -0.7) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	task.wait(0.5)
	black.BackgroundTransparency = 1
	black.Position = UDim2.fromScale(-0.7, 1.7)           -- park off bottom-left for next time
end

local targetVisible = false
function Cinematics.ShowTarget(targetValue, isRisk)
	if isRisk then
		-- Risk "On The Dot" mode: must land EXACTLY on the target. Show it in the
		-- rig's two-field SS:HH style (target is whole seconds, so :00 hundredths).
		targetText.Text = string.format("On The Dot: %d:00", targetValue or 7)
	else
		targetText.Text = string.format("Don't go above %g", targetValue or 7)
	end
	if targetVisible then return end
	targetVisible = true
	targetText.Visible = true
	Cinematics.ShowRoundCircles()
	tw(targetText, 0.3, {
		TextTransparency       = shownTextT[targetText] or 0,
		BackgroundTransparency = shownTargetBG,
	})
	local s = strokes[targetText]
	if s then tw(s, 0.3, { Transparency = shownStrokeT[s] or 0 }) end
end

function Cinematics.HideTarget()
	if not targetVisible then return end
	targetVisible = false
	Cinematics.HideRoundCircles()
	tw(targetText, 0.3, { TextTransparency = 1, BackgroundTransparency = 1 })
	local s = strokes[targetText]
	if s then tw(s, 0.3, { Transparency = 1 }) end
	task.delay(0.3, function() targetText.Visible = false end)
end

-- ═════ round-win circles (HUD mirror of the billboard's circles) ═════
local COLOR_P1 = Color3.fromRGB(225, 55, 55)
local COLOR_P2 = Color3.fromRGB(70, 130, 240)

local function resetRoundCircles()
	for _, c in ipairs(circleSlots) do
		c.BackgroundColor3 = circleEmptyBG
		local av = c:FindFirstChild("Avatar")
		if av then
			av.Image = ""
			av.ImageTransparency = 1
		end
	end
end

function Cinematics.ShowRoundCircles()
	resetRoundCircles()
	roundCircles.Visible = true
end

function Cinematics.HideRoundCircles()
	roundCircles.Visible = false
	resetRoundCircles()
end

-- Fill circle `index` with the winning seat's color and avatar (matches the
-- billboard styling). Index is 1-based (1..3 for best-of-3).
function Cinematics.SetCircleWin(index, winnerSeat, userId)
	local c = circleSlots[index]
	if not c then return end
	roundCircles.Visible = true
	c.BackgroundColor3 = (winnerSeat == "Seat1") and COLOR_P1 or COLOR_P2
	local av = c:FindFirstChild("Avatar")
	if av and userId then
		av.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
		tw(av, 0.25, { ImageTransparency = 0 })
	end
end

function Cinematics.TurnCountdown()
	for n = 3, 1, -1 do
		turnNum.Text = tostring(n)
		setVis(turnNum, 0)
		turnScale.Scale = 1.8
		tw(turnScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		task.wait(0.55)
		twVis(turnNum, 0.2, 1)
		task.wait(0.2)
	end
end

function Cinematics.ShowWinner(name)
	winner.Text = (name and (name .. " WINS!")) or "WINNER!"
	setVis(winner, 0)
end

function Cinematics.HideWinner()
	setVis(winner, 1)
end

function Cinematics.RoundFlash(round)
	roundFlash.Text = "ROUND " .. tostring(round)
	setVis(roundFlash, 0)
	task.delay(1.2, function() twVis(roundFlash, 0.3, 1) end)
end

-- ═════ camera (locked to active side) ═════
local camConn, camStartCF, camGoal, camT0

local function sideCFrame(group, seatName)
	local rig = group:FindFirstChild("TimerRig")
	if not rig then return nil end
	local seat = group:FindFirstChild(seatName)
	if not seat then return nil end
	local core = rig:FindFirstChild("Core")
	local t    = group:FindFirstChild("table")
	local center = (t and t:IsA("Model")) and t:GetBoundingBox().Position
		or (core and core.Position) or group:GetPivot().Position

	-- Horizontal direction from the seat toward the rig.
	local d = center - seat.Position; d = Vector3.new(d.X, 0, d.Z)
	if d.Magnitude < 0.1 then d = Vector3.new(0, 0, 1) end
	d = d.Unit

	-- Frame the active player's button + timer screen.
	local button = rig:FindFirstChild("Button_" .. seatName)
	local screen = rig:FindFirstChild("Screen_" .. seatName)
	local buttonPos
	if button then
		if button:IsA("Model") then
			local cf = button:GetBoundingBox(); buttonPos = cf.Position
		elseif button:IsA("BasePart") then
			buttonPos = button.Position
		end
	end
	if not buttonPos then
		buttonPos = seat.Position + d * 2.5 + Vector3.new(0, 1.5, 0)
	end
	local screenPos = (screen and screen.Position) or (center + Vector3.new(0, 2.5, 0))

	-- Is the local player the one whose turn this is?
	local occ = seat.Occupant
	local localIsActive = (occ ~= nil) and (occ.Parent == player.Character)

	local camPos, lookAt
	if localIsActive then
		-- My turn: camera over my own button, looking across it at the timer screen;
		-- I'm behind the camera, out of frame.
		camPos = buttonPos - d * 1.5 + Vector3.new(0, 2.2, 0)
		lookAt = buttonPos:Lerp(screenPos, 0.6) + Vector3.new(0, 0.2, 0)
	else
		-- Opponent's turn: a 3/4 view from behind-and-beside the active player,
		-- raised, aimed between their head and the timer screen — so I can see the
		-- player AND read the timer. The camera stays on the player's side of the
		-- rig so the screen face points roughly toward it (readable).
		local perp = d:Cross(Vector3.yAxis)
		if perp.Magnitude < 0.1 then perp = Vector3.new(0, 0, 1) end
		perp = perp.Unit
		local cp = group:FindFirstChild("CameraPart")
		if cp and (cp.Position - center):Dot(perp) < 0 then perp = -perp end
		local headPos = seat.Position + Vector3.yAxis * 1.2          -- approx seated head
		camPos = seat.Position - d * 2.2 + perp * 5.0 + Vector3.yAxis * 2.6
		lookAt = headPos:Lerp(screenPos, 0.55) + Vector3.yAxis * 0.2 -- frame player + timer
	end
	return CFrame.lookAt(camPos, lookAt)
end

local function setCameraGoal(goalCF)
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	camStartCF = cam.CFrame
	camGoal = goalCF
	camT0 = os.clock()
	if not camConn then
		camConn = RunService.RenderStepped:Connect(function()
			local c = Workspace.CurrentCamera
			if c.CameraType ~= Enum.CameraType.Scriptable then c.CameraType = Enum.CameraType.Scriptable end
			local a = math.clamp((os.clock() - camT0) / 0.6, 0, 1)
			a = a * a * (3 - 2 * a)
			c.CFrame = camStartCF:Lerp(camGoal, a)
		end)
	end
end

local function releaseCamera()
	if camConn then camConn:Disconnect(); camConn = nil end
	Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
end

-- ═════ VS reveal (post-GO side pan + cards, matches reference layout) ═════
-- After the GO black slam, the camera pans to a side-on view that frames both
-- seated players, then the overlay assembles one piece at a time, in order:
--   left photo -> "VS" -> right photo -> left record number -> right record number
-- Each piece plays a whoosh as it flies in. Motion is Quint-eased (smooth glide +
-- grow + fade, no stiff snap or tacky overshoot). Which card is on the LEFT of the
-- screen follows the camera, so the player on the left of frame gets the left card.
local FLY_SFX_ID = "rbxassetid://139158121862290"

local vsParts
local vsActive = false
local hiddenTableGui = nil  -- { gui = BillboardGui, prior = boolean }

local function playFlySfx()
	local snd = Instance.new("Sound")
	snd.SoundId = FLY_SFX_ID
	snd.Volume  = 0.65
	snd.Parent  = SoundService
	snd:Play()
	snd.Ended:Connect(function() snd:Destroy() end)
	Debris:AddItem(snd, 6)
end

local function buildVsGui()
	if vsParts then return end
	vsParts = {}
	local function scaleOf(o)
		local sc = o:FindFirstChildOfClass("UIScale")
		if not sc then sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = o end
		return sc
	end
	-- Photo cards: capture each card's Studio "shown" transparencies + position as
	-- the reveal targets, so you can restyle/reposition them freely in Studio.
	for key, name in pairs({ leftPic = "LeftCard", rightPic = "RightCard" }) do
		local card = gui:FindFirstChild(name)
		if card then
			local photo  = card:FindFirstChild("Photo")
			local stroke = card:FindFirstChildOfClass("UIStroke")
			local fades  = { { card, "BackgroundTransparency", card.BackgroundTransparency } }
			if stroke then fades[#fades + 1] = { stroke, "Transparency", stroke.Transparency } end
			if photo  then fades[#fades + 1] = { photo, "ImageTransparency", photo.ImageTransparency } end
			vsParts[key] = { obj = card, scale = scaleOf(card), photo = photo, target = card.Position, fades = fades }
		end
	end
	-- Text parts: VS plus the two records.
	for key, name in pairs({ vs = "VS", leftNum = "LeftRecord", rightNum = "RightRecord" }) do
		local lbl = gui:FindFirstChild(name)
		if lbl then
			local stroke = lbl:FindFirstChildOfClass("UIStroke")
			local fades  = { { lbl, "TextTransparency", lbl.TextTransparency } }
			if stroke then fades[#fades + 1] = { stroke, "Transparency", stroke.Transparency } end
			vsParts[key] = { obj = lbl, scale = scaleOf(lbl), label = lbl, target = lbl.Position, fades = fades }
		end
	end
	-- Start hidden (these live in DuelCinematics; default Visible=false so they
	-- never flash on join).
	for _, p in pairs(vsParts) do
		p.obj.Visible = false
		for _, f in ipairs(p.fades) do f[1][f[2]] = 1 end
	end
end

-- Side-on camera that frames both seats with one on each side of the view.
local function sideViewCFrame(group)
	local s1 = group:FindFirstChild("Seat1")
	local s2 = group:FindFirstChild("Seat2")
	if not (s1 and s2) then return nil end
	local p1, p2 = s1.Position, s2.Position
	local center = Vector3.new((p1.X + p2.X) / 2, math.max(p1.Y, p2.Y) + 1.2, (p1.Z + p2.Z) / 2)
	local axis = Vector3.new(p2.X - p1.X, 0, p2.Z - p1.Z)
	local sep = axis.Magnitude
	if sep < 0.1 then axis = Vector3.new(1, 0, 0); sep = 6 else axis = axis.Unit end
	local perp = axis:Cross(Vector3.yAxis)
	if perp.Magnitude < 0.1 then perp = Vector3.new(0, 0, 1) end
	perp = perp.Unit
	local cp = group:FindFirstChild("CameraPart")
	if cp and (cp.Position - center):Dot(perp) < 0 then perp = -perp end
	local dist = math.max(sep * 1.15, 12)
	local camPos = center + perp * dist + Vector3.yAxis * 3.4
	return CFrame.lookAt(camPos, center + Vector3.yAxis * 0.5)
end

-- Smooth fly-in: glide from a small offset + scale 0.72->1 + fade, all Quint/Quad
-- eased so it eases to rest without snapping or bouncing.
local function reveal(part, ox, oy, noSfx)
	if not noSfx then playFlySfx() end
	for _, f in ipairs(part.fades) do f[1][f[2]] = 1 end  -- start hidden
	part.scale.Scale = 0.72
	local tx, ty = part.target.X.Scale, part.target.Y.Scale
	part.obj.Position = UDim2.fromScale(tx + (ox or 0), ty + (oy or 0))
	part.obj.Visible = true
	tw(part.obj, 0.52, { Position = part.target }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	tw(part.scale, 0.52, { Scale = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	for _, f in ipairs(part.fades) do
		tw(f[1], 0.42, { [f[2]] = f[3] }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end
end

local function vsIntro(group, dataA, dataB)
	if not group then return end
	buildVsGui()
	vsActive = true

	-- Hide this table's billboard for the two seated players (client-local only).
	local tbl  = group:FindFirstChild("table")
	local tgui = tbl and tbl:FindFirstChild("TableGui")
	if tgui then
		hiddenTableGui = { gui = tgui, prior = tgui.Enabled }
		tgui.Enabled = false
	end

	-- Pan to the side view.
	local camCF = sideViewCFrame(group)
	local cam = Workspace.CurrentCamera
	if cam then cam.FieldOfView = FOV_NORMAL end
	if camCF then setCameraGoal(camCF) end

	-- Which seat sits on the camera's left (negative local X)?
	local s1 = group:FindFirstChild("Seat1")
	local s2 = group:FindFirstChild("Seat2")
	local function lx(seat) return (camCF and seat) and camCF:PointToObjectSpace(seat.Position).X or 0 end
	local seat1OnLeft = lx(s1) <= lx(s2)

	local bySeat = {}
	bySeat[dataA.seat] = dataA
	bySeat[dataB.seat] = dataB
	local leftData  = seat1OnLeft and bySeat.Seat1 or bySeat.Seat2
	local rightData = seat1OnLeft and bySeat.Seat2 or bySeat.Seat1

	local function headshot(d)
		return d.userId and string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=420&h=420", d.userId) or ""
	end
	vsParts.leftPic.photo.Image  = headshot(leftData)
	vsParts.rightPic.photo.Image = headshot(rightData)
	vsParts.leftNum.label.Text   = string.format("%d-%d", leftData.wins or 0, leftData.losses or 0)
	vsParts.rightNum.label.Text  = string.format("%d-%d", rightData.wins or 0, rightData.losses or 0)

	-- Assemble one piece at a time, in the requested order.
	task.spawn(function()
		task.wait(0.5)                       -- let the camera settle into the side view
		if not vsActive then return end
		reveal(vsParts.leftPic,  -0.10, 0)   -- 1. left photo
		task.wait(0.72); if not vsActive then return end
		reveal(vsParts.vs,        0,   -0.03)-- 2. VS
		task.wait(0.72); if not vsActive then return end
		reveal(vsParts.rightPic,  0.10, 0)   -- 3. right photo
		task.wait(0.72); if not vsActive then return end
		reveal(vsParts.leftNum,   0,    0.05)     -- 4. left record
		task.wait(0.72); if not vsActive then return end
		reveal(vsParts.rightNum,  0,    0.05)     -- 5. right record
	end)
end

local function hideVs()
	if not vsActive then return end
	vsActive = false
	if not vsParts then return end
	for _, part in pairs(vsParts) do
		local obj = part.obj
		if obj and obj.Visible then
			tw(part.scale, 0.28, { Scale = 0.86 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			for _, f in ipairs(part.fades) do
				tw(f[1], 0.28, { [f[2]] = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
			task.delay(0.3, function() if not vsActive then obj.Visible = false end end)
		end
	end
end

local function restoreTableGui()
	if hiddenTableGui and hiddenTableGui.gui then
		hiddenTableGui.gui.Enabled = hiddenTableGui.prior
	end
	hiddenTableGui = nil
end

-- The duel scoreboard billboard (cloned onto the rig Core when the match starts)
-- is hidden client-side for the two seated players. BillboardGui.PlayerToHideFrom
-- only hides from one player, so we disable it locally for each participant; other
-- players still see it. A ChildAdded watcher catches it if it replicates late.
local duelBBConn = nil
local function hideDuelBillboard(group)
	if duelBBConn then duelBBConn:Disconnect(); duelBBConn = nil end
	local rig  = group and group:FindFirstChild("TimerRig")
	local core = rig and rig:FindFirstChild("Core")
	if not core then return end
	local existing = core:FindFirstChild("DuelBillboard")
	if existing and existing:IsA("BillboardGui") then existing.Enabled = false end
	duelBBConn = core.ChildAdded:Connect(function(child)
		if child.Name == "DuelBillboard" and child:IsA("BillboardGui") then
			child.Enabled = false
		end
	end)
end
local function restoreDuelBillboard()
	if duelBBConn then duelBBConn:Disconnect(); duelBBConn = nil end
end

-- ═════ HUD swoosh (clear the screen while a duel is on) ═════
-- When the game starts, the regular HUD flies off to its nearest edge so it's
-- out of the way (top-anchored bits swoosh up); it all swooshes back when the
-- match ends or the table empties. Positions are captured at hide time and
-- restored exactly on show.
local hudGui = playerGui:WaitForChild("UI")
local hudHidden = false
local hudOrig = {}   -- [GuiObject] = original Position

local function isFullScreen(o)
	return o.Size.X.Scale >= 0.99 and o.Size.Y.Scale >= 0.99
		and o.Position.X.Scale <= 0.01 and o.Position.Y.Scale <= 0.01
end

-- Nearest-edge exit: top -> up, bottom -> down, otherwise left/right.
local function exitPos(o)
	local px, py = o.Position.X.Scale, o.Position.Y.Scale
	local ox, oy = o.Position.X.Offset, o.Position.Y.Offset
	if py < 0.28 then
		return UDim2.new(px, ox, -1.6, 0)
	elseif py > 0.72 then
		return UDim2.new(px, ox, 1.8, 0)
	elseif px < 0.5 then
		return UDim2.new(-1.7, 0, py, oy)
	else
		return UDim2.new(1.8, 0, py, oy)
	end
end

local function hideHud()
	if hudHidden then return end
	hudHidden = true
	hudOrig = {}
	for _, o in ipairs(hudGui:GetChildren()) do
		if o:IsA("GuiObject") and o.Visible and not isFullScreen(o) and o.Name ~= "QuickPlay" then
			hudOrig[o] = o.Position
			tw(o, 0.45, { Position = exitPos(o) }, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
		end
	end
end

local function showHud()
	if not hudHidden then return end
	hudHidden = false
	for o, pos in pairs(hudOrig) do
		if o and o.Parent then
			tw(o, 0.55, { Position = pos }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		end
	end
	hudOrig = {}
end

-- Quick Play is managed on its own: it leaves frame for the duel and swooshes back
-- a few seconds AFTER the game finishes (not the instant you stand up).
local quickPlayBtn = hudGui:WaitForChild("QuickPlay")
local quickPlayHome
local qpToken = 0
local function ensureQPHome()
	if not quickPlayHome then quickPlayHome = quickPlayBtn.Position end
end
local function qpOffScreen()
	ensureQPHome()
	return UDim2.new(quickPlayHome.X.Scale, quickPlayHome.X.Offset, 1.7, 0)  -- below the screen
end
local function hideQuickPlay()
	ensureQPHome()
	qpToken += 1                       -- cancel any pending return
	quickPlayBtn.Position = qpOffScreen()
end
-- Quick Play visibility is owned by CasesClient's refreshQuickPlay (the seated
-- rule: hidden while sitting). This script only owns the swoosh POSITION. On
-- game end we glide the button back to its home slot; whether it's actually
-- shown is decided by refreshQuickPlay (which re-runs on the InDuel attribute
-- clearing). That keeps a finished game that left the player seated from ever
-- forcing Quick Play on screen.
local function returnQuickPlayAfter(delaySec)
	ensureQPHome()
	qpToken += 1
	local myToken = qpToken
	quickPlayBtn.Position = qpOffScreen()   -- ensure it starts off-screen
	task.delay(delaySec, function()
		if myToken ~= qpToken then return end  -- superseded by a new game
		-- Glide home regardless; CasesClient controls Visible. If the player is
		-- seated, refreshQuickPlay keeps Visible=false so nothing shows even though
		-- the position is home.
		tw(quickPlayBtn, 0.5, { Position = quickPlayHome }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end)
end

-- ═════ rig timer + slam ═════
local timerStartServer, canSlam
local timerConns = {}     -- [tableGroup] = Heartbeat connection: one rig-render loop PER TABLE
local myMatchGroup = nil  -- table group of the match I'M playing in (nil = not in a match)
local turnPhase     -- nil | "start" (awaiting manual start) | "pending" | "stop" (running, can stop)
local turnRunStart  -- server time the running climb began (for the 0.01 stop guard)

-- Per-table cache of the rig screens' TimeLabels (+ their UIStrokes). The three
-- helpers below run every Heartbeat for every table with a climbing timer, on
-- every client — the recursive FindFirstChild calls they used to make each frame
-- were the hottest scripted path in the game. Build the refs once per table and
-- reuse them; the cache self-heals if a label ever leaves the tree.
local EMPTY_SCREENS = {}
local screenCache = {}  -- [tableGroup] = { {label=TextLabel, stroke=UIStroke?}, ... }

local function getScreenLabels(group)
	if not group then return EMPTY_SCREENS end
	local cached = screenCache[group]
	if cached then
		local valid = true
		for _, e in ipairs(cached) do
			if not e.label.Parent then valid = false break end
		end
		if valid then return cached end
	end
	local list = {}
	local rig = group:FindFirstChild("TimerRig")
	if rig then
		for _, sn in ipairs({ "Screen_Seat1", "Screen_Seat2" }) do
			local scr = rig:FindFirstChild(sn)
			local lbl = scr and scr:FindFirstChild("TimeLabel", true)
			if lbl then
				list[#list + 1] = { label = lbl, stroke = lbl:FindFirstChildWhichIsA("UIStroke") }
			end
		end
	end
	screenCache[group] = list
	return list
end

local function setScreens(group, value)
	local txt = string.format("%05.2f", value)
	for _, e in ipairs(getScreenLabels(group)) do
		e.label.Text = txt
	end
end

local function colorScreens(group, color)
	for _, e in ipairs(getScreenLabels(group)) do
		e.label.TextColor3 = color
	end
end

-- t = 0 fully visible .. 1 fully transparent. Fades the text and its outline.
local function fadeScreens(group, t)
	t = math.clamp(t, 0, 1)
	for _, e in ipairs(getScreenLabels(group)) do
		e.label.TextTransparency = t
		if e.stroke then e.stroke.Transparency = t end
	end
end

-- ═════ timer tick sounds + heartbeat + between-round rewind ═════
local SECOND_TICK_ID = "rbxassetid://126426395279301"  -- plays on each whole second
local HEARTBEAT_ID   = "rbxassetid://135454814111440"  -- repeating beat; speeds up near the target

-- Heartbeat pacing: seconds between beats far from the target vs right at it. The
-- curve (>1) keeps it calm early and pounds noticeably faster as you close in.
local HB_INTERVAL_FAR  = 0.95
local HB_INTERVAL_NEAR = 0.16
local HB_CURVE         = 1.6

local secondTickSound, heartbeatSound
local function ensureTickSounds()
	if not secondTickSound then
		secondTickSound = Instance.new("Sound")
		secondTickSound.SoundId = SECOND_TICK_ID
		secondTickSound.Volume  = 0.6
		secondTickSound.Parent  = SoundService
	end
	if not heartbeatSound then
		heartbeatSound = Instance.new("Sound")
		heartbeatSound.SoundId = HEARTBEAT_ID
		heartbeatSound.Volume  = 0.65
		heartbeatSound.Parent  = SoundService
	end
end

local function playSecondTick()
	ensureTickSounds()
	secondTickSound.TimePosition = 0
	secondTickSound:Play()
end

-- Repeating heartbeat whose interval shrinks as `norm` (0..1 proximity to target)
-- grows. Call every frame while it's your turn and the timer is running; it
-- self-throttles to the right beat rate. AT or PAST target it switches to a
-- continuous looped playback so the rhythm doesn't disappear into the
-- inter-pulse gap at max speed.
local lastBeat = 0
local function pulseHeartbeat(norm)
	ensureTickSounds()
	if norm >= 1 then
		-- At/above target: continuous loop, no gaps.
		if not heartbeatSound.Looped or not heartbeatSound.IsPlaying then
			heartbeatSound.Looped = true
			heartbeatSound.TimePosition = 0
			heartbeatSound:Play()
		end
		return
	end
	-- Under target: restore pulsing mode if we were looped previously.
	if heartbeatSound.Looped then
		heartbeatSound.Looped = false
		heartbeatSound:Stop()
	end
	norm = math.clamp(norm, 0, 1)
	local interval = HB_INTERVAL_FAR + (HB_INTERVAL_NEAR - HB_INTERVAL_FAR) * (norm ^ HB_CURVE)
	local now = os.clock()
	if now - lastBeat >= interval then
		lastBeat = now
		heartbeatSound.TimePosition = 0
		heartbeatSound:Play()
	end
end

local function resetHeartbeat()
	lastBeat = 0
	if heartbeatSound then
		heartbeatSound.Looped = false
		heartbeatSound:Stop()
	end
end

-- Last value shown on the rig, so the next round can rewind down from it.
local lastShownValue, lastShownGroup = nil, nil

-- Smoothly count the rig screen back down to 00.00 between rounds, ticking on each
-- whole second crossed and rolling the fast tick as the hundredths fall.
local function rewindScreens(group, fromVal, dur)
	fromVal = math.max(fromVal or 0, 0)
	dur = dur or 0.7
	colorScreens(group, TIMER_COLOR_CLEAR)
	fadeScreens(group, 0)
	local t0 = os.clock()
	local lastWhole = math.floor(fromVal)
	while true do
		local a = math.clamp((os.clock() - t0) / dur, 0, 1)
		local e = 1 - (1 - a) * (1 - a)   -- ease-out
		local v = fromVal * (1 - e)
		setScreens(group, v)
		local whole = math.floor(v)
		if whole ~= lastWhole then lastWhole = whole; playSecondTick() end
		if a >= 1 then break end
		RunService.Heartbeat:Wait()
	end
	setScreens(group, 0)
	playSecondTick()
end

local function setSlamText(txt)
	if slamBtn:IsA("TextButton") then slamBtn.Text = txt end
	for _, d in ipairs(slamBtn:GetDescendants()) do
		if d:IsA("TextButton") or d:IsA("TextLabel") then d.Text = txt end
	end
end

local function doSlam()
	if turnPhase == "start" then
		-- First click of a later turn: ask the server to start the climb.
		turnPhase = "pending"
		Network.send("DuelStart")
		return
	end
	if turnPhase ~= "stop" then return end
	if not canSlam or not timerStartServer then return end
	-- At least 0.01s must pass after the timer starts before a stop click counts.
	if turnRunStart and (Workspace:GetServerTimeNow() - turnRunStart) < 0.01 then return end
	local elapsed = Workspace:GetServerTimeNow() - timerStartServer
	if elapsed < 0 then elapsed = 0 end
	canSlam = false
	turnPhase = nil
	slamBtn.Visible = false
	Network.send("DuelSlam", elapsed)
end

-- Space-bar slam: bound only during your slam window so Space triggers the slam
-- without Roblox's default jump-out-of-seat behaviour aborting the match.
local SLAM_ACTION = "DuelSlamAction"
local slamBound = false
local function bindSlamInput()
	if slamBound then return end
	slamBound = true
	CAS:BindAction(SLAM_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then doSlam() end
		return Enum.ContextActionResult.Sink  -- prevent default jump
	-- Bound to keyboard (Space) AND gamepad (A / right trigger) so console players can
	-- start/stop the timer. Sinking these also blocks the seat's default jump on both.
	end, false, Enum.KeyCode.Space, Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonR2)
end
local function unbindSlamInput()
	if not slamBound then return end
	slamBound = false
	pcall(function() CAS:UnbindAction(SLAM_ACTION) end)
end

slamBtn.Activated:Connect(doSlam)

-- ═════ remotes ═════
Network.onClient("DuelPreGame", function(s, ready, needed, group)
	-- Sent only to THIS match's players — anchor which table is ours.
	myMatchGroup = group or myMatchGroup
	hideHud()
	hideQuickPlay()
	hideDuelBillboard(group)
	Cinematics.SetPreGame(s, ready, needed)
end)

Network.onClient("DuelGo", function(target, isRisk)
	player:SetAttribute("InDuel", true)
	task.spawn(function() Cinematics.GoSlam(target, isRisk) end)
end)

Network.onClient("DuelVsIntro", function(group, dataA, dataB)
	player:SetAttribute("InDuel", true)
	task.spawn(function() vsIntro(group, dataA, dataB) end)
end)

Network.onClient("DuelShowSide", function(group, seatName)
	player:SetAttribute("InDuel", true)
	hideVs()
	if group then
		local cf = sideCFrame(group, seatName)
		if cf then setCameraGoal(cf) end
	end
end)

Network.onClient("DuelTurnCountdown", function()
	task.spawn(Cinematics.TurnCountdown)
end)

Network.onClient("DuelRoundStart", function(round, target)
	-- Rewind the rig timer back down to 00.00 before this round's countdown.
	if lastShownGroup then
		local g, fromV = lastShownGroup, lastShownValue or 0
		task.spawn(function() rewindScreens(g, fromV, 0.7) end)
	end
	if target then Cinematics.ShowTarget(target) end
	Cinematics.RoundFlash(round)
end)

Network.onClient("DuelAwaitStart", function(group, seatName, carry)
	-- Later-turn manual start: freeze the rig at the carried value and wait for the
	-- active player to click START. Sent only to this match's players.
	myMatchGroup = group or myMatchGroup
	if group and timerConns[group] then timerConns[group]:Disconnect(); timerConns[group] = nil end
	carry = carry or 0
	timerStartServer = nil
	turnRunStart = nil
	setScreens(group, carry)
	colorScreens(group, TIMER_COLOR_CLEAR)
	fadeScreens(group, 0)
	clearTension()
	local seat = group and group:FindFirstChild(seatName)
	local occ  = seat and seat.Occupant
	local mine = (occ ~= nil) and (occ.Parent == player.Character)
	if mine then
		turnPhase = "start"
		canSlam = false
		setSlamText("TAP TO START")
		slamBtn.Visible = true
		bindSlamInput()
	else
		turnPhase = nil
		canSlam = false
		slamBtn.Visible = false
		unbindSlamInput()
	end
end)

Network.onClient("DuelTimerStart", function(serverStart, target, group, seatName)
	-- Broadcast so SPECTATORS see every table's rig climb — but only events for
	-- MY OWN match may touch my slam state, sounds, or tension. Without this
	-- gate, any other table starting a turn killed this player's controls.
	local mine = (group ~= nil) and (group == myMatchGroup)

	colorScreens(group, TIMER_COLOR_CLEAR)  -- start green; heartbeat lerps to red
	fadeScreens(group, 0)                   -- fully visible at the start of the turn

	if mine then
		timerStartServer = serverStart
		turnRunStart = Workspace:GetServerTimeNow()  -- 0.01 stop guard reference
		local seat = group and group:FindFirstChild(seatName)
		local occ  = seat and seat.Occupant
		canSlam = (occ ~= nil) and (occ.Parent == player.Character)
		turnPhase = canSlam and "stop" or nil
		if canSlam then setSlamText("STOP!") end
		slamBtn.Visible = canSlam
		if canSlam then bindSlamInput() else unbindSlamInput() end
		resetHeartbeat()
	end

	-- One render loop PER TABLE so concurrent matches never clobber each other.
	if timerConns[group] then timerConns[group]:Disconnect() end
	local tgt = target or 7
	local tickLastWhole = math.floor(math.max(0, Workspace:GetServerTimeNow() - serverStart))
	timerConns[group] = RunService.Heartbeat:Connect(function()
		local v = Workspace:GetServerTimeNow() - serverStart
		if v < 0 then v = 0 end
		setScreens(group, v)
		-- Tension + screen color scale with proximity to target. Capped at 1.
		local norm = math.clamp(v / tgt, 0, 1)
		colorScreens(group, TIMER_COLOR_CLEAR:Lerp(TIMER_COLOR_DANGER, norm))
		fadeScreens(group, TIMER_FADE_MAX * (norm ^ TIMER_FADE_CURVE))
		if mine then
			if player:GetAttribute("InDuel") then setTension(norm ^ CURVE) end
			-- One tick per whole second crossed — only for OUR match, so other
			-- tables' duels stay silent for us.
			local whole = math.floor(v)
			if whole ~= tickLastWhole then tickLastWhole = whole; playSecondTick() end
			-- Heartbeat only on your own turn, pounding faster as the target nears.
			if canSlam then pulseHeartbeat(norm) end
		end
	end)
end)

Network.onClient("DuelTimerStop", function(elapsed, result, group, seatName)
	-- Stop THIS table's render loop and paint its result — for everyone.
	if timerConns[group] then timerConns[group]:Disconnect(); timerConns[group] = nil end
	setScreens(group, elapsed)
	local col = Color3.fromRGB(255, 42, 42)
	if result == "exact" then col = Color3.fromRGB(60, 255, 90)
	elseif result == "pass" then col = Color3.fromRGB(255, 220, 70) end
	colorScreens(group, col)
	fadeScreens(group, 0)
	-- My slam state / sounds / tension only reset when it's MY match's turn ending.
	if group ~= nil and group == myMatchGroup then
		canSlam = false
		turnPhase = nil
		turnRunStart = nil
		slamBtn.Visible = false
		unbindSlamInput()
		resetHeartbeat()                        -- stop the looped pound
		if player:GetAttribute("InDuel") then clearTension() end
		lastShownValue = elapsed
		lastShownGroup = group
	end
end)

Network.onClient("DuelEnd", function(winnerName)
	hideVs()
	Cinematics.ShowWinner(winnerName)
	Cinematics.HideTarget()
end)

-- Server mirrors the billboard circles to the HUD so players locked to the
-- cinematic camera can see the round score without looking at the table.
Network.onClient("DuelCircle", function(index, winnerSeat, userId)
	Cinematics.SetCircleWin(index, winnerSeat, userId)
end)

-- Server picks a random Sound name from SoundService.LostSFX and broadcasts it
-- to both seats on bust + match end. We clone it so simultaneous plays don't
-- clobber each other and so destroy on finish keeps SoundService clean.
Network.onClient("DuelLostSfx", function(soundName)
	local de = SoundService:FindFirstChild("DuelSoundEffects")
	local folder = (de and de:FindFirstChild("LostSFX")) or SoundService:FindFirstChild("LostSFX")
	local src = folder and folder:FindFirstChild(soundName)
	if not src or not src:IsA("Sound") then return end
	local copy = src:Clone()
	copy.Parent = SoundService
	copy:Play()
	copy.Ended:Connect(function() copy:Destroy() end)
	Debris:AddItem(copy, 10)
end)

Network.onClient("DuelReset", function(group)
	-- Rig visuals + that table's render loop reset for EVERYONE…
	if group then
		setScreens(group, 0)
		colorScreens(group, Color3.fromRGB(255, 42, 42))
		fadeScreens(group, 0)
		if timerConns[group] then timerConns[group]:Disconnect(); timerConns[group] = nil end
	end
	-- …but the FULL UI teardown (HUD back, cinematics hidden, camera released)
	-- only when it's MY match that reset. Without this gate, any other table's
	-- match ending would tear down this player's duel mid-game.
	if group ~= nil and group ~= myMatchGroup then return end
	myMatchGroup = nil
	lastShownValue, lastShownGroup = nil, nil
	canSlam = false
	turnPhase = nil
	turnRunStart = nil
	slamBtn.Visible = false
	unbindSlamInput()
	resetHeartbeat()                        -- kill any looped pound left running
	Cinematics.HidePreGame()
	Cinematics.HideWinner()
	Cinematics.HideTarget()
	hideVs()
	restoreTableGui()
	restoreDuelBillboard()
	showHud()
	if player:GetAttribute("InDuel") then
		clearTension()
		returnQuickPlayAfter(3)   -- Quick Play swooshes back in 3s after the game ends
		player:SetAttribute("InDuel", false)
		releaseCamera()
	end
end)
