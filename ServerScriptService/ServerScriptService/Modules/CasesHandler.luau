	local module = {}
	module.onGameEnd = nil

	local RS           = game:GetService("ReplicatedStorage")
	local TweenService = game:GetService("TweenService")
	local Players      = game:GetService("Players")
	local Network      = require(RS.Modules.Network)
	local ChairInfo    = require(RS.Modules.ChairInfo)
	local CashConfig   = require(RS.Modules.CashConfig)

	local DataHandler
	local AIHandler

	local OPEN_ANIM  = "rbxassetid://90064464387376"
	local SPAWN_Y    = 0.265
	local DROP_H     = 35
	local DROP_TIME  = 2.4

	local SND_FALLING   = "140065475003739"
	local SND_LAND      = "9117451558"
	local SND_DRUMROLL  = "4398694764"
	local SND_POOF      = "107424340854522"
	local SND_OPEN      = "108106344071650"
	local SND_CASE_OPEN = "9114619627"
	local SND_WIN       = "108165586294729"
	local SND_LOSE      = "104387441091303"

	local FLAT          = CFrame.Angles(0, 0, math.pi/2)
	local ROT_FACENEG_X = CFrame.Angles(0, -math.pi/2, 0) * FLAT
	local ROT_FACEPOS_X = CFrame.Angles(0,  math.pi/2, 0) * FLAT

	local BILLBOARD_MAX_DISTANCE = 25
	local MAX_ROUNDS             = 100
	local KEEP_GOING_TIMER       = 20

	local ChairsFolder = RS:WaitForChild("Assets"):WaitForChild("Chairs")

	local PRESENTER_PICKS = {
		{ decl = "Case 1 Has Cash", side = "Left"  },
		{ decl = "Case 2 Has Cash", side = "Right" },
		{ decl = "Case 1 Is Empty", side = "Right" },
		{ decl = "Case 2 Is Empty", side = "Left"  },
	}

	-- ── Seat display ──────────────────────────────────────────────────────────────

	local function getDisplayForSeat(seat)
		local closest, closestDist = nil, math.huge
		for _, child in ipairs(seat.Parent:GetChildren()) do
			if child.Name == "Display" and child:IsA("Model") then
				local bp = child:FindFirstChildWhichIsA("BasePart")
				if bp then
					local d = (bp.Position - seat.Position).Magnitude
					if d < closestDist then closestDist = d; closest = child end
				end
			end
		end
		return closest
	end

	local function hideDisplay(seat)
		local display = getDisplayForSeat(seat)
		if not display then return end
		for _, part in ipairs(display:GetDescendants()) do
			if part:IsA("BasePart") then part.Transparency = 1 end
		end
	end

	local function showDisplay(seat)
		local display = getDisplayForSeat(seat)
		if not display then return end
		for _, part in ipairs(display:GetDescendants()) do
			if part:IsA("BasePart") then part.Transparency = 0 end
		end
	end

	-- ── Chair helpers ─────────────────────────────────────────────────────────────

	local function applyChairToSeat(player, seat, overrideCF)
		if not seat then return nil end
		local p = seat.Position
		local seatTag = string.format("SEAT_%.3f_%.3f_%.3f", p.X, p.Y, p.Z)
		for _, obj in ipairs(workspace:GetChildren()) do
			if obj.Name == "ChairModel" and obj:GetAttribute("SeatTag") == seatTag then obj:Destroy() end
		end
		showDisplay(seat)
		local equippedVal = player:FindFirstChild("EquippedChair") or player:WaitForChild("EquippedChair", 5)
		if not equippedVal then return nil end
		local chairName = equippedVal.Value
		if chairName == "Basic" then return nil end
		local modelTemplate = ChairsFolder:FindFirstChild(chairName)
		if not modelTemplate then return nil end
		local result
		local ok, err = pcall(function()
			local clone    = modelTemplate:Clone(); clone.Name = "ChairModel"
			local chairbase = clone:FindFirstChild("Chairbase")
			local basePart  = (chairbase and chairbase:FindFirstChild("Base")) or clone:FindFirstChildWhichIsA("BasePart")
			local relOffsets = {}
			if basePart then
				local inv = basePart.CFrame:Inverse()
				for _, part in ipairs(clone:GetDescendants()) do
					if part:IsA("BasePart") then relOffsets[part] = inv * part.CFrame end
				end
				relOffsets[basePart] = CFrame.new()
			end
			for _, part in ipairs(clone:GetDescendants()) do
				if part:IsA("BasePart") then part.Anchored = true end
			end

			-- Koppel de juiste rotatie aan de juiste stoel om de bug te fixen
			local targetCF
			if chairName == "Basic" then
				targetCF = (overrideCF or seat.CFrame) * CFrame.Angles(0, math.rad(180), 0)
			else
				targetCF = (overrideCF or seat.CFrame) * CFrame.Angles(0, math.rad(0), 0)
			end

			if basePart then
				for part, rel in pairs(relOffsets) do
					part.CFrame = targetCF * rel
				end
			else
				clone:PivotTo(targetCF)
			end

			clone.Parent = workspace
			clone:SetAttribute("SeatTag", seatTag)
			result = clone
		end)
		if not ok then warn("[CHAIR] Error applying chair for", player.Name, ":", err) end
		return result
	end

	local function destroyChair(chairModel, seat)
		if chairModel and chairModel.Parent then chairModel:Destroy() end
		if seat then showDisplay(seat) end
	end

	-- ── Network defines ───────────────────────────────────────────────────────────

	Network.define("Cases_CamToCase")
	Network.define("Cases_CamToNormal")
	Network.define("Cases_CamToTableCam")
	Network.define("Cases_ShowPick")
	Network.define("Cases_HidePick")
	Network.define("Cases_PickChose")
	Network.define("Cases_ShowChoose")
	Network.define("Cases_HideChoose")
	Network.define("Cases_Chose")
	Network.define("Cases_PlaySound")
	Network.define("Cases_StopSound")
	Network.define("Cases_CamWatchDrop")
	Network.define("Cases_CamTrackLand")
	Network.define("Cases_LandImpact")
	Network.define("Cases_CamDirect3P")
	Network.define("Cases_CamFirstPerson")
	Network.define("Cases_CamWatchPresenter")
	Network.define("Cases_OpenAndFreeze")
	Network.define("Cases_CloseAll")
	Network.define("Cases_TpToTable")
	Network.define("Cases_StartTimer")
	Network.define("Cases_StopTimer")
	Network.define("Cases_ShowLuckCombine")
	Network.define("Cases_ShowMonetization")
	Network.define("Cases_ShowPlayAI")
	Network.define("Cases_HidePlayAI")
	Network.define("Cases_RequestPlayAI")
	Network.define("Cases_ShowResult")
	Network.define("Cases_HideUI")
	Network.define("Cases_ShowUI")
	Network.define("Cases_ShowKeepGoing")
	Network.define("Cases_HideKeepGoing")
	Network.define("Cases_KeepGoingDecision")
	Network.define("Cases_UpdateBank")
	Network.define("Cases_ShowRound")
	Network.define("Jumpscare")
	Network.define("StealPrompt_MatchStart")
	Network.define("StealPrompt_MatchEnd")
	Network.define("QuickPlay_Request")
	Network.define("QuickPlay_Failed")

	local activeSessions = {}
	local BASE_JUMP_POWER = 50

	-- ── Seat lock ─────────────────────────────────────────────────────────────────

	local function lockPlayerInSeat(player)
		local char = player.Character
		local hum  = char and char:FindFirstChildOfClass("Humanoid")
		if hum then hum.JumpPower = 0; hum.JumpHeight = 0 end
	end

	local function unlockPlayerFromSeat(player)
		local char = player.Character
		local hum  = char and char:FindFirstChildOfClass("Humanoid")
		if hum then hum.JumpPower = BASE_JUMP_POWER; hum.JumpHeight = 7.2 end
	end

	-- ── Helpers ───────────────────────────────────────────────────────────────────

	function module.GetOpponent(player)
		local session = activeSessions[player.UserId]
		if not session then return nil end
		return player == session.presenter and session.guesser or session.presenter
	end

	function module.GetAIOpponentTruthRate(player)
		if AIHandler then return AIHandler.GetSessionTruthRate(player) end
		return nil
	end

	local function sendBoth(session, remote, ...)
		Network.sendToClient(session.presenter, remote, ...)
		Network.sendToClient(session.guesser,   remote, ...)
	end

	local function updateCam(hrp, cam)
		if not cam then return end
		local camPos = hrp.Position + Vector3.new(0, 2.8, 0) - hrp.CFrame.LookVector * 0.6
		cam.CFrame = CFrame.lookAt(camPos, hrp.Position + Vector3.new(0, 0.1, 0), Vector3.new(0, 1, 0))
	end

	local function prepareCase(model)
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CanCollide = false
				p.Anchored   = (p.Name == "HumanoidRootPart" or p.Name == "Cam")
			end
		end
		model.PrimaryPart = model.HumanoidRootPart
	end

	local function billboard(player, text, color)
		local char = player.Character; if not char then return end
		local head = char:FindFirstChild("Head"); if not head then return end
		local old  = head:FindFirstChild("CasePick"); if old then old:Destroy() end
		local bb   = Instance.new("BillboardGui")
		bb.Name = "CasePick"; bb.Size = UDim2.new(0, 240, 0, 60)
		bb.StudsOffset = Vector3.new(0, 3.5, 0); bb.AlwaysOnTop = true
		bb.MaxDistance = BILLBOARD_MAX_DISTANCE; bb.Parent = head
		local lbl = Instance.new("TextLabel", bb)
		lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1
		lbl.TextColor3 = color; lbl.TextScaled = true
		lbl.Font = Enum.Font.GothamBold; lbl.Text = text
		Instance.new("UIStroke", lbl).Thickness = 2
	end

	local function clearBillboard(player)
		if not player.Character then return end
		local head = player.Character:FindFirstChild("Head")
		if head then local b = head:FindFirstChild("CasePick"); if b then b:Destroy() end end
	end

	local function setCaseNumber(caseModel, number)
		local lid = caseModel:FindFirstChild("Lid", true); if not lid then return end
		for _, guiName in ipairs({"CaseGui", "InsideCaseGui"}) do
			local gui = lid:FindFirstChild(guiName)
			if gui then local label = gui:FindFirstChild("CaseNumber"); if label then label.Text = tostring(number) end end
		end
	end

	local function spawnInSky(template, finalCF)
		local m = template:Clone(); prepareCase(m)
		m:PivotTo(finalCF + Vector3.new(0, DROP_H, 0)); m.Parent = workspace; return m
	end

	local function dropCase(caseModel, finalCF)
		local hrp = caseModel.HumanoidRootPart
		local cam = caseModel:FindFirstChild("Cam")
		local tw = TweenService:Create(hrp,
			TweenInfo.new(DROP_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { CFrame = finalCF })
		tw:Play(); tw.Completed:Wait(); updateCam(hrp, cam)
	end

	local function shakeCase(caseModel, duration)
		local hrp = caseModel.HumanoidRootPart; local cam = caseModel:FindFirstChild("Cam")
		local origHRPCF = hrp.CFrame; local deadline = tick() + duration; local step = 0
		while tick() < deadline do
			local progress  = 1 - ((deadline - tick()) / duration)
			local intensity = progress * progress * progress
			local side = math.sin(step * 1.9) * intensity * 0.5
			local up   = math.abs(math.sin(step * 3.7)) * intensity * 0.15
			TweenService:Create(hrp, TweenInfo.new(0.04, Enum.EasingStyle.Linear),
				{ CFrame = origHRPCF + Vector3.new(side, up, 0) }):Play()
			task.wait(0.04); step += 1
		end
		hrp.CFrame = origHRPCF; updateCam(hrp, cam)
	end

	local function toPhysical(choice)
		return choice == "1" and "Left" or "Right"
	end

	local function getPlayerLuck(player)
		local equippedVal = player:FindFirstChild("EquippedChair"); if not equippedVal then return 0 end
		local data = ChairInfo[equippedVal.Value]; return data and (data.Luck or 0) or 0
	end

	-- ── Centralised cleanup ───────────────────────────────────────────────────────

	local function cancelSessionTimers(session)
		if session.presenterTimerThread then task.cancel(session.presenterTimerThread); session.presenterTimerThread = nil end
		if session.guesserTimerThread   then task.cancel(session.guesserTimerThread);   session.guesserTimerThread   = nil end
		if session.keepGoingThread      then task.cancel(session.keepGoingThread);      session.keepGoingThread       = nil end
	end

	local function cleanupSession(session)
		unlockPlayerFromSeat(session.presenter)
		unlockPlayerFromSeat(session.guesser)
		if activeSessions[session.presenter.UserId] == session then activeSessions[session.presenter.UserId] = nil end
		if activeSessions[session.guesser.UserId]   == session then activeSessions[session.guesser.UserId]   = nil end
		cancelSessionTimers(session)
		sendBoth(session, "Cases_HideKeepGoing")
		destroyChair(session.presenterChair, session.presenterSeat); session.presenterChair = nil
		destroyChair(session.guesserChair,   session.guesserSeat);   session.guesserChair   = nil
		if session.leftCase  and session.leftCase.Parent  then session.leftCase:Destroy()  end
		if session.rightCase and session.rightCase.Parent then session.rightCase:Destroy() end
		if session.cashModel and session.cashModel.Parent then session.cashModel:Destroy() end
		Network.sendToClient(session.presenter, "OPRolls_HideButtons")
		Network.sendToClient(session.guesser,   "OPRolls_HideButtons")
		if DataHandler then
			DataHandler.ClearSessionRolls(session.presenter.UserId)
			DataHandler.ClearSessionRolls(session.guesser.UserId)
		end
	end

	-- ── End-of-game sequence ──────────────────────────────────────────────────────

	local function doEndSequence(session, guesserWins, cashAmount)
		if session.stage == "done" then return end
		session.stage = "done"

		cancelSessionTimers(session)
		sendBoth(session, "Cases_StopTimer")
		sendBoth(session, "Cases_HideKeepGoing")
		Network.sendToClient(session.guesser, "Cases_UpdateBank", 0)

		local winner = guesserWins and session.guesser or session.presenter
		local loser  = guesserWins and session.presenter or session.guesser

		local loserStreak = DataHandler
			and DataHandler.GetProfile(loser)
			and (DataHandler.GetProfile(loser).Data.Streak or 0) or 0

		if DataHandler then
			if cashAmount > 0 then
				DataHandler.AddCurrencyRaw(winner, cashAmount, "Cash")
			end
			DataHandler.AddCurrency(winner, 1, "Streak")
			DataHandler.AddCurrency(winner, 1, "Wins")
			DataHandler.SetCurrency(loser, 0, "Streak")
			DataHandler.SetRevengePending(loser.UserId, {
				winnerUserId = winner.UserId,
				cash         = cashAmount,
				loserStreak  = loserStreak,
			})
		end
		Network.sendToClient(loser, "ShowRevenge")

		sendBoth(session, "Cases_ShowUI")
		Network.sendToClient(session.guesser,   "Cases_ShowResult", "guesser",   guesserWins)
		Network.sendToClient(session.presenter, "Cases_ShowResult", "presenter", not guesserWins)

		if guesserWins then
			Network.sendToClient(session.guesser,   "Cases_PlaySound", SND_WIN,  false)
			Network.sendToClient(session.presenter, "Cases_PlaySound", SND_LOSE, false)
			billboard(session.guesser,   "YOU WIN!", Color3.fromRGB(80, 255, 120))
			task.wait(0.05)
			billboard(session.presenter, "You Lose", Color3.fromRGB(255, 80, 80))
			Network.sendToClient(session.guesser, "Cases_Confetti")
		else
			Network.sendToClient(session.guesser,   "Cases_PlaySound", SND_LOSE, false)
			Network.sendToClient(session.presenter, "Cases_PlaySound", SND_WIN,  false)
			billboard(session.guesser,   "You Lose", Color3.fromRGB(255, 80, 80))
			task.wait(0.05)
			billboard(session.presenter, "YOU WIN!", Color3.fromRGB(80, 255, 120))
			Network.sendToClient(session.presenter, "Cases_Confetti")
		end

		task.delay(1.5, function()
			unlockPlayerFromSeat(session.presenter)
			unlockPlayerFromSeat(session.guesser)
			for _, entry in ipairs({
				{p=session.presenter, seat=session.presenterSeat},
				{p=session.guesser,   seat=session.guesserSeat},
				}) do
				local char = entry.p and entry.p.Character
				if char then
					local h = char:FindFirstChild("Humanoid")
					local hrp2 = char:FindFirstChild("HumanoidRootPart")
					if entry.seat then local sw = entry.seat:FindFirstChild("SeatWeld"); if sw then sw:Destroy() end end
					if hrp2 then for _, w in ipairs(hrp2:GetChildren()) do if w:IsA("Weld") and w.Name == "SeatWeld" then w:Destroy() end end end
					if h then h.Sit = false; h.Jump = true end
				end
				if entry.seat and entry.seat.Parent then entry.seat.Disabled = false end
			end
		end)

		task.delay(2, function() sendBoth(session, "Cases_TpToTable") end)

		task.delay(6, function()
			Network.sendToClient(session.presenter, "StealPrompt_MatchEnd")
			Network.sendToClient(session.guesser,   "StealPrompt_MatchEnd")
			clearBillboard(session.guesser)
			clearBillboard(session.presenter)
			cleanupSession(session)
			if module.onGameEnd then module.onGameEnd(session.presenter, session.guesser) end
		end)
	end

	-- ── Per-round drop + reveal ───────────────────────────────────────────────────

	local function doCaseDrop(session)
		sendBoth(session, "Cases_StopTimer")
		sendBoth(session, "Cases_CamWatchDrop", session.midPos)
		task.wait(0.85)

		local timeUntilLand = 0.15 + DROP_TIME
		sendBoth(session, "Cases_PlaySound",  SND_FALLING, true)
		sendBoth(session, "Cases_LandImpact", session.midPos, SND_LAND, timeUntilLand)
		task.spawn(function() dropCase(session.leftCase,  session.leftFinalCF) end)
		task.wait(0.15)
		task.spawn(function() dropCase(session.rightCase, session.rightFinalCF) end)
		task.wait(DROP_TIME * 0.52)
		sendBoth(session, "Cases_CamTrackLand", session.midPos, DROP_TIME * 0.48)
		task.wait(DROP_TIME * 0.48 + 0.15)
		sendBoth(session, "Cases_StopSound", SND_FALLING)
		task.wait(0.5)
	end

	local function spawnFreshCases(session)
		if session.leftCase  and session.leftCase.Parent  then session.leftCase:Destroy()  end
		if session.rightCase and session.rightCase.Parent then session.rightCase:Destroy() end

		session.leftIsGood = math.random() > 0.5
		local leftCase  = spawnInSky(session.leftIsGood      and RS.Cases.GoodCase or RS.Cases.BadCase, session.leftFinalCF)
		local rightCase = spawnInSky((not session.leftIsGood) and RS.Cases.GoodCase or RS.Cases.BadCase, session.rightFinalCF)
		leftCase.Name   = "BriefcaseLeft"  .. session.caseTag
		rightCase.Name  = "BriefcaseRight" .. session.caseTag
		setCaseNumber(leftCase, 1); setCaseNumber(rightCase, 2)
		session.leftCase  = leftCase
		session.rightCase = rightCase
	end

	local function startNextRound(session)
		cancelSessionTimers(session)
		spawnFreshCases(session)
		sendBoth(session, "Cases_ShowRound", session.round)
		task.wait(1.8)
		Network.sendToClient(session.guesser, "Cases_CamToTableCam", session.tableCamCF)
		doCaseDrop(session)
		module.PlayCaseReveal(session)
	end

	-- ── Public API ────────────────────────────────────────────────────────────────

	function module.SetDataHandler(h) DataHandler = h end
	function module.SetAIHandler(h)   AIHandler   = h end

	function module.SpawnCases(presenter, guesser, presenterSeat, guesserSeat, cashModel, presenterChairIn, guesserChairIn)
		local tg = presenterSeat.Parent
		local presenterFacesNegX = presenterSeat.CFrame.LookVector.X < 0
		local spawnName = presenterFacesNegX and "Spawns1" or "Spawns2"

		local camPart    = tg:FindFirstChild("CameraPart")
		local tableCamCF = camPart and camPart.CFrame

		local spawns = {}
		for _, v in ipairs(tg:GetChildren()) do if v.Name == spawnName then table.insert(spawns, v) end end
		if #spawns < 2 then warn("[Cases] Need 2 " .. spawnName) return nil end
		table.sort(spawns, function(a, b) return a.Position.Z > b.Position.Z end)

		local leftIdx    = presenterFacesNegX and 1 or 2
		local rightIdx   = presenterFacesNegX and 2 or 1
		local leftIsGood = math.random() > 0.5
		local guesserRot = presenterFacesNegX and ROT_FACEPOS_X or ROT_FACENEG_X

		local leftFinalCF  = CFrame.new(spawns[leftIdx].Position  + Vector3.new(0, SPAWN_Y, 0)) * guesserRot
		local rightFinalCF = CFrame.new(spawns[rightIdx].Position + Vector3.new(0, SPAWN_Y, 0)) * guesserRot
		local midPos       = (spawns[leftIdx].Position + spawns[rightIdx].Position) / 2

		local leftCase  = spawnInSky(leftIsGood      and RS.Cases.GoodCase or RS.Cases.BadCase, leftFinalCF)
		local rightCase = spawnInSky((not leftIsGood) and RS.Cases.GoodCase or RS.Cases.BadCase, rightFinalCF)
		local caseTag   = "_" .. presenter.UserId
		leftCase.Name   = "BriefcaseLeft"  .. caseTag
		rightCase.Name  = "BriefcaseRight" .. caseTag
		setCaseNumber(leftCase, 1); setCaseNumber(rightCase, 2)

		local presenterLuck = getPlayerLuck(presenter)
		local guesserLuck   = getPlayerLuck(guesser)
		local combinedLuck  = presenterLuck + guesserLuck

		local baseCash     = cashModel and CashConfig[cashModel.Name] and CashConfig[cashModel.Name].amount or 0
		local cashPerRound = baseCash   

		local cashValue = cashModel and cashModel:FindFirstChild("Value")
		if cashValue and cashValue:IsA("NumberValue") then
			cashValue.Value = cashPerRound
		end

		print("[CASES] Combined luck:", combinedLuck, "| Prize per round: $" .. cashPerRound)

		local session = {
			presenter            = presenter,       guesser              = guesser,
			leftCase             = leftCase,        rightCase            = rightCase,
			caseTag              = caseTag,
			leftIsGood           = leftIsGood,      stage                = "reveal",
			cashModel            = cashModel,
			tableCamCF           = tableCamCF,
			guesserRot           = guesserRot,
			presenterTruth       = nil,
			presenterSeat        = presenterSeat,   guesserSeat          = guesserSeat,
			presenterChair       = presenterChairIn, guesserChair        = guesserChairIn,
			presenterTimerThread = nil,              guesserTimerThread   = nil,
			round                = 1,
			bank                 = 0,
			cashPerRound         = cashPerRound,
			leftFinalCF          = leftFinalCF,     rightFinalCF         = rightFinalCF,
			midPos               = midPos,          keepGoingThread      = nil,
		}
		activeSessions[presenter.UserId] = session
		activeSessions[guesser.UserId]   = session

		lockPlayerInSeat(presenter); lockPlayerInSeat(guesser)
		sendBoth(session, "Cases_HidePlayAI")
		sendBoth(session, "Cases_HideUI")

		Network.sendToClient(session.presenter, "StealPrompt_MatchStart", session.guesser.UserId)
		Network.sendToClient(session.guesser,   "StealPrompt_MatchStart", session.presenter.UserId)
		sendBoth(session, "Cases_ShowMonetization")

		doCaseDrop(session)
		Network.sendToClient(guesser, "Cases_CamToTableCam", tableCamCF)
		return session
	end

	function module.PlayCaseReveal(session)
		task.wait(0.8)
		Network.sendToClient(session.guesser,   "Cases_CamToTableCam", session.tableCamCF)
		Network.sendToClient(session.presenter, "Cases_CamToCase", "BriefcaseLeft" .. session.caseTag, 1.0)
		task.wait(1.5)
		sendBoth(session, "Cases_OpenAndFreeze", "BriefcaseLeft" .. session.caseTag)
		sendBoth(session, "Cases_PlaySound", SND_CASE_OPEN, false)
		task.wait(0.5)
		Network.sendToClient(session.guesser,   "Cases_CamToTableCam", session.tableCamCF)
		Network.sendToClient(session.presenter, "Cases_CamToCase", "BriefcaseRight" .. session.caseTag, 1.0)
		task.wait(1.5)
		sendBoth(session, "Cases_OpenAndFreeze", "BriefcaseRight" .. session.caseTag)
		sendBoth(session, "Cases_PlaySound", SND_CASE_OPEN, false)
		task.wait(0.5)
		Network.sendToClient(session.presenter, "Cases_CamFirstPerson")
		Network.sendToClient(session.guesser,   "Cases_CamToTableCam", session.tableCamCF)
		task.wait(0.6)

		session.stage = "presenter_pick"
		Network.sendToClient(session.presenter, "Cases_ShowPick")
		sendBoth(session, "Cases_StopTimer")
		sendBoth(session, "Cases_StartTimer", 30)
		session.presenterTimerThread = task.delay(30, function()
			if session.stage ~= "presenter_pick" then return end
			session.presenterTimerThread = nil
			local p = PRESENTER_PICKS[math.random(1, #PRESENTER_PICKS)]
			module.HandlePickChose(session.presenter, p.decl, p.side)
		end)
	end

	function module.HandlePickChose(player, declaration, claimedGoodSide)
		local session = activeSessions[player.UserId]
		if not session or session.stage ~= "presenter_pick" or player ~= session.presenter then return end

		if session.presenterTimerThread then task.cancel(session.presenterTimerThread); session.presenterTimerThread = nil end
		sendBoth(session, "Cases_StopTimer")
		Network.sendToClient(session.presenter, "Cases_HidePick")

		session.stage = "guesser_pick"

		if claimedGoodSide == nil then
			session.presenterTruth = nil
		else
			local claimedLeftIsGood = (claimedGoodSide == "Left")
			session.presenterTruth  = (claimedLeftIsGood == session.leftIsGood)
			print("[TRUTHRATE]", player.Name, "| Declaration:", declaration, "| verdict:", session.presenterTruth and "TRUTH" or "LIE")
		end

		billboard(session.presenter, declaration, Color3.fromRGB(255, 210, 50))
		sendBoth(session, "Cases_CloseAll")
		Network.sendToClient(session.presenter, "Cases_CamDirect3P")
		task.wait(0.4)
		Network.sendToClient(session.guesser, "Cases_CamFirstPerson")
		Network.sendToClient(session.guesser, "Cases_ShowChoose")
		sendBoth(session, "Cases_StopTimer")
		sendBoth(session, "Cases_StartTimer", 30)
		session.guesserTimerThread = task.delay(30, function()
			if session.stage ~= "guesser_pick" then return end
			session.guesserTimerThread = nil
			local wrongChoice   = session.leftIsGood and "2" or "1"
			local correctChoice = session.leftIsGood and "1" or "2"
			module.HandleChose(session.guesser, math.random() < 0.65 and wrongChoice or correctChoice)
		end)
	end

	function module.HandleChose(player, choice)
		local session = activeSessions[player.UserId]
		if not session or session.stage ~= "guesser_pick" or player ~= session.guesser then return end

		if session.guesserTimerThread then task.cancel(session.guesserTimerThread); session.guesserTimerThread = nil end
		sendBoth(session, "Cases_StopTimer")
		session.stage = "resolving"
		Network.sendToClient(session.guesser, "Cases_HideChoose")

		local physicalChoice = toPhysical(choice)
		local guesserWins    = (physicalChoice == "Left") == session.leftIsGood
		local chosenCase     = physicalChoice == "Left" and session.leftCase or session.rightCase

		updateCam(chosenCase.HumanoidRootPart, chosenCase:FindFirstChild("Cam"))
		task.wait(0.15)
		sendBoth(session, "Cases_CamToCase", chosenCase.Name, 0.9)
		task.wait(1.0)
		sendBoth(session, "Cases_PlaySound", SND_DRUMROLL, false)
		shakeCase(chosenCase, 3.5)
		sendBoth(session, "Cases_PlaySound", SND_POOF, false)
		task.wait(0.08)
		sendBoth(session, "Cases_PlaySound", SND_OPEN, false)
		sendBoth(session, "Cases_OpenAndFreeze", chosenCase.Name)
		task.wait(0.6)

		if DataHandler and session.presenterTruth ~= nil then
			DataHandler.RecordDeclaration(session.presenter, session.presenterTruth)
		end

		if guesserWins then
			session.bank += session.cashPerRound
			Network.sendToClient(session.guesser, "Cases_UpdateBank", session.bank)

			billboard(session.guesser,   "+" .. session.cashPerRound .. " Banked!", Color3.fromRGB(80, 255, 120))
			task.wait(0.05)
			billboard(session.presenter, "Round " .. session.round .. " Lost",     Color3.fromRGB(255, 80, 80))
			task.wait(1.8)
			clearBillboard(session.guesser)
			clearBillboard(session.presenter)

			if session.round >= MAX_ROUNDS then
				print("[CASES] Round cap — force cash-out |", player.Name)
				doEndSequence(session, true, session.bank)
				return
			end

			session.stage = "keep_going"
			Network.sendToClient(session.presenter, "Cases_CamDirect3P")
			Network.sendToClient(session.guesser,   "Cases_CamDirect3P")
			task.wait(0.35)

			Network.sendToClient(session.guesser, "Cases_StopTimer")
			Network.sendToClient(session.guesser, "Cases_ShowKeepGoing", session.bank, session.round, session.cashPerRound)
			Network.sendToClient(session.guesser, "Cases_StartTimer", KEEP_GOING_TIMER)

			session.keepGoingThread = task.delay(KEEP_GOING_TIMER, function()
				if session.stage ~= "keep_going" then return end
				session.keepGoingThread = nil
				module.HandleKeepGoing(session.guesser, "cashout")
			end)
		else
			local presenterPrize = session.bank + session.cashPerRound
			print("[CASES] Guesser busted | presenter prize: $" .. presenterPrize, "| bank was: $" .. session.bank, "| round:", session.round)
			doEndSequence(session, false, presenterPrize)
		end
	end

	function module.HandleKeepGoing(player, decision)
		local session = activeSessions[player.UserId]
		if not session or session.stage ~= "keep_going" or player ~= session.guesser then return end

		if session.keepGoingThread then task.cancel(session.keepGoingThread); session.keepGoingThread = nil end
		sendBoth(session, "Cases_StopTimer")
		sendBoth(session, "Cases_HideKeepGoing")

		if decision == "cashout" then
			print("[CASES]", player.Name, "cashes out | bank: $" .. session.bank, "| round:", session.round)
			doEndSequence(session, true, session.bank)
		else
			session.round += 1
			session.stage = "reveal"
			print("[CASES]", player.Name, "keeps going | new round:", session.round)
			task.spawn(function() startNextRound(session) end)
		end
	end

	function module.HandlePlayerLeft(leavingPlayer)
		local session = activeSessions[leavingPlayer.UserId]
		if not session then return end
		if session.stage == "done" then return end
		session.stage = "done"
		cancelSessionTimers(session)

		local winner     = (leavingPlayer == session.presenter) and session.guesser or session.presenter
		local winnerRole = (winner == session.guesser) and "guesser" or "presenter"
		local cashPrize  = math.max(session.bank, 0)

		Network.sendToClient(winner, "Cases_StopTimer")
		Network.sendToClient(winner, "Cases_HideChoose")
		Network.sendToClient(winner, "Cases_HidePick")
		Network.sendToClient(winner, "Cases_HideKeepGoing")

		if DataHandler then
			if cashPrize > 0 then DataHandler.AddCurrencyRaw(winner, cashPrize, "Cash") end
			DataHandler.AddCurrency(winner, 1, "Streak")
			DataHandler.AddCurrency(winner, 1, "Wins")
			DataHandler.SetCurrency(leavingPlayer, 0, "Streak")
		end

		Network.sendToClient(winner, "Cases_CamDirect3P")
		Network.sendToClient(winner, "Cases_ShowUI")
		Network.sendToClient(winner, "Cases_ShowResult", winnerRole, true)
		billboard(winner, "YOU WIN!", Color3.fromRGB(80, 255, 120))
		Network.sendToClient(winner, "Cases_PlaySound", SND_WIN, false)
		Network.sendToClient(winner, "Cases_Confetti")

		if winner == session.guesser then
			Network.sendToClient(winner, "Cases_UpdateBank", 0)
		end

		task.delay(1.5, function()
			unlockPlayerFromSeat(winner)
			local char    = winner.Character
			local winSeat = (winner == session.presenter) and session.presenterSeat or session.guesserSeat
			if char then
				local h    = char:FindFirstChild("Humanoid")
				local hrp2 = char:FindFirstChild("HumanoidRootPart")
				if winSeat then local sw = winSeat:FindFirstChild("SeatWeld"); if sw then sw:Destroy() end end
				if hrp2 then for _, w in ipairs(hrp2:GetChildren()) do if w:IsA("Weld") and w.Name == "SeatWeld" then w:Destroy() end end end
				if h then h.Sit = false; h.Jump = true end
			end
			for _, seat in ipairs({session.presenterSeat, session.guesserSeat}) do
				if seat and seat.Parent then seat.Disabled = false end
			end
			if session.presenterSeat then session.presenterSeat.Anchored = true end
		end)

		task.delay(2, function() Network.sendToClient(winner, "Cases_TpToTable") end)
		task.delay(6, function()
			cleanupSession(session)
			pcall(function()
				Network.sendToClient(winner, "StealPrompt_MatchEnd")
				clearBillboard(winner)
			end)
			if module.onGameEnd then module.onGameEnd(session.presenter, session.guesser) end
		end)
	end

	function module.ApplyChair(player, seat, overrideCF) return applyChairToSeat(player, seat, overrideCF) end
	function module.RemoveChair(chairModel, seat) destroyChair(chairModel, seat) end
	function module.IsAISession(player)
		if AIHandler then return AIHandler.IsAISession(player) end
		return false
	end

	function module.Init()
		Network.onServer("Cases_PickChose", function(player, declaration, claimedGoodSide)
			if AIHandler and AIHandler.IsAISession(player) then AIHandler.HandlePresenterPick(player, declaration, claimedGoodSide); return end
			module.HandlePickChose(player, declaration, claimedGoodSide)
		end)

		Network.onServer("Cases_Chose", function(player, choice)
			if AIHandler and AIHandler.IsAISession(player) then AIHandler.HandleGuesserChose(player, choice); return end
			module.HandleChose(player, choice)
		end)

		Network.onServer("Cases_KeepGoingDecision", function(player, decision)
			if AIHandler and AIHandler.IsAISession(player) then AIHandler.HandleKeepGoing(player, decision); return end
			module.HandleKeepGoing(player, decision)
		end)

		-- PlayAI seat monitor
		task.spawn(function()
			local tablesFolder = workspace:WaitForChild("Map"):WaitForChild("Tables")
			for _, tg in ipairs(tablesFolder:GetChildren()) do
				for _, desc in ipairs(tg:GetDescendants()) do
					if desc:IsA("Seat") or desc:IsA("VehicleSeat") then
						local seat = desc; local prevOccupant = nil
						seat:GetPropertyChangedSignal("Occupant"):Connect(function()
							local occ = seat.Occupant
							if occ and occ:IsA("Humanoid") then
								local p = Players:GetPlayerFromCharacter(occ.Parent)
								if p then
									prevOccupant = p
									-- Eventuele extra logica voor bezetting hier toevoegen
								end
							elseif not occ and prevOccupant then
								prevOccupant = nil
							end
						end)
					end
				end
			end
		end)
	end

	return module

	