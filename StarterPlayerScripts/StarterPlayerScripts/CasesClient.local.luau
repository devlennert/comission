local Players      = game:GetService("Players")
local TweenService  = game:GetService("TweenService")
local RunService    = game:GetService("RunService")
local RS           = game:GetService("ReplicatedStorage")

local player  = Players.LocalPlayer
local camera  = workspace.CurrentCamera
local Network = require(RS:WaitForChild("Modules"):WaitForChild("Network"))

local mainUI        = player.PlayerGui:WaitForChild("MainUI")
local convinceFrame = mainUI:WaitForChild("ConvinceFrame")
local guessFrame    = mainUI:WaitForChild("GuessFrame")
local timerLabel    = mainUI:WaitForChild("Timer")
local case1Button   = guessFrame:WaitForChild("Case1")
local case2Button   = guessFrame:WaitForChild("Case2")

local gameplayUI = player.PlayerGui:WaitForChild("UI")

local reasonFrame    = mainUI:WaitForChild("ReasonFrame")
local reasonLabel    = reasonFrame:WaitForChild("TextLabel")
local reasonOrigSize = reasonFrame.Size
reasonFrame.Visible  = false
reasonFrame.Size     = UDim2.new(0, 0, 0, 0)

local monetizationFrame = mainUI:WaitForChild("Monetization")
monetizationFrame.Visible = false

local waitText  = mainUI:WaitForChild("WaitText")
local playAIBtn = mainUI:WaitForChild("PlayAI")
waitText.Visible  = false
playAIBtn.Visible = false

-- ── Multi-round UI ────────────────────────────────────────────────────────────
local decisionFrame  = mainUI:WaitForChild("DecisionFrame")
local keepGoingBtn   = decisionFrame:WaitForChild("KeepGoing")
local cashOutBtn     = decisionFrame:WaitForChild("CashOut")
local keepGoingLabel = keepGoingBtn:WaitForChild("TextLabel")
local cashOutLabel   = cashOutBtn:WaitForChild("TextLabel")
decisionFrame.Visible = false

-- Store original position for slide animations
local decisionOrigPos = decisionFrame.Position

local earnedMoneyLabel = mainUI:WaitForChild("EarnedMoney")
earnedMoneyLabel.Visible = false

-- UIScale for the bank pop-effect on update
local bankPopScale = Instance.new("UIScale")
bankPopScale.Scale  = 1
bankPopScale.Parent = earnedMoneyLabel

-- ── Keep Going helpers ────────────────────────────────────────────────────────

local keepGoingConns = {}

-- Instant clear – used internally when re-showing or force-hiding
local function clearKeepGoing()
	for _, c in ipairs(keepGoingConns) do c:Disconnect() end
	keepGoingConns = {}
	decisionFrame.Visible  = false
	decisionFrame.Position = decisionOrigPos
end

-- Animated hide used when the player clicks a decision button
local function hideKeepGoingAnimated()
	for _, c in ipairs(keepGoingConns) do c:Disconnect() end
	keepGoingConns = {}
	local targetPos = UDim2.new(
		decisionOrigPos.X.Scale,  decisionOrigPos.X.Offset,
		decisionOrigPos.Y.Scale + 0.06, decisionOrigPos.Y.Offset)
	local tw = TweenService:Create(decisionFrame,
		TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = targetPos })
	tw:Play()
	tw.Completed:Connect(function()
		decisionFrame.Visible  = false
		decisionFrame.Position = decisionOrigPos
	end)
end

-- Public hide – instant (called by server events and cleanup)
local function hideKeepGoing()
	clearKeepGoing()
end

-- ── Camera helpers ─────────────────────────────────────────────────────────────

convinceFrame.Visible = false
guessFrame.Visible    = false
timerLabel.Visible    = false

local case1Top    = convinceFrame:WaitForChild("Case1Top")
local case1Bottom = convinceFrame:WaitForChild("Case1Bottom")
local case2Top    = convinceFrame:WaitForChild("Case2Top")
local case2Bottom = convinceFrame:WaitForChild("Case2Bottom")

local case1TopBtn    = case1Top:WaitForChild("Btn")
local case1BottomBtn = case1Bottom:WaitForChild("Btn")
local case2TopBtn    = case2Top:WaitForChild("Btn")
local case2BottomBtn = case2Bottom:WaitForChild("Btn")

