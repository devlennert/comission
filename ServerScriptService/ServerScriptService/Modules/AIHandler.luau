local module = {}
module.ENABLED = false  -- legacy AI cases/Noob mode. Set true to restore the old AI tables.

local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Network      = require(RS.Modules.Network)
local CashConfig   = require(RS.Modules.CashConfig)
local ChairInfo    = require(RS.Modules.ChairInfo)

local DataHandler

local SPAWN_Y   = 0.265
local DROP_H    = 35
local DROP_TIME = 2.4

local SND_FALLING   = "140065475003739"
local SND_LAND      = "9117451558"
local SND_DRUMROLL  = "4398694764"
local SND_POOF      = "107424340854522"
local SND_OPEN      = "108106344071650"
local SND_CASE_OPEN = "9114619627"
local SND_WIN       = "108165586294729"
local SND_LOSE      = "104387441091303"
local SND_TICK      = "99955064134003"
local SND_WINNER    = "99873338511718"

local OP_MIN,      OP_MAX      = 7,  11
local SUPEROP_MIN, SUPEROP_MAX = 12, 16

local FLAT          = CFrame.Angles(0, 0, math.pi / 2)
local ROT_FACENEG_X = CFrame.Angles(0, -math.pi / 2, 0) * FLAT
local ROT_FACEPOS_X = CFrame.Angles(0,  math.pi / 2, 0) * FLAT

local AI_TR_MIN        = 35
local AI_TR_MAX        = 85
local MAX_ROUNDS       = 100
local KEEP_GOING_TIMER = 20

local FLIP_X   = CFrame.Angles(math.pi, 0, 0)
local SIDE_ROT = CFrame.Angles(0, math.pi/2, 0)
local MODEL_DATA = {
	["1"]={flip=true},  ["2"]={flip=true},  ["3"]={flip=true},
	["4"]={flip=true},  ["5"]={flip=true},  ["6"]={flip=true},
	["7"]={flip=true},  ["8"]={flip=true},  ["9"]={flip=true},
	["10"]={side=true}, ["11"]={side=true}, ["12"]={side=true},
	["13"]={side=true}, ["14"]={flip=false},["15"]={flip=false},
	["16"]={flip=false},
}

local BILLBOARD_MAX_DISTANCE = 25

local NoobTemplate   = RS:WaitForChild("Noob")
local CashFolder     = RS:WaitForChild("Cash")
local ChairsFolder   = RS:WaitForChild("Assets"):WaitForChild("Chairs")
local AITablesFolder = workspace:WaitForChild("Map"):WaitForChild("AITables")

Network.define("Cases_CamToPos")
Network.define("StealPrompt_MatchStart")
Network.define("StealPrompt_MatchEnd")

local aiSessions  = {}
local aiTableList = {}

local function send(player, remote, ...) Network.sendToClient(player, remote, ...) end

local function randomTruthRate() return math.random(AI_TR_MIN, AI_TR_MAX) end

-- Fallback when DataHandler not yet assigned
local function getPlayerLuckFallback(player)
	local equippedVal = player:FindFirstChild("EquippedChair"); if not equippedVal then return 0 end
	local data = ChairInfo[equippedVal.Value]; return data and (data.Luck or 0) or 0
end

-- Full luck: chair + BonusLuck + 2x event — matches what the player sees on their overhead.
-- This is what we pass to pickWinner so the displayed luck stat actually affects the roll.
local function getFullPlayerLuck(player)
	if DataHandler then return DataHandler.GetEquippedLuck(player) end
	return getPlayerLuckFallback(player)
end

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
	local d = getDisplayForSeat(seat); if not d then return end
	for _, p in ipairs(d:GetDescendants()) do if p:IsA("BasePart") then p.Transparency = 1 end end
end

local function showDisplay(seat)
	local d = getDisplayForSeat(seat); if not d then return end
	for _, p in ipairs(d:GetDescendants()) do if p:IsA("BasePart") then p.Transparency = 0 end end
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
	local chairName = equippedVal.Value; if chairName == "Basic" then return nil end
	local modelTemplate = ChairsFolder:FindFirstChild(chairName); if not modelTemplate then return nil end
	local result
	local ok, err = pcall(function()
		local clone = modelTemplate:Clone(); clone.Name = "ChairModel"
		local chairbase = clone:FindFirstChild("Chairbase")
		local basePart = (chairbase and chairbase:FindFirstChild("Base")) or clone:FindFirstChildWhichIsA("BasePart")
		local relOffsets = {}
		if basePart then
			local inv = basePart.CFrame:Inverse()
			for _, part in ipairs(clone:GetDescendants()) do if part:IsA("BasePart") then relOffsets[part] = inv * part.CFrame end end
			relOffsets[basePart] = CFrame.new()
		end
		for _, part in ipairs(clone:GetDescendants()) do if part:IsA("BasePart") then part.Anchored = true end end
		local targetCF = (overrideCF or seat.CFrame) * CFrame.Angles(0, math.rad(0), 0)
		if basePart then for part, offset in pairs(relOffsets) do part.CFrame = targetCF * offset end
		else clone:PivotTo(targetCF) end
		hideDisplay(seat); clone.Parent = workspace; result = clone; clone:SetAttribute("SeatTag", seatTag)
	end)
	if not ok then warn("[CHAIR] Error applying chair for", player.Name, ":", err) end
	return result