local case1TopText    = case1TopBtn:WaitForChild("AnswerText")
local case1BottomText = case1BottomBtn:WaitForChild("AnswerText")
local case2TopText    = case2TopBtn:WaitForChild("AnswerText")
local case2BottomText = case2BottomBtn:WaitForChild("AnswerText")

local activeSounds    = {}
local currentTween    = nil
local activeHighlight = nil
local timerThread     = nil
local reasonThread    = nil
local currentTableCamCF = nil

-- ── Camera ────────────────────────────────────────────────────────────────────

local function tweenCam(cf, t, style, dir)
	camera.CameraType = Enum.CameraType.Scriptable
	if currentTween then currentTween:Cancel() end
	local tw = TweenService:Create(camera,
		TweenInfo.new(t or 1.0, style or Enum.EasingStyle.Sine, dir or Enum.EasingDirection.Out),
		{ CFrame = cf })
	currentTween = tw; tw:Play(); return tw
end

local function getTableCamCF()
	if currentTableCamCF then return currentTableCamCF end
	local tg = workspace:FindFirstChild("Map")
		and workspace.Map:FindFirstChild("Tables")
		and workspace.Map.Tables:FindFirstChild("TableGroup")
	local cp = tg and tg:FindFirstChild("CameraPart")
	return cp and cp.CFrame or nil
end

local function restore3P()
	if currentTween then currentTween:Cancel(); currentTween = nil end
	camera.CameraType = Enum.CameraType.Custom
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if hrp then camera.CameraSubject = hrp end
end

-- ── Highlight ─────────────────────────────────────────────────────────────────

local function setHighlight(caseName)
	if activeHighlight then activeHighlight:Destroy(); activeHighlight = nil end
	local m = workspace:FindFirstChild(caseName)
	if not m then
		for _, obj in ipairs(workspace:GetChildren()) do
			if obj.Name:sub(1, #caseName) == caseName then m = obj; break end
		end
	end
	if not m then return end
	local hl = Instance.new("Highlight")
	hl.FillColor = Color3.fromRGB(255, 255, 255); hl.FillTransparency = 1
	hl.OutlineColor = Color3.fromRGB(255, 255, 255); hl.OutlineTransparency = 1
	hl.DepthMode = Enum.HighlightDepthMode.Occluded; hl.Adornee = m; hl.Parent = workspace
	activeHighlight = hl
	TweenService:Create(hl, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FillTransparency = 0.7, OutlineTransparency = 0 }):Play()
end

local function clearHighlight()
	if not activeHighlight then return end
	local hl = activeHighlight; activeHighlight = nil
	local tw = TweenService:Create(hl, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FillTransparency = 1, OutlineTransparency = 1 })
	tw:Play(); tw.Completed:Connect(function() hl:Destroy() end)
end

-- ── Timer ─────────────────────────────────────────────────────────────────────

local function stopTimer()
	if timerThread then task.cancel(timerThread); timerThread = nil end
	timerLabel.Visible = false
end

local function startTimer(duration)
	stopTimer()
	timerLabel.Visible = true
	timerThread = task.spawn(function()
		local remaining = duration
		while remaining > 0 do
			local m = math.floor(remaining / 60)
			local s = remaining % 60
			timerLabel.Text = m .. ":" .. string.format("%02d", s)
			task.wait(1)
			remaining -= 1
		end
		timerLabel.Text = "0:00"
		task.wait(0.5)
		timerLabel.Visible = false
		timerThread = nil
	end)
end

-- ── Screen shake ──────────────────────────────────────────────────────────────

local shakeConnection = nil
local function screenShake(intensity, duration)
	if shakeConnection then shakeConnection:Disconnect(); shakeConnection = nil end
	local deadline = tick() + duration
	shakeConnection = RunService.RenderStepped:Connect(function()
		if tick() >= deadline then shakeConnection:Disconnect(); shakeConnection = nil; return end
		local progress = (deadline - tick()) / duration
		local mag = intensity * (progress * progress)
		local ox = (math.random() * 2 - 1) * mag
		local oy = (math.random() * 2 - 1) * mag * 0.6
		camera.CFrame = camera.CFrame * CFrame.new(ox, oy, 0)
			* CFrame.Angles(math.rad((math.random()*2-1)*mag*0.4), math.rad((math.random()*2-1)*mag*0.2), 0)
	end)
end

-- ── Result card ───────────────────────────────────────────────────────────────

local RESULT_MESSAGES = {
	guesser   = { [true] = 'You guessed the <font color="#00CC44"><b>SAFE</b></font> Case!',
		[false] = 'You guessed the <font color="#FF3333"><b>EMPTY</b></font> Case!' },
	presenter = { [true] = 'You <font color="#00CC44"><b>SUCCESSFULLY</b></font> tricked the player!',
		[false] = 'You <font color="#FF3333"><b>FAILED</b></font> to trick the player!' },
}

local function showReasonFrame(role, won)
	if reasonThread then task.cancel(reasonThread) end
	local messages = RESULT_MESSAGES[role]; if not messages then return end
	reasonLabel.Text = messages[won]
	reasonFrame.Size = UDim2.new(0, 0, 0, 0); reasonFrame.Visible = true
	TweenService:Create(reasonFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = reasonOrigSize }):Play()
	reasonThread = task.spawn(function()
		task.wait(4)
		local tw = TweenService:Create(reasonFrame,
			TweenInfo.new(0.3, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut),
			{ Size = UDim2.new(0, 0, 0, 0) })
		tw:Play(); tw.Completed:Wait()
		reasonFrame.Visible = false; reasonThread = nil
	end)
end

-- ── Standard handlers ─────────────────────────────────────────────────────────

Network.onClient("Cases_HideUI",    function() gameplayUI.Enabled = false end)
Network.onClient("Cases_ShowUI",    function() gameplayUI.Enabled = true  end)
Network.onClient("Cases_ShowResult", function(role, won) showReasonFrame(role, won) end)
Network.onClient("Cases_StartTimer", function(duration) startTimer(duration or 30) end)
Network.onClient("Cases_StopTimer",  function() stopTimer() end)

-- ── Multi-round handlers ──────────────────────────────────────────────────────

Network.onClient("Cases_ShowRound", function(round)
	stopTimer()
	timerLabel.Text    = "Round " .. round
	timerLabel.Visible = true
	timerThread = task.spawn(function()
		task.wait(2)
		timerLabel.Visible = false
		timerThread = nil
	end)
end)

-- Bank display with pop-effect on update.
-- The server now only fires this event on the guesser, so the presenter
-- will never see the bank UI (no client-side role check needed).
Network.onClient("Cases_UpdateBank", function(amount)
	if amount and amount > 0 then
		earnedMoneyLabel.Text    = "Bank: $" .. tostring(amount)
		earnedMoneyLabel.Visible = true
		-- Pop scale up then settle back
		bankPopScale.Scale = 1.28
		TweenService:Create(bankPopScale,
			TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1.0 }):Play()
	else
		earnedMoneyLabel.Visible = false
		bankPopScale.Scale = 1
	end
end)

-- Show keep-going / cash-out decision UI.
-- bank        = total accumulated so far (guaranteed if you cash out)
-- lastRound   = round that just ended
-- cashPerRound = prize per round
Network.onClient("Cases_ShowKeepGoing", function(bank, lastRound, cashPerRound)
	clearKeepGoing()   -- instant reset before re-showing

	local totalIfWin = bank + cashPerRound

	-- Keep Going: shows what the player would have IN TOTAL if they win the next round
	keepGoingLabel.Text = string.format(
		"Keep Going\n" ..
			'<font color="#33DD33"><b>$%s total if you win</b></font>',
		tostring(totalIfWin))

	-- Cash Out: shows what they have RIGHT NOW that they'll keep
	cashOutLabel.Text = string.format(
		"Cash Out\n" ..
			'<font color="#FFDD55"><b>Take $%s now</b></font>',
		tostring(bank))

	-- Slide in from slightly below
	decisionFrame.Position = UDim2.new(
		decisionOrigPos.X.Scale, decisionOrigPos.X.Offset,
		decisionOrigPos.Y.Scale + 0.07, decisionOrigPos.Y.Offset)
	decisionFrame.Visible = true
	TweenService:Create(decisionFrame,
		TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = decisionOrigPos }):Play()

	-- Cinematic pull-back while the player decides
	task.spawn(function()
		local char = player.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		camera.CameraType = Enum.CameraType.Scriptable
		local fwd     = hrp.CFrame.LookVector
		local eyePos  = hrp.Position + Vector3.new(0, 2.0, 0) - fwd * 4.5
		local lookAt  = hrp.Position + Vector3.new(0, 0.7, 0)
		camera.CFrame = CFrame.lookAt(eyePos, lookAt)
		-- Slow upward drift for a cinematic feel
		TweenService:Create(camera,
			TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ CFrame = CFrame.lookAt(eyePos + Vector3.new(0, 0.55, 0), lookAt) }):Play()
	end)

	-- Shared decision handler
	local function makeDecision(decision)
		if not decisionFrame.Visible then return end
		hideKeepGoingAnimated()
		-- Restore camera smoothly back to 3P
		if camera.CameraType == Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Custom
			local hrp2 = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp2 then camera.CameraSubject = hrp2 end
		end
		Network.send("Cases_KeepGoingDecision", decision)
	end

	table.insert(keepGoingConns, keepGoingBtn.MouseButton1Click:Connect(function()
		makeDecision("keepgoing")
	end))
	table.insert(keepGoingConns, cashOutBtn.MouseButton1Click:Connect(function()
		makeDecision("cashout")
	end))