end

local function destroyChair(chairModel, seat)
	if chairModel and chairModel.Parent then chairModel:Destroy() end
	if seat then showDisplay(seat) end
end

-- ── Cash roll ─────────────────────────────────────────────────────────────────

-- luck biases which TIER you land on (exponential weighting in pickWinner).
-- It does NOT multiply the rolled amount — that would silently diverge from the
-- dollar value printed on the 3D cash model the player is looking at.
-- Result: rolled tier visual = val.Value = cashPerRound = payout. Always exact.
local function pickWinner(luck, rollType)
	luck = luck or 0
	local entries = {}
	for name, e in pairs(CashConfig) do table.insert(entries, {name=name, amount=e.amount, weight=e.weight}) end
	table.sort(entries, function(a, b) return a.amount < b.amount end)
	local n = #entries; local minIdx, maxIdx = 1, n
	if rollType == "op"      then minIdx, maxIdx = OP_MIN,      OP_MAX      end
	if rollType == "superOp" then minIdx, maxIdx = SUPEROP_MIN, SUPEROP_MAX end
	local luckFactor = math.clamp(luck / 600, 0, 1)
	local totalBiased = 0; local biased = {}
	for i = minIdx, maxIdx do
		local rank = (i - minIdx) / math.max(maxIdx - minIdx, 1)
		local bw   = entries[i].weight * math.exp(luckFactor * rank * 5.5)
		biased[i] = bw; totalBiased += bw
	end
	local roll, cum = math.random() * totalBiased, 0
	for i = minIdx, maxIdx do cum += biased[i]; if roll <= cum then return entries[i].name end end
	return entries[maxIdx].name
end