end)

Network.onClient("Cases_HideKeepGoing", function()
	hideKeepGoing()
end)

-- ── Monetization / PlayAI ────────────────────────────────────────────────────

Network.onClient("Cases_ShowMonetization", function() monetizationFrame.Visible = true end)
Network.onClient("Cases_ShowPlayAI", function() waitText.Visible = true; playAIBtn.Visible = true end)
Network.onClient("Cases_HidePlayAI", function() waitText.Visible = false; playAIBtn.Visible = false end)

playAIBtn.MouseButton1Click:Connect(function()
	if not playAIBtn.Visible then return end
	waitText.Visible = false; playAIBtn.Visible = false
	-- Old game fired Cases_RequestPlayAI (teleport to AI cases table).
	-- New flow: the player is already seated at a timer-duel table when this
	-- button shows, so just kick off the AI timer duel for that seat.
	Network.send("RequestAIDuel")
end)

Network.onClient("Cases_ShowLuckCombine", function() end)

-- ── Sound ─────────────────────────────────────────────────────────────────────

Network.onClient("Cases_PlaySound", function(soundId, looped)
	if looped and activeSounds[soundId] then return end
	local snd = Instance.new("Sound")
	snd.SoundId = "rbxassetid://" .. soundId; snd.Looped = looped == true
	snd.Volume = 0.85; snd.RollOffMaxDistance = 9999; snd.Parent = workspace; snd:Play()
	if looped then activeSounds[soundId] = snd
	else game:GetService("Debris"):AddItem(snd, 10) end
end)

Network.onClient("Cases_StopSound", function(soundId)
	local snd = activeSounds[soundId]
	if snd then snd:Stop(); snd:Destroy(); activeSounds[soundId] = nil end
end)

-- ── Camera handlers ───────────────────────────────────────────────────────────

Network.onClient("Cases_CamWatchDrop", function(midPos)
	tweenCam(CFrame.lookAt(Vector3.new(midPos.X, midPos.Y+1.8, midPos.Z+10.5),
		Vector3.new(midPos.X, midPos.Y+32, midPos.Z-2)), 0.7)
end)

Network.onClient("Cases_CamTrackLand", function(midPos, tweenTime)
	if not (tweenTime and tweenTime > 0) then return end
	tweenCam(CFrame.lookAt(Vector3.new(midPos.X, midPos.Y+1.8, midPos.Z+10.5),
		Vector3.new(midPos.X, midPos.Y+1.0, midPos.Z-0.5)), tweenTime,
		Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
end)

Network.onClient("Cases_LandImpact", function(midPos, soundId, timeUntilImpact)
	task.delay(math.max(0, timeUntilImpact or 0), function()
		local snd = Instance.new("Sound")
		snd.SoundId = "rbxassetid://" .. soundId; snd.Volume = 0.9
		snd.RollOffMaxDistance = 9999; snd.Parent = workspace; snd:Play()
		game:GetService("Debris"):AddItem(snd, 8)
		tweenCam(CFrame.lookAt(Vector3.new(midPos.X, midPos.Y+1.8, midPos.Z+10.5),
			Vector3.new(midPos.X, midPos.Y+0.8, midPos.Z-0.5)), 0.3)
		screenShake(0.55, 0.65)
	end)
end)

Network.onClient("Cases_CamToTableCam", function(cf)
	if cf then currentTableCamCF = cf end
	local useCF = currentTableCamCF or getTableCamCF()
	if useCF then tweenCam(useCF, 0.7) end
end)

Network.onClient("Cases_CamToCase", function(caseName, t)
	local m = workspace:FindFirstChild(caseName); if not m then return end
	local cp = m:FindFirstChild("Cam", true); if not cp then return end
	tweenCam(cp.CFrame, t or 1.0)
end)

Network.onClient("Cases_CamToPos", function(cf, t) tweenCam(cf, t or 1.0) end)

Network.onClient("Cases_CamToNormal", function(t)
	local cf = getTableCamCF()
	if cf then tweenCam(cf, t or 1.0).Completed:Wait() end
	restore3P()
end)

Network.onClient("Cases_TpToTable", function()
	-- Clear all game UI
	monetizationFrame.Visible = false
	earnedMoneyLabel.Visible  = false
	bankPopScale.Scale        = 1
	hideKeepGoing()
	stopTimer()

	local cf = currentTableCamCF
	currentTableCamCF = nil
	if not cf then cf = getTableCamCF() end
	if not cf then restore3P(); return end

	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then hrp.CFrame = CFrame.new(cf.Position) + Vector3.new(0, 3, 0) end
	restore3P()
end)

Network.onClient("Cases_CamDirect3P", function() restore3P() end)

Network.onClient("Cases_CamWatchPresenter", function(presenterUserId)
	task.spawn(function()
		local char = player.Character; if not char then return end
		local hrp  = char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
		local eyePos  = hrp.Position + Vector3.new(0, 2.5, 0) - hrp.CFrame.LookVector * 5
		local lookPos = eyePos + hrp.CFrame.LookVector * 10
		for _, p in ipairs(Players:GetPlayers()) do
			if p.UserId == presenterUserId and p.Character then
				local pHrp = p.Character:FindFirstChild("HumanoidRootPart")
				if pHrp then lookPos = pHrp.Position + Vector3.new(0, 1, 0) end
				break
			end
		end
		tweenCam(CFrame.lookAt(eyePos, lookPos), 0.5)
	end)
end)

local function goFirstPerson()
	local char = player.Character; if not char then return end
	local hrp  = char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
	local eyePos = hrp.Position + Vector3.new(0, 1.5, 0) + hrp.CFrame.LookVector * 0.6
	tweenCam(CFrame.lookAt(eyePos, eyePos + hrp.CFrame.LookVector * 10), 0.5)
end

Network.onClient("Cases_CamFirstPerson", function() goFirstPerson() end)

-- ── Presenter pick panel ──────────────────────────────────────────────────────

local pickConns = {}
local function hidePick()
	clearHighlight(); convinceFrame.Visible = false
	for _, c in ipairs(pickConns) do c:Disconnect() end; pickConns = {}
end
Network.onClient("Cases_HidePick", function() hidePick() end)

Network.onClient("Cases_ShowPick", function()
	for _, c in ipairs(pickConns) do c:Disconnect() end; pickConns = {}; clearHighlight()
	case1TopText.Text = "Case 1 has Cash"; case1BottomText.Text = "Case 1 is Empty"
	case2TopText.Text = "Case 2 has Cash"; case2BottomText.Text = "Case 2 is Empty"

	local function picked(decl, claimedGoodSide)
		hidePick(); Network.send("Cases_PickChose", decl, claimedGoodSide)
	end

	table.insert(pickConns, case1TopBtn.MouseButton1Click:Connect(function()    picked("Case 1 Has Cash", "Left")  end))
	table.insert(pickConns, case2TopBtn.MouseButton1Click:Connect(function()    picked("Case 2 Has Cash", "Right") end))
	table.insert(pickConns, case1BottomBtn.MouseButton1Click:Connect(function() picked("Case 1 Is Empty", "Right") end))
	table.insert(pickConns, case2BottomBtn.MouseButton1Click:Connect(function() picked("Case 2 Is Empty", "Left")  end))
	table.insert(pickConns, case1TopBtn.MouseEnter:Connect(function()    setHighlight("BriefcaseLeft")  end))
	table.insert(pickConns, case1TopBtn.MouseLeave:Connect(function()    clearHighlight() end))
	table.insert(pickConns, case1BottomBtn.MouseEnter:Connect(function() setHighlight("BriefcaseLeft")  end))
	table.insert(pickConns, case1BottomBtn.MouseLeave:Connect(function() clearHighlight() end))
	table.insert(pickConns, case2TopBtn.MouseEnter:Connect(function()    setHighlight("BriefcaseRight") end))
	table.insert(pickConns, case2TopBtn.MouseLeave:Connect(function()    clearHighlight() end))
	table.insert(pickConns, case2BottomBtn.MouseEnter:Connect(function() setHighlight("BriefcaseRight") end))
	table.insert(pickConns, case2BottomBtn.MouseLeave:Connect(function() clearHighlight() end))
	convinceFrame.Visible = true
end)

-- ── Guesser pick panel ────────────────────────────────────────────────────────

local guessConns = {}
Network.onClient("Cases_ShowChoose", function()
	for _, c in ipairs(guessConns) do c:Disconnect() end; guessConns = {}; clearHighlight()
	local function chose(num)
		clearHighlight(); guessFrame.Visible = false
		for _, c in ipairs(guessConns) do c:Disconnect() end; guessConns = {}
		Network.send("Cases_Chose", num)
	end
	table.insert(guessConns, case1Button.MouseButton1Click:Connect(function() chose("1") end))
	table.insert(guessConns, case2Button.MouseButton1Click:Connect(function() chose("2") end))
	table.insert(guessConns, case1Button.MouseEnter:Connect(function() setHighlight("BriefcaseLeft")  end))
	table.insert(guessConns, case1Button.MouseLeave:Connect(function() clearHighlight() end))
	table.insert(guessConns, case2Button.MouseEnter:Connect(function() setHighlight("BriefcaseRight") end))
	table.insert(guessConns, case2Button.MouseLeave:Connect(function() clearHighlight() end))
	guessFrame.Visible = true
end)

Network.onClient("Cases_HideChoose", function()
	clearHighlight(); guessFrame.Visible = false
	for _, c in ipairs(guessConns) do c:Disconnect() end; guessConns = {}
end)

-- ── Case animations ───────────────────────────────────────────────────────────

local OPEN_ANIM_ID = "rbxassetid://90064464387376"
local openTracks   = {}

Network.onClient("Cases_OpenAndFreeze", function(caseName)
	if openTracks[caseName] then pcall(function() openTracks[caseName]:Stop(0) end); openTracks[caseName] = nil end
	local caseModel = workspace:FindFirstChild(caseName)
	if not caseModel then task.wait(0.5); caseModel = workspace:FindFirstChild(caseName) end
	if not caseModel then return end
	local animator = caseModel:FindFirstChildWhichIsA("Animator", true); if not animator then return end
	local anim = Instance.new("Animation"); anim.AnimationId = OPEN_ANIM_ID
	local track = animator:LoadAnimation(anim)
	track.Priority = Enum.AnimationPriority.Action4; track.Looped = true; track:Play(0)
	local w = 0
	while track.Length == 0 and w < 3 do task.wait(0.05); w += 0.05 end
	local len = track.Length
	task.wait(math.max(len - 0.05, 0.05))
	track:AdjustSpeed(0); track.TimePosition = len - 0.01
	openTracks[caseName] = track
end)

Network.onClient("Cases_CloseAll", function()
	local cf = getTableCamCF(); if cf then tweenCam(cf, 0.5) end
	for caseName, track in pairs(openTracks) do
		if track and track.IsPlaying then track:AdjustSpeed(1); track:Stop(0.2) end
		openTracks[caseName] = nil
	end
end)

-- ── OP Roll buttons ───────────────────────────────────────────────────────────

local opRollBtn    = mainUI:WaitForChild("OPRoll")
local superRollBtn = mainUI:WaitForChild("SuperOPRoll")
local luckRolls    = mainUI:WaitForChild("LuckRolls")
local opRollLabel  = luckRolls:WaitForChild("OPRoll")
local superRollLbl = luckRolls:WaitForChild("SuperOPRoll")
local boughtLabel  = mainUI:WaitForChild("Bought")
local MPS_OP       = game:GetService("MarketplaceService")
local DevProductsOP = require(RS:WaitForChild("Modules"):WaitForChild("DevProducts"))

opRollBtn.Visible = false; superRollBtn.Visible = false
opRollLabel.Visible = false; superRollLbl.Visible = false; boughtLabel.Visible = false

Network.onClient("OPRolls_ShowButtons", function() opRollBtn.Visible = true; superRollBtn.Visible = true end)
Network.onClient("OPRolls_HideButtons", function() opRollBtn.Visible = false; superRollBtn.Visible = false end)

Network.onClient("OPRolls_Update", function(opCount, superCount)
	opCount = opCount or 0; superCount = superCount or 0
	opRollLabel.Text    = "OP Rolls: " .. opCount;       opRollLabel.Visible  = opCount > 0
	superRollLbl.Text   = "Super OP Rolls: " .. superCount; superRollLbl.Visible = superCount > 0
end)

Network.onClient("OPRolls_Bought", function(text, r, g, b)
	boughtLabel.Text = text; boughtLabel.TextColor3 = Color3.fromRGB(r, g, b)
	boughtLabel.TextTransparency = 0; boughtLabel.Visible = true
	local stroke = boughtLabel:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Transparency = 0 end
	TweenService:Create(boughtLabel, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 2.8),
		{ TextTransparency = 1 }):Play()
	if stroke then TweenService:Create(stroke, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 2.8), { Transparency = 1 }):Play() end
	task.delay(3.6, function() boughtLabel.Visible = false end)