local function doCashRoll(player, cashSpawn, luck)
	luck = luck or 0
	local allNames = {}
	for _, m in ipairs(CashFolder:GetChildren()) do table.insert(allNames, m.Name) end
	local FILLER  = 27; local LOCK_AT = FILLER
	local seq = {}
	for _ = 1, FILLER do table.insert(seq, allNames[math.random(1, #allNames)]) end
	table.insert(seq, nil)
	local times = {}
	for _=1,12 do table.insert(times, 0.07) end
	for _=1, 8 do table.insert(times, 0.15) end
	for _=1, 5 do table.insert(times, 0.30) end
	for _=1, 2 do table.insert(times, 0.55) end
	table.insert(times, 0)
	local spawnX = cashSpawn.Position.X; local spawnZ = cashSpawn.Position.Z
	local floorY = cashSpawn.Position.Y + cashSpawn.Size.Y / 2
	send(player, "OPRolls_ShowButtons")
	if DataHandler then
		local rolls = DataHandler.GetSessionRolls(player.UserId)
		send(player, "OPRolls_Update", rolls.op or 0, rolls.superOp or 0)
	end
	local current = nil; local winnerName = nil; local rollTypeUsed = nil
	for i = 1, #seq do
		if i == LOCK_AT and DataHandler then
			local pr = DataHandler.GetSessionRolls(player.UserId)
			if (pr.superOp or 0) > 0 then rollTypeUsed = "superOp"
			elseif (pr.op or 0) > 0  then rollTypeUsed = "op" end
			if rollTypeUsed then DataHandler.ConsumeOneRoll(player.UserId, rollTypeUsed) end
			winnerName = pickWinner(luck, rollTypeUsed); seq[#seq] = winnerName
			DataHandler.SetRollLocked(player.UserId, true)
			local pr2 = DataHandler.GetSessionRolls(player.UserId)
			send(player, "OPRolls_Update", pr2.op or 0, pr2.superOp or 0)
		end
		local name = seq[i]
		if not name then local w = times[i] or 0.55; if w > 0 then task.wait(w) end; continue end
		if current then current:Destroy() end
		local tmpl = CashFolder:FindFirstChild(name)
		if tmpl then
			current = tmpl:Clone(); current.Parent = workspace
			for _, p in ipairs(current:GetDescendants()) do
				if p:IsA("BasePart") then p.Anchored = true; p.CanCollide = false end
			end
			local d = MODEL_DATA[name] or {flip=false}
			local rotCF = d.flip and FLIP_X or (d.side and SIDE_ROT or CFrame.new())
			current:PivotTo(CFrame.new(spawnX, floorY, spawnZ) * rotCF)
			local bbCF, bbSize = current:GetBoundingBox()
			current:PivotTo(current:GetPivot() + Vector3.new(
				spawnX - bbCF.X, floorY - (bbCF.Y - bbSize.Y / 2), spawnZ - bbCF.Z))
			send(player, "Cases_PlaySound", i < #seq and SND_TICK or SND_WINNER, false)
		end
		local w = times[i] or 0.55; if w > 0 then task.wait(w) end
	end
	task.wait(1.2)
	if DataHandler then DataHandler.SetRollLocked(player.UserId, false) end
	send(player, "OPRolls_HideButtons")

	local cashEntry  = winnerName and CashConfig[winnerName]
	local baseAmount = cashEntry and cashEntry.amount or 100

	-- ── THE FIX: finalAmount = exactly the rolled tier's base amount.
	-- Luck already biased which tier was rolled. No hidden multiplier on top.
	-- This guarantees: model visual = val.Value = cashPerRound = payout.
	local finalAmount = baseAmount

	print("[AI] Roll winner:", winnerName,
		"| prize: $" .. finalAmount,
		"| luck (tier bias):", luck .. "%",
		"| rollType:", rollTypeUsed or "none")

	if current then
		local val = Instance.new("NumberValue", current)
		val.Name  = "Value"
		val.Value = finalAmount
	end
	return current, finalAmount
end

-- ── Case helpers ─────────────────────────────────────────────────────────────

local function prepareCase(model)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then p.CanCollide = false; p.Anchored = (p.Name == "HumanoidRootPart" or p.Name == "Cam") end
	end
	model.PrimaryPart = model.HumanoidRootPart
end

local function spawnInSky(template, finalCF)
	local m = template:Clone(); prepareCase(m); m:PivotTo(finalCF + Vector3.new(0, DROP_H, 0)); m.Parent = workspace; return m
end

local function updateCam(hrp, cam)
	if not cam then return end
	local camPos = hrp.Position + Vector3.new(0, 2.8, 0) - hrp.CFrame.LookVector * 0.6
	cam.CFrame = CFrame.lookAt(camPos, hrp.Position + Vector3.new(0, 0.1, 0), Vector3.new(0, 1, 0))
end

local function dropCase(caseModel, finalCF)
	local hrp = caseModel.HumanoidRootPart; local cam = caseModel:FindFirstChild("Cam")
	TweenService:Create(hrp, TweenInfo.new(DROP_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { CFrame = finalCF }):Play()
	task.wait(DROP_TIME); updateCam(hrp, cam)
end

local function shakeCase(caseModel, duration)
	local hrp = caseModel.HumanoidRootPart; local cam = caseModel:FindFirstChild("Cam")
	local origCF = hrp.CFrame; local deadline = tick() + duration; local step = 0
	while tick() < deadline do
		local progress = 1 - ((deadline - tick()) / duration)
		local intensity = progress * progress * progress
		TweenService:Create(hrp, TweenInfo.new(0.04, Enum.EasingStyle.Linear),
			{ CFrame = origCF + Vector3.new(math.sin(step*1.9)*intensity*0.5, math.abs(math.sin(step*3.7))*intensity*0.15, 0) }):Play()
		task.wait(0.04); step += 1
	end
	hrp.CFrame = origCF; updateCam(hrp, cam)
end

local function setCaseNumber(caseModel, number)
	local lid = caseModel:FindFirstChild("Lid", true); if not lid then return end
	for _, guiName in ipairs({"CaseGui", "InsideCaseGui"}) do
		local gui = lid:FindFirstChild(guiName)
		if gui then local label = gui:FindFirstChild("CaseNumber"); if label then label.Text = tostring(number) end end
	end
end

-- ── Billboard helpers ─────────────────────────────────────────────────────────

local function setBillboard(head, text, color)
	if not head then return end
	local old = head:FindFirstChild("CasePick"); if old then old:Destroy() end
	local bb = Instance.new("BillboardGui")
	bb.Name = "CasePick"; bb.Size = UDim2.new(0, 240, 0, 60)
	bb.StudsOffset = Vector3.new(0, 3.5, 0); bb.AlwaysOnTop = true
	bb.MaxDistance = BILLBOARD_MAX_DISTANCE; bb.Parent = head
	local lbl = Instance.new("TextLabel", bb)
	lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1
	lbl.TextColor3 = color; lbl.TextScaled = true; lbl.Font = Enum.Font.GothamBold; lbl.Text = text
	Instance.new("UIStroke", lbl).Thickness = 2
end

local function clearBillboard(head)
	if not head then return end; local b = head:FindFirstChild("CasePick"); if b then b:Destroy() end
end

local function playerHead(p) local c = p.Character; return c and c:FindFirstChild("Head") end
local function noobHead(noobChar) return noobChar and noobChar:FindFirstChild("Head") end

-- ── Noob helpers ─────────────────────────────────────────────────────────────

local function makeWaitingBB(seat) return nil end
local function setWaitingBB(bb, occupied)
	local lbl = bb and bb:FindFirstChild("Label"); if not lbl then return end
	if occupied then lbl.Text="2/2"; lbl.TextColor3=Color3.fromRGB(80,255,120)
	else             lbl.Text="1/2"; lbl.TextColor3=Color3.fromRGB(255,220,50) end
end
local function makeNoobOverhead(noobChar) end

local function spawnNoob(seat)
	local clone = NoobTemplate:Clone(); clone.Name = "AINoob"
	for _, p in ipairs(clone:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = true end end
	clone.Parent = workspace
	local hrp = clone:FindFirstChild("HumanoidRootPart")
	if hrp then hrp.CFrame = seat.CFrame * CFrame.new(0, 0.5, 0) end
	local hum = clone:FindFirstChild("Humanoid")
	if hum and seat:IsA("Seat") and seat.Occupant == nil then seat:Sit(hum) end
	for _, p in ipairs(clone:GetDescendants()) do if p:IsA("BasePart") and p ~= hrp then p.Anchored = false end end
	if hrp then hrp.Anchored = false end
	makeNoobOverhead(clone); return clone
end

local BASE_JUMP_POWER = 50
local function lockPlayerInSeat(player)
	local char = player.Character; local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then hum.JumpPower = 0; hum.JumpHeight = 0 end
end
local function unlockPlayerFromSeat(player)
	local char = player.Character; local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then hum.JumpPower = BASE_JUMP_POWER; hum.JumpHeight = 7.2 end
end

local function reseatNoob(noobChar, aiSeat)
	if not noobChar or not noobChar.Parent or not aiSeat then return end
	local hum = noobChar:FindFirstChild("Humanoid"); if not hum then return end
	if aiSeat.Occupant == hum then return end
	local nHrp = noobChar:FindFirstChild("HumanoidRootPart"); if not nHrp then return end
	nHrp.Anchored = true; nHrp.CFrame = aiSeat.CFrame * CFrame.new(0, 0.5, 0)
	if aiSeat:IsA("Seat") and aiSeat.Occupant == nil then aiSeat:Sit(hum) end
	nHrp.Anchored = false
end

local function findSeats(tableGroup)
	local seats = {}
	for _, d in ipairs(tableGroup:GetDescendants()) do
		if d:IsA("Seat") or d:IsA("VehicleSeat") then table.insert(seats, d) end
	end
	table.sort(seats, function(a, b) return a.Position.Z > b.Position.Z end)
	return seats
end

local function showTableGui(tData)
	if tData.tableGui  then tData.tableGui.Enabled = true  end
	if tData.waitLabel then tData.waitLabel.Text   = "1/2" end
end
local function hideTableGui(tData) if tData.tableGui then tData.tableGui.Enabled = false end end

local function resetTable(tData)
	tData.busy = false; tData.countdownThread = nil; tData.currentPlayer = nil; tData.playerChairModel = nil
	setWaitingBB(tData.waitBB, false)
	if tData.playerSeat and tData.playerSeat.Parent then tData.playerSeat.Disabled = false end
	showTableGui(tData)
	if tData.waitLabel then tData.waitLabel.Text = "1/2" end
end

local function cancelSessionTimers(session)
	if session.timerThread     then task.cancel(session.timerThread);     session.timerThread     = nil end
	if session.keepGoingThread then task.cancel(session.keepGoingThread); session.keepGoingThread = nil end
end

-- ── AI declaration logic ─────────────────────────────────────────────────────

local function aiMakeDeclaration(leftIsGood, aiTR)
	local honest   = math.random(1, 100) <= aiTR
	local goodSide = leftIsGood and "Left" or "Right"
	local badSide  = leftIsGood and "Right" or "Left"
	if honest then
		return (goodSide == "Left" and "Case 1 Has Cash" or "Case 2 Has Cash"), goodSide, true
	else
		return (badSide == "Left" and "Case 1 Has Cash" or "Case 2 Has Cash"), badSide, false
	end
end

-- ── End-of-game sequence ──────────────────────────────────────────────────────

local function finishAIGame(player, session, humanWins)
	if session.stage == "done" then return end
	session.stage = "done"

	local tData    = session.tableInfo
	local noobChar = tData.noobChar

	cancelSessionTimers(session)
	send(player, "Cases_StopTimer")
	send(player, "Cases_HideKeepGoing")
	send(player, "Cases_UpdateBank", 0)
	send(player, "Cases_ShowUI")
	send(player, "Cases_ShowResult", "guesser", humanWins)

	if humanWins then
		if DataHandler then
			-- AddCurrencyRaw: pays the bank exactly as displayed, zero hidden multipliers
			if session.bank > 0 then DataHandler.AddCurrencyRaw(player, session.bank, "Cash") end
			DataHandler.AddCurrency(player, 1, "Streak")
			DataHandler.AddCurrency(player, 1, "Wins")
		end
		send(player, "Cases_PlaySound", SND_WIN, false)
		send(player, "Cases_Confetti")
		setBillboard(playerHead(player), "YOU WIN!", Color3.fromRGB(80,  255, 120))
		setBillboard(noobHead(noobChar),  "You Lose", Color3.fromRGB(255, 80,  80))
	else
		if DataHandler then DataHandler.SetCurrency(player, 0, "Streak") end
		send(player, "Cases_PlaySound", SND_LOSE, false)
		setBillboard(playerHead(player), "You Lose",  Color3.fromRGB(255, 80,  80))
		setBillboard(noobHead(noobChar),  "YOU WIN!", Color3.fromRGB(80,  255, 120))
	end

	task.delay(1.5, function()
		unlockPlayerFromSeat(player)
		local char = player.Character; local pSeat = tData.playerSeat
		if char then
			local h = char:FindFirstChild("Humanoid"); local hrp = char:FindFirstChild("HumanoidRootPart")
			if pSeat then local sw = pSeat:FindFirstChild("SeatWeld"); if sw then sw:Destroy() end end
			if hrp then for _, w in ipairs(hrp:GetChildren()) do if w:IsA("Weld") and w.Name == "SeatWeld" then w:Destroy() end end end
			if h then h.Sit = false; h.Jump = true end
		end
		if pSeat and pSeat.Parent then pSeat.Disabled = false end
	end)

	task.delay(2, function()
		local char = player.Character; local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then hrp.CFrame = tData.playerSeat.CFrame * CFrame.new(0, 4, 10) end
		send(player, "Cases_CamDirect3P")
	end)

	task.delay(6, function()
		clearBillboard(playerHead(player)); clearBillboard(noobHead(noobChar))
		if session.playerChair then destroyChair(session.playerChair, tData.playerSeat); session.playerChair = nil
		else showDisplay(tData.playerSeat) end
		for _, obj in ipairs({session.leftCase, session.rightCase, session.cashModel}) do
			if obj and obj.Parent then obj:Destroy() end
		end
		send(player, "StealPrompt_MatchEnd")
		if aiSessions[player.UserId] == session then aiSessions[player.UserId] = nil end
		if DataHandler then DataHandler.ClearSessionRolls(player.UserId) end
		tData.aiTruthRate = randomTruthRate()
		resetTable(tData)
		print("[AI] Table", tData.tableGroup.Name, "reset | new AI TR:", tData.aiTruthRate .. "%")
		task.wait(0.5); reseatNoob(noobChar, tData.aiSeat)
	end)
end

-- ── Per-round resolve ─────────────────────────────────────────────────────────

local function resolveAIRound(player, session, humanWins, chosenCase)
	cancelSessionTimers(session)
	send(player, "Cases_StopTimer")

	send(player, "Cases_CamToCase", chosenCase.Name, 0.9)
	task.wait(1.0)
	send(player, "Cases_PlaySound", SND_DRUMROLL, false)
	shakeCase(chosenCase, 3.5)
	send(player, "Cases_PlaySound", SND_POOF, false)
	task.wait(0.08)
	send(player, "Cases_PlaySound", SND_OPEN, false)
	send(player, "Cases_OpenAndFreeze", chosenCase.Name)
	task.wait(0.6)

	local tData    = session.tableInfo
	local noobChar = tData.noobChar

	if humanWins then
		session.bank += session.cashPerRound
		send(player, "Cases_UpdateBank", session.bank)

		setBillboard(playerHead(player), "+" .. session.cashPerRound .. " Banked!", Color3.fromRGB(80, 255, 120))
		setBillboard(noobHead(noobChar),  "Round " .. session.round .. " Lost",    Color3.fromRGB(255, 80, 80))
		task.wait(1.8)
		clearBillboard(playerHead(player)); clearBillboard(noobHead(noobChar))

		if session.round >= MAX_ROUNDS then
			print("[AI] Round cap — force cash-out for", player.Name)
			finishAIGame(player, session, true)
			return
		end

		session.stage = "keep_going"
		send(player, "Cases_CamDirect3P")
		task.wait(0.35)
		send(player, "Cases_StopTimer")
		send(player, "Cases_ShowKeepGoing", session.bank, session.round, session.cashPerRound)
		send(player, "Cases_StartTimer", KEEP_GOING_TIMER)

		session.keepGoingThread = task.delay(KEEP_GOING_TIMER, function()
			if session.stage ~= "keep_going" then return end
			session.keepGoingThread = nil
			module.HandleKeepGoing(player, "cashout")
		end)
	else
		print("[AI] Player busted | bank lost: $" .. session.bank, "| round:", session.round)
		clearBillboard(playerHead(player)); clearBillboard(noobHead(noobChar))
		finishAIGame(player, session, false)
	end
end

-- ── Next-round drop + declaration ─────────────────────────────────────────────

local function startNextAIRound(player, session)
	cancelSessionTimers(session)

	local tData   = session.tableInfo
	local caseTag = session.caseTag

	if session.leftCase  and session.leftCase.Parent  then session.leftCase:Destroy()  end
	if session.rightCase and session.rightCase.Parent then session.rightCase:Destroy() end

	session.leftIsGood = math.random() > 0.5
	local leftCase  = spawnInSky(session.leftIsGood      and RS.Cases.GoodCase or RS.Cases.BadCase, session.leftCF)
	local rightCase = spawnInSky((not session.leftIsGood) and RS.Cases.GoodCase or RS.Cases.BadCase, session.rightCF)
	leftCase.Name  = "BriefcaseLeft"  .. caseTag
	rightCase.Name = "BriefcaseRight" .. caseTag
	setCaseNumber(leftCase, 1); setCaseNumber(rightCase, 2)
	session.leftCase = leftCase; session.rightCase = rightCase

	send(player, "Cases_ShowRound", session.round)
	task.wait(1.8)

	send(player, "Cases_CamWatchDrop", session.midPos)
	task.wait(0.85)
	local timeUntilLand = 0.15 + DROP_TIME
	send(player, "Cases_PlaySound",  SND_FALLING, true)
	send(player, "Cases_LandImpact", session.midPos, SND_LAND, timeUntilLand)
	task.spawn(function() dropCase(leftCase,  session.leftCF)  end)
	task.wait(0.15)
	task.spawn(function() dropCase(rightCase, session.rightCF) end)
	task.wait(DROP_TIME * 0.52)
	send(player, "Cases_CamTrackLand", session.midPos, DROP_TIME * 0.48)
	task.wait(DROP_TIME * 0.48 + 0.15)
	send(player, "Cases_StopSound", SND_FALLING)
	task.wait(0.5)

	task.wait(0.8)
	send(player, "Cases_CamToPos", session.tableCamCF, 0.7)
	task.wait(1.2)
	local decl, claimedGood, _ = aiMakeDeclaration(session.leftIsGood, session.aiTruthRate)
	session.aiClaimedGood = claimedGood
	setBillboard(noobHead(tData.noobChar), decl, Color3.fromRGB(255, 210, 50))
	task.wait(1.6)

	send(player, "Cases_CamFirstPerson")
	task.wait(0.4)

	session.stage = "player_guesser_pick"
	send(player, "Cases_ShowChoose")
	send(player, "Cases_StopTimer")
	send(player, "Cases_StartTimer", 30)
	session.timerThread = task.delay(30, function()
		if session.stage ~= "player_guesser_pick" then return end
		session.timerThread = nil
		local wrongChoice   = session.leftIsGood and "2" or "1"
		local correctChoice = session.leftIsGood and "1" or "2"
		module.HandleGuesserChose(player, math.random() < 0.65 and wrongChoice or correctChoice)
	end)
end

-- ── Table init ────────────────────────────────────────────────────────────────

local function initAITable(tableGroup)
	local seats = findSeats(tableGroup)
	if #seats < 2 then warn("[AI] TableGroup", tableGroup.Name, "needs ≥ 2 seats, found", #seats); return end
	local cashSpawn = tableGroup:FindFirstChild("CashSpawn")
	if not cashSpawn then warn("[AI] TableGroup", tableGroup.Name, "missing CashSpawn"); return end

	local aiSeat = seats[1]; local playerSeat = seats[2]
	local noobChar = spawnNoob(aiSeat); local waitBB = makeWaitingBB(playerSeat)
	local tableGui  = tableGroup:FindFirstChild("table") and tableGroup.table:FindFirstChild("TableGui")
	local waitLabel = tableGui and tableGui:FindFirstChild("WaitingLabel")
	if tableGui  then tableGui.Enabled = true  end
	if waitLabel then waitLabel.Text   = "1/2" end

	local tData = {
		tableGroup = tableGroup, cashSpawn = cashSpawn, aiSeat = aiSeat,
		playerSeat = playerSeat, playerSeatCF = playerSeat.CFrame,
		noobChar = noobChar, waitBB = waitBB, tableGui = tableGui, waitLabel = waitLabel,
		aiTruthRate = randomTruthRate(), busy = false, conn = nil,
		countdownThread = nil, currentPlayer = nil, playerChairModel = nil,
	}

	tData.conn = playerSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occ = playerSeat.Occupant
		if not occ then
			if tData.countdownThread then
				task.cancel(tData.countdownThread)
				if tData.currentPlayer then
					Network.sendToClient(tData.currentPlayer, "OPRolls_HideButtons")
					unlockPlayerFromSeat(tData.currentPlayer)
				end
				local chairToDestroy = tData.playerChairModel
				resetTable(tData)
				if chairToDestroy then destroyChair(chairToDestroy, playerSeat) end
			elseif tData.playerChairModel then
				destroyChair(tData.playerChairModel, playerSeat); tData.playerChairModel = nil
			end
			return
		end
		local p = Players:GetPlayerFromCharacter(occ.Parent); if not p then return end
		if not tData.busy and not aiSessions[p.UserId] then
			if tData.playerChairModel then destroyChair(tData.playerChairModel, playerSeat); tData.playerChairModel = nil end
			tData.playerChairModel = applyChairToSeat(p, playerSeat, tData.playerSeatCF)
			tData.busy = true; tData.currentPlayer = p; setWaitingBB(waitBB, true)
			tData.countdownThread = task.spawn(function()
				if tData.waitLabel then tData.waitLabel.Text = "2/2" end
				if DataHandler then
					local rolls = DataHandler.GetSessionRolls(p.UserId)
					Network.sendToClient(p, "OPRolls_ShowButtons")
					Network.sendToClient(p, "OPRolls_Update", rolls.op or 0, rolls.superOp or 0)
				end
				for i = 5, 1, -1 do
					if tData.waitLabel then tData.waitLabel.Text = tostring(i) end
					task.wait(1)
					local stillSeated = playerSeat.Occupant ~= nil
						and Players:GetPlayerFromCharacter(playerSeat.Occupant.Parent) == p
					if not stillSeated then
						Network.sendToClient(p, "OPRolls_HideButtons")
						resetTable(tData); return
					end
				end
				tData.countdownThread = nil
				local finallySeated = playerSeat.Occupant ~= nil
					and Players:GetPlayerFromCharacter(playerSeat.Occupant.Parent) == p
				if not finallySeated then
					Network.sendToClient(p, "OPRolls_HideButtons")
					resetTable(tData); return
				end
				hideTableGui(tData)
				module.StartAIGame(p, tData)
			end)
		end
	end)

	table.insert(aiTableList, tData)
	print("[AI] Table ready:", tableGroup.Name, "| AI TR:", tData.aiTruthRate .. "%")
end

-- ── Public API ────────────────────────────────────────────────────────────────

function module.StartAIGame(player, tData)
	if aiSessions[player.UserId] then return end

	local tableGroup = tData.tableGroup; local playerSeat = tData.playerSeat
	local presenterFacesNegX = playerSeat.CFrame.LookVector.X < 0
	local spawnName = presenterFacesNegX and "Spawns1" or "Spawns2"
	local spawns = {}
	for _, v in ipairs(tableGroup:GetChildren()) do if v.Name == spawnName then table.insert(spawns, v) end end
	if #spawns < 2 then warn("[AI] Not enough spawn points in", tableGroup.Name); resetTable(tData); return end
	table.sort(spawns, function(a, b) return a.Position.Z > b.Position.Z end)

	local leftIsGood = math.random() > 0.5
	local guesserRot = presenterFacesNegX and ROT_FACEPOS_X or ROT_FACENEG_X
	local leftIdx    = presenterFacesNegX and 1 or 2
	local rightIdx   = presenterFacesNegX and 2 or 1
	local leftCF     = CFrame.new(spawns[leftIdx].Position  + Vector3.new(0, SPAWN_Y, 0)) * guesserRot
	local rightCF    = CFrame.new(spawns[rightIdx].Position + Vector3.new(0, SPAWN_Y, 0)) * guesserRot
	local midPos     = (spawns[leftIdx].Position + spawns[rightIdx].Position) / 2

	local leftCase  = spawnInSky(leftIsGood      and RS.Cases.GoodCase or RS.Cases.BadCase, leftCF)
	local rightCase = spawnInSky((not leftIsGood) and RS.Cases.GoodCase or RS.Cases.BadCase, rightCF)
	local caseTag   = "_" .. player.UserId
	leftCase.Name   = "BriefcaseLeft"  .. caseTag
	rightCase.Name  = "BriefcaseRight" .. caseTag
	setCaseNumber(leftCase, 1); setCaseNumber(rightCase, 2)

	local tableCamCF = CFrame.lookAt(midPos + Vector3.new(0,5,11), midPos + Vector3.new(0,0.5,0))
	local cashCamCF  = CFrame.lookAt(tData.cashSpawn.Position + Vector3.new(0,3,6), tData.cashSpawn.Position + Vector3.new(0,0.5,0))

	local playerChair = tData.playerChairModel; tData.playerChairModel = nil

	-- Full luck: chair + BonusLuck + 2x event so the stat the player sees on their
	-- overhead is exactly what biases the roll tier selection in pickWinner.
	local playerLuck = getFullPlayerLuck(player)

	local session = {
		player = player, caseTag = caseTag,
		leftCase = leftCase, rightCase = rightCase, leftIsGood = leftIsGood,
		leftCF = leftCF, rightCF = rightCF, midPos = midPos,
		cashModel = nil, cashPerRound = 0,
		tableInfo = tData, tableCamCF = tableCamCF,
		aiTruthRate = tData.aiTruthRate, stage = "cashroll",
		aiClaimedGood = nil, playerChair = playerChair,
		timerThread = nil,
		round = 1, bank = 0, keepGoingThread = nil,
	}
	aiSessions[player.UserId] = session

	lockPlayerInSeat(player)
	send(player, "StealPrompt_MatchStart", nil)
	send(player, "Cases_HideUI")

	print("[AI] Game started |", player.Name,
		"| AI TR:", session.aiTruthRate .. "%",
		"| luck:", playerLuck .. "% (full: chair+bonus+event)")

	send(player, "Cases_CamToPos", cashCamCF, 0.5)
	task.wait(0.6)

	if DataHandler then DataHandler.FlushPendingBoughtNotifs(player, player) end
	local cashModel, cashAmount = doCashRoll(player, tData.cashSpawn, playerLuck)
	task.wait(0.4)

	if aiSessions[player.UserId] ~= session then
		for _, obj in ipairs({cashModel, leftCase, rightCase}) do if obj and obj.Parent then obj:Destroy() end end
		return
	end

	session.cashModel    = cashModel
	session.cashPerRound = cashAmount   -- exact base amount of rolled tier, no hidden multipliers
	session.stage        = "drop"

	send(player, "Cases_CamWatchDrop", midPos)
	task.wait(0.85)
	local timeUntilLand = 0.15 + DROP_TIME
	send(player, "Cases_PlaySound",  SND_FALLING, true)
	send(player, "Cases_LandImpact", midPos, SND_LAND, timeUntilLand)
	task.spawn(function() dropCase(leftCase,  leftCF)  end)
	task.wait(0.15)
	task.spawn(function() dropCase(rightCase, rightCF) end)
	task.wait(DROP_TIME * 0.52)
	send(player, "Cases_CamTrackLand", midPos, DROP_TIME * 0.48)
	task.wait(DROP_TIME * 0.48 + 0.15)
	send(player, "Cases_StopSound", SND_FALLING)
	task.wait(0.5)

	task.wait(0.8)
	send(player, "Cases_CamToPos", tableCamCF, 0.7)
	task.wait(1.2)
	local decl, claimedGood, _ = aiMakeDeclaration(leftIsGood, session.aiTruthRate)
	session.aiClaimedGood = claimedGood
	setBillboard(noobHead(tData.noobChar), decl, Color3.fromRGB(255, 210, 50))
	task.wait(1.6)
	send(player, "Cases_CamFirstPerson")
	task.wait(0.4)

	session.stage = "player_guesser_pick"
	send(player, "Cases_ShowChoose")
	send(player, "Cases_StopTimer")
	send(player, "Cases_StartTimer", 30)
	session.timerThread = task.delay(30, function()
		if session.stage ~= "player_guesser_pick" then return end
		session.timerThread = nil
		local wrongChoice   = session.leftIsGood and "2" or "1"
		local correctChoice = session.leftIsGood and "1" or "2"
		module.HandleGuesserChose(player, math.random() < 0.65 and wrongChoice or correctChoice)
	end)
end

function module.HandleGuesserChose(player, choice)
	local session = aiSessions[player.UserId]
	if not session or session.stage ~= "player_guesser_pick" then return end
	session.stage = "resolving"

	cancelSessionTimers(session)
	send(player, "Cases_StopTimer")
	send(player, "Cases_HideChoose")

	local physSide   = choice == "1" and "Left" or "Right"
	local humanWins  = (physSide == "Left") == session.leftIsGood
	local chosenCase = physSide == "Left" and session.leftCase or session.rightCase
	print("[AI] Round", session.round, "| guessed:", physSide, "| wins:", humanWins)
	resolveAIRound(player, session, humanWins, chosenCase)
end

function module.HandleKeepGoing(player, decision)
	local session = aiSessions[player.UserId]
	if not session or session.stage ~= "keep_going" then return end

	cancelSessionTimers(session)
	send(player, "Cases_StopTimer")
	send(player, "Cases_HideKeepGoing")

	if decision == "cashout" then
		print("[AI]", player.Name, "cashes out | bank: $" .. session.bank, "| round:", session.round)
		finishAIGame(player, session, true)
	else
		session.round += 1
		session.stage = "drop"
		print("[AI]", player.Name, "keeps going | new round:", session.round)
		task.spawn(function() startNextAIRound(player, session) end)
	end
end

function module.HandlePresenterPick(player, declaration, claimedGoodSide) end

function module.IsAISession(player)     return aiSessions[player.UserId] ~= nil end
function module.GetSessionTruthRate(player)
	local s = aiSessions[player.UserId]; return s and s.aiTruthRate or nil
end
function module.GetFreeAITableInfo()
	if #aiTableList == 0 then return nil end
	for _, tData in ipairs(aiTableList) do if not tData.busy then return tData end end
	return aiTableList[math.random(1, #aiTableList)]
end
function module.SetDataHandler(h) DataHandler = h end

function module.Init()
	if not module.ENABLED then
		print("[AI] AIHandler disabled — legacy AI tables/Noobs off")
		return
	end
	for _, tg in ipairs(AITablesFolder:GetChildren()) do
		if tg:IsA("Folder") or tg:IsA("Model") then task.spawn(function() initAITable(tg) end) end
	end

	Players.PlayerRemoving:Connect(function(player)
		local session = aiSessions[player.UserId]; if not session then return end
		unlockPlayerFromSeat(player)
		cancelSessionTimers(session)
		if session.playerChair then destroyChair(session.playerChair, session.tableInfo.playerSeat); session.playerChair = nil
		else showDisplay(session.tableInfo.playerSeat) end
		for _, obj in ipairs({session.leftCase, session.rightCase, session.cashModel}) do
			if obj and obj.Parent then obj:Destroy() end
		end
		clearBillboard(noobHead(session.tableInfo.noobChar))
		aiSessions[player.UserId] = nil
		local tData = session.tableInfo
		tData.aiTruthRate = randomTruthRate()
		resetTable(tData)
		print("[AI] Table", tData.tableGroup.Name, "reset (player left) | new AI TR:", tData.aiTruthRate .. "%")
		task.delay(0.5, function() reseatNoob(tData.noobChar, tData.aiSeat) end)
	end)

	print("[AI] AIHandler initialised |", #AITablesFolder:GetChildren(), "AI table(s) found")
end

return module