end)

opRollBtn.MouseButton1Click:Connect(function() MPS_OP:PromptProductPurchase(player, DevProductsOP["OPRoll"].ID) end)
superRollBtn.MouseButton1Click:Connect(function() MPS_OP:PromptProductPurchase(player, DevProductsOP["SuperOPRoll"].ID) end)

-- ── Revenge button ────────────────────────────────────────────────────────────

local revengeBtn       = mainUI:WaitForChild("Revenge")
local revengeCountdown = revengeBtn:WaitForChild("Countdown")
local revengeThread    = nil
local revengeActive    = false
local refreshQuickPlay
local MPS         = game:GetService("MarketplaceService")
local DevProducts = require(RS:WaitForChild("Modules"):WaitForChild("DevProducts"))

local function hideRevenge()
	if revengeThread then pcall(task.cancel, revengeThread); revengeThread = nil end
	revengeActive = false; revengeBtn.Visible = false
	if refreshQuickPlay then refreshQuickPlay() end
end

Network.onClient("ShowRevenge", function(canTroll)
	if revengeThread then pcall(task.cancel, revengeThread); revengeThread = nil end
	revengeActive = true; revengeBtn.Visible = true
	-- Hide the Troll button when there's no human winner to jumpscare (AI win).
	local tb = revengeBtn:FindFirstChild("Troll")
	if tb then tb.Visible = (canTroll ~= false) end
	local remaining = 10; revengeCountdown.Text = remaining .. "s"
	revengeThread = task.spawn(function()
		while remaining > 0 do task.wait(1); remaining -= 1; revengeCountdown.Text = remaining .. "s" end
		revengeThread = nil; revengeActive = false; revengeBtn.Visible = false
		if refreshQuickPlay then refreshQuickPlay() end
	end)
end)

revengeBtn.MouseButton1Click:Connect(function()
	if not revengeBtn.Visible then return end
	hideRevenge(); MPS:PromptProductPurchase(player, DevProducts["Revenge"].ID)
end)

local trollBtn = revengeBtn:WaitForChild("Troll")
trollBtn.MouseButton1Click:Connect(function()
	if not revengeBtn.Visible then return end
	MPS:PromptProductPurchase(player, DevProducts["Troll"].ID)
end)

-- ── Confetti ──────────────────────────────────────────────────────────────────

local CONFETTI_COLORS = {
	Color3.fromRGB(255,215,0), Color3.fromRGB(100,255,130), Color3.fromRGB(90,160,255),
	Color3.fromRGB(255,110,200), Color3.fromRGB(255,160,40), Color3.fromRGB(200,90,255),
	Color3.fromRGB(255,70,70), Color3.fromRGB(70,230,230),
}

local function spawnConfetti()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ConfettiGui"; gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = true; gui.Parent = player.PlayerGui
	for _ = 1, 90 do
		task.spawn(function()
			task.wait(math.random() * 2.0)
			if not gui or not gui.Parent then return end
			local piece = Instance.new("Frame")
			piece.Size = UDim2.new(0, math.random(8,20), 0, math.random(6,14))
			piece.Position = UDim2.new(math.random(), 0, -0.06, 0)
			piece.BackgroundColor3 = CONFETTI_COLORS[math.random(#CONFETTI_COLORS)]
			piece.BorderSizePixel = 0; piece.Rotation = math.random(0,360); piece.ZIndex = 60; piece.Parent = gui
			if math.random() > 0.4 then local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0.3,0); c.Parent = piece end
			local drift = (math.random()-0.5)*0.38; local fall = 2.1+math.random()*1.6
			TweenService:Create(piece, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = UDim2.new(piece.Position.X.Scale+drift,0,1.18,0), Rotation = piece.Rotation+math.random(-720,720) }):Play()
			task.delay(fall*0.58, function() if piece and piece.Parent then TweenService:Create(piece, TweenInfo.new(fall*0.44, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {BackgroundTransparency=1}):Play() end end)
			task.delay(fall+0.1, function() if piece and piece.Parent then piece:Destroy() end end)
		end)
	end
	task.delay(6, function() if gui and gui.Parent then gui:Destroy() end end)
end

Network.onClient("Cases_Confetti", function() spawnConfetti() end)

-- ── QuickPlay ─────────────────────────────────────────────────────────────────

local quickPlayBtn = gameplayUI:WaitForChild("QuickPlay")

-- RiskMode: while seated at a RiskMode table, the Quick Play button becomes a
-- "Start" button that launches the solo risk game, then reverts afterward.
local riskStartGroup = nil
local riskInProgress = false

-- Snapshot the button's authored on-screen slot once, so when we re-show it we
-- can also restore its position. TimerDuelCinematics parks the button off-screen
-- (by position) during a duel; without restoring here, a re-shown button could
-- be Visible=true yet still sitting off-screen.
local quickPlayHomePos = quickPlayBtn.Position

local function setQuickPlayText(t)
	local lbl = quickPlayBtn:FindFirstChild("Speed")
	if lbl and lbl:IsA("TextLabel") then lbl.Text = t end
end

local function getSeatedRiskGroup()
	local char = player.Character
	local hum  = char and char:FindFirstChild("Humanoid")
	local seat = hum and hum.SeatPart
	if not seat or seat.Name ~= "Seat1" then return nil end
	local map = workspace:FindFirstChild("Map")
	local riskFolder = map and map:FindFirstChild("RiskMode")
	local group = seat.Parent
	if riskFolder and group and group.Parent == riskFolder then return group end
	return nil
end

local function showQuickPlay()
	-- Make sure a re-shown button is in its on-screen slot (the duel script may
	-- have parked it off-screen by position).
	quickPlayBtn.Position = quickPlayHomePos
	quickPlayBtn.Visible  = not revengeActive
end

refreshQuickPlay = function()
	-- Never show the button while a game is running — the duel script owns the
	-- screen for the whole match. The InDuel-clear listener below re-evaluates
	-- the instant the game ends.
	if player:GetAttribute("InDuel") then
		quickPlayBtn.Visible = false
		return
	end
	local char = player.Character; local hum = char and char:FindFirstChild("Humanoid")
	local sitting = hum and hum.Sit
	if not sitting then
		riskInProgress = false
		riskStartGroup = nil
		setQuickPlayText("Quick Play")
		showQuickPlay()
		return
	end
	if riskInProgress then
		quickPlayBtn.Visible = false
		return
	end
	local rg = getSeatedRiskGroup()
	if rg then
		riskStartGroup = rg
		setQuickPlayText("Start")
		showQuickPlay()
	else
		riskStartGroup = nil
		setQuickPlayText("Quick Play")
		quickPlayBtn.Visible = false
	end
end

local function connectQuickPlayChar(char)
	local hum = char:WaitForChild("Humanoid")
	hum:GetPropertyChangedSignal("Sit"):Connect(refreshQuickPlay)
end

player.CharacterAdded:Connect(function(char) connectQuickPlayChar(char); refreshQuickPlay() end)
if player.Character then connectQuickPlayChar(player.Character) end
refreshQuickPlay()

-- TimerDuelCinematics sets/clears the "InDuel" attribute around each game. When
-- it clears (game ended), re-evaluate the button so it follows the seated rule
-- (hidden while seated) rather than being force-shown by the duel script.
player:GetAttributeChangedSignal("InDuel"):Connect(function()
	task.wait(0.1)  -- let the server's eject settle the Sit state first
	refreshQuickPlay()
end)

quickPlayBtn.MouseButton1Click:Connect(function()
	if not quickPlayBtn.Visible then return end
	if riskStartGroup and not riskInProgress then
		riskInProgress = true
		quickPlayBtn.Visible = false       -- the game takes over from here
		Network.send("RiskStart")
	else
		Network.send("QuickPlay_Request")
	end
end)

Network.onClient("QuickPlay_Failed", function() end)