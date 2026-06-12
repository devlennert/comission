-- RiskHandler  (Script — place alongside CasesHandler / AIHandler)
-- Solo risk gamemode: 5 cases drop (4 cash, 1 empty).
-- Player picks cases one at a time.  Each cash case adds to their running bank.
-- They can CASH OUT after any cash find, or KEEP GOING.
-- Picking the empty case wipes the entire bank.
-- If all 4 cash cases are opened the player auto-wins everything.
--
-- Workspace.Map.RiskMode
--   └─ TableGroup (Folder or Model)
--        ├─ Seat  (Seat or VehicleSeat)
--        ├─ Spawns1 … Spawns5  (BasePart)
--        └─ table (Model)
--             └─ TableGui (ScreenGui/SurfaceGui)
--                  └─ WaitingLabel (TextLabel)

local module = {}
local RISK_ENABLED = false  -- legacy solo risk minigame. Set true to restore it.

local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Network      = require(RS.Modules.Network)
local ChairInfo    = require(RS.Modules.ChairInfo)
local DataHandler  = require(script.Parent.DataHandler)

-- ─── Constants ────────────────────────────────────────────────────────────────

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

local BILLBOARD_MAX_DISTANCE = 25
local FLAT = CFrame.Angles(0, 0, math.pi / 2)

-- Cash tiers — sorted ascending so cheaper prizes come first
local RISK_CASH_POOL = { 250, 500, 1000, 1500, 2500, 4000, 6000, 10000, 50000 }

local RiskTablesFolder = workspace:WaitForChild("Map"):WaitForChild("RiskMode")

-- ─── Network ─────────────────────────────────────────────────────────────────

Network.define("Risk_ShowCasePick")     -- server → client : {available indices}
Network.define("Risk_HideCasePick")
Network.define("Risk_ShowCashOut")      -- server → client : foundAmount, bankTotal, remaining
Network.define("Risk_HideCashOut")
Network.define("Risk_UpdateBank")       -- server → client : bankTotal
Network.define("Risk_CasePicked")       -- client → server : caseIndex
Network.define("Risk_CashOutDecision")  -- client → server : "cashout" | "keepgoing"
Network.define("Risk_ShowResult")       -- server → client : won (bool), amount

-- ─── State ───────────────────────────────────────────────────────────────────

local riskSessions  = {}
local riskTableList = {}

-- ─── Utility ─────────────────────────────────────────────────────────────────

local function send(player, remote, ...)
	Network.sendToClient(player, remote, ...)
end

local function getPlayerLuck(player)
	local eq = player:FindFirstChild("EquippedChair")
	if not eq then return 0 end
	local data = ChairInfo[eq.Value]
	return data and (data.Luck or 0) or 0
end

local function playerHead(player)
	local c = player.Character
	return c and c:FindFirstChild("Head")
end

local function setBillboard(head, text, color)
	if not head then return end
	local old = head:FindFirstChild("RiskTag")
	if old then old:Destroy() end
	local bb  = Instance.new("BillboardGui")
	bb.Name        = "RiskTag"
	bb.Size        = UDim2.new(0, 260, 0, 65)
	bb.StudsOffset = Vector3.new(0, 3.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = BILLBOARD_MAX_DISTANCE
	bb.Parent      = head
	local lbl = Instance.new("TextLabel", bb)
	lbl.Size                   = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3             = color
	lbl.TextScaled             = true
	lbl.Font                   = Enum.Font.GothamBold
	lbl.Text                   = text
	Instance.new("UIStroke", lbl).Thickness = 2
end

local function clearBillboard(player)
	if not player.Character then return end
	local head = player.Character:FindFirstChild("Head")
	if not head then return end
	local b = head:FindFirstChild("RiskTag")
	if b then b:Destroy() end
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

local function spawnInSky(template, finalCF)
	local m = template:Clone()
	prepareCase(m)
	m:PivotTo(finalCF + Vector3.new(0, DROP_H, 0))
	m.Parent = workspace
	return m
end

local function updateCam(hrp, cam)
	if not cam then return end
	local camPos = hrp.Position + Vector3.new(0, 2.8, 0) - hrp.CFrame.LookVector * 0.6
	cam.CFrame = CFrame.lookAt(camPos, hrp.Position + Vector3.new(0, 0.1, 0), Vector3.new(0, 1, 0))
end

local function dropCase(caseModel, finalCF)
	local hrp = caseModel.HumanoidRootPart
	local cam = caseModel:FindFirstChild("Cam")
	TweenService:Create(hrp,
		TweenInfo.new(DROP_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
		{ CFrame = finalCF }):Play()
	task.wait(DROP_TIME)
	updateCam(hrp, cam)
end

local function shakeCase(caseModel, duration)
	local hrp      = caseModel.HumanoidRootPart
	local cam      = caseModel:FindFirstChild("Cam")
	local origCF   = hrp.CFrame
	local deadline = tick() + duration
	local step     = 0
	while tick() < deadline do
		local progress  = 1 - ((deadline - tick()) / duration)
		local intensity = progress * progress * progress
		local side      = math.sin(step * 1.9)           * intensity * 0.5
		local up        = math.abs(math.sin(step * 3.7)) * intensity * 0.15
		TweenService:Create(hrp,
			TweenInfo.new(0.04, Enum.EasingStyle.Linear),
			{ CFrame = origCF + Vector3.new(side, up, 0) }):Play()
		task.wait(0.04)
		step += 1
	end
	hrp.CFrame = origCF
	updateCam(hrp, cam)
end

local function setCaseNumber(caseModel, number)
	local lid = caseModel:FindFirstChild("Lid", true)
	if not lid then return end
	for _, guiName in ipairs({"CaseGui", "InsideCaseGui"}) do
		local gui = lid:FindFirstChild(guiName)
		if gui then
			local label = gui:FindFirstChild("CaseNumber")
			if label then label.Text = tostring(number) end
		end
	end
end

-- Sets the dollar label inside each GoodCase's Safe part.
-- Path: model > Safe (Part) > SafeGui (SurfaceGui) > Frame > SafeText (TextLabel)
local function setCashLabel(caseModel, amount)
	local safe = caseModel:FindFirstChild("Safe", true)
	if not safe then return end
	local safeGui = safe:FindFirstChild("SafeGui")
	if not safeGui then return end
	local frame = safeGui:FindFirstChild("Frame")
	if not frame then return end
	local label = frame:FindFirstChild("SafeText")
	if not label then return end
	label.Text = "$" .. tostring(amount)
end

-- Mirrors the AIHandler pattern for finding a TableGroup's GUI.
local function findTableGui(tableGroup)
	local t = tableGroup:FindFirstChild("table")
	if not t then return nil, nil end
	local gui = t:FindFirstChild("TableGui")
	if not gui then return nil, nil end
	return gui, gui:FindFirstChild("WaitingLabel")
end

local function showTableGui(tData)
	if tData.tableGui  then tData.tableGui.Enabled  = true   end
	if tData.waitLabel then tData.waitLabel.Text    = "PLAY!" end
end

local function hideTableGui(tData)
	if tData.tableGui then tData.tableGui.Enabled = false end
end

local function pickCashAmounts(luck)
	local pool  = {}
	for _, v in ipairs(RISK_CASH_POOL) do table.insert(pool, v) end
	local boost    = math.floor(math.clamp(luck / 100 * 3, 0, 3))
	local eligible = {}
	for i = 1 + boost, #pool do table.insert(eligible, pool[i]) end
	if #eligible < 4 then eligible = pool end
	for i = #eligible, 2, -1 do
		local j = math.random(1, i)
		eligible[i], eligible[j] = eligible[j], eligible[i]
	end
	local result = {}
	for i = 1, 4 do result[i] = eligible[i] or pool[math.random(#pool)] end
	table.sort(result)  -- ascending: smaller prizes first
	return result
end

local function computeOverviewCam(spawnPositions, seatCF)
	local sum = Vector3.new()
	for _, pos in ipairs(spawnPositions) do sum = sum + pos end
	local mid = sum / #spawnPositions

	local maxRadius = 0
	for _, pos in ipairs(spawnPositions) do
		local d = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(mid.X, 0, mid.Z)).Magnitude
		if d > maxRadius then maxRadius = d end
	end
	maxRadius = math.max(maxRadius, 4)

	local seatDelta = seatCF.Position - mid
	local horizDir  = Vector3.new(seatDelta.X, 0, seatDelta.Z)
	if horizDir.Magnitude < 0.01 then horizDir = seatCF.LookVector * -1 end
	horizDir = horizDir.Unit

	local camDist = maxRadius * 2.4
	local camPos  = mid + horizDir * camDist * 0.3 + Vector3.new(0, camDist * 1.05, 0)
	return CFrame.lookAt(camPos, mid + Vector3.new(0, 0.4, 0))
end

-- ─── Table Initialisation ────────────────────────────────────────────────────

local function findSeat(tableGroup)
	for _, d in ipairs(tableGroup:GetDescendants()) do
		if d:IsA("Seat") or d:IsA("VehicleSeat") then return d end
	end
end

local startRiskGame
local showPick
local handleCasePicked
local handleCashOutDecision
local cleanupSession

local function initRiskTable(tableGroup)
	local seat = findSeat(tableGroup)
	if not seat then warn("[RISK]", tableGroup.Name, "— no Seat found"); return end

	local spawnParts = {}
	for i = 1, 5 do
		local sp = tableGroup:FindFirstChild("Spawns" .. i)
		if sp then spawnParts[i] = sp
		else warn("[RISK]", tableGroup.Name, "— missing Spawns" .. i) end
	end
	if #spawnParts < 5 then
		warn("[RISK]", tableGroup.Name, "— needs 5 SpawnN parts, found", #spawnParts); return
	end

	local tableGui, waitLabel = findTableGui(tableGroup)
	if tableGui  then tableGui.Enabled  = true   end
	if waitLabel then waitLabel.Text    = "PLAY!" end

	local tData = {
		tableGroup = tableGroup,
		seat       = seat,
		spawnParts = spawnParts,
		tableGui   = tableGui,
		waitLabel  = waitLabel,
		busy       = false,
	}

	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occ = seat.Occupant
		if not occ then return end
		local p = Players:GetPlayerFromCharacter(occ.Parent)
		if not p                  then return end
		if tData.busy             then return end
		if riskSessions[p.UserId] then return end

		tData.busy = true

		task.spawn(function()
			for i = 3, 1, -1 do
				if waitLabel then waitLabel.Text = tostring(i) end
				task.wait(1)
				local stillSeated = seat.Occupant ~= nil
					and Players:GetPlayerFromCharacter(seat.Occupant.Parent) == p
				if not stillSeated then
					tData.busy = false
					showTableGui(tData)
					return
				end
			end
			hideTableGui(tData)
			startRiskGame(p, tData)
		end)
	end)

	table.insert(riskTableList, tData)
	print("[RISK] Table ready:", tableGroup.Name)
end

-- ─── Game Flow ───────────────────────────────────────────────────────────────

startRiskGame = function(player, tData)
	if riskSessions[player.UserId] then return end

	local seat       = tData.seat
	local spawnParts = tData.spawnParts

	local seatLook = seat.CFrame.LookVector
	local yAngle   = math.atan2(-seatLook.X, -seatLook.Z)
	local caseRot  = CFrame.Angles(0, yAngle, 0) * FLAT

	local spawnCFs       = {}
	local spawnPositions = {}
	for i = 1, 5 do
		local pos         = spawnParts[i].Position + Vector3.new(0, SPAWN_Y, 0)
		spawnCFs[i]       = CFrame.new(pos) * caseRot
		spawnPositions[i] = pos
	end

	local sum = Vector3.new()
	for _, p in ipairs(spawnPositions) do sum = sum + p end
	local midPos        = sum / 5
	local overviewCamCF = computeOverviewCam(spawnPositions, seat.CFrame)

	local luck        = getPlayerLuck(player)
	local cashAmounts = pickCashAmounts(luck)
	local emptyIdx    = math.random(1, 5)
	local caseValues  = {}
	local citr        = 1
	for i = 1, 5 do
		if i == emptyIdx then
			caseValues[i] = 0
		else
			caseValues[i] = cashAmounts[citr]
			citr += 1
		end
	end

	print("[RISK] Game started |", player.Name,
		"| empty slot:", emptyIdx,
		"| values:", table.concat(caseValues, ", "),
		"| luck:", luck .. "%")

	local cases = {}
	for i = 1, 5 do
		local template = caseValues[i] > 0 and RS.Cases.GoodCase or RS.Cases.BadCase
		local cm       = spawnInSky(template, spawnCFs[i])
		cm.Name        = "RiskCase_" .. i .. "_" .. player.UserId
		setCaseNumber(cm, i)
		if caseValues[i] > 0 then
			setCashLabel(cm, caseValues[i])
		end
		cases[i] = cm
	end

	local session = {
		player        = player,
		tData         = tData,
		cases         = cases,
		caseValues    = caseValues,
		spawnCFs      = spawnCFs,
		openedCases   = {},
		bank          = 0,
		overviewCamCF = overviewCamCF,
		midPos        = midPos,
		stage         = "dropping",
		timerThread   = nil,
	}
	riskSessions[player.UserId] = session

	send(player, "Cases_HideUI")
	send(player, "Risk_UpdateBank", 0)

	-- Drop all 5 cases
	send(player, "Cases_CamWatchDrop", midPos)
	task.wait(0.85)

	local timeUntilLand = 0.15 + DROP_TIME
	send(player, "Cases_PlaySound",  SND_FALLING, true)
	send(player, "Cases_LandImpact", midPos, SND_LAND, timeUntilLand)

	for i = 1, 5 do
		local idx = i
		task.spawn(function() dropCase(cases[idx], spawnCFs[idx]) end)
		if i < 5 then task.wait(0.06) end
	end

	task.wait(DROP_TIME * 0.52)
	send(player, "Cases_CamTrackLand", midPos, DROP_TIME * 0.48)
	task.wait(DROP_TIME * 0.48 + 0.2)
	send(player, "Cases_StopSound", SND_FALLING)
	task.wait(0.5)

	send(player, "Cases_CamToPos", overviewCamCF, 1.0)
	task.wait(1.2)

	showPick(session)
end

-- ─────────────────────────────────────────────────────────────────────────────
showPick = function(session)
	session.stage = "picking"

	local available = {}
	for i = 1, 5 do
		if not session.openedCases[i] then table.insert(available, i) end
	end

	send(session.player, "Risk_ShowCasePick", available)
	send(session.player, "Cases_StartTimer",  30)

	session.timerThread = task.delay(30, function()
		if session.stage ~= "picking" then return end
		session.timerThread = nil
		local avail2 = {}
		for i = 1, 5 do
			if not session.openedCases[i] then table.insert(avail2, i) end
		end
		if #avail2 > 0 then
			handleCasePicked(session.player, avail2[math.random(#avail2)])
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
handleCasePicked = function(player, caseIndex)
	local session = riskSessions[player.UserId]
	if not session                    then return end
	if session.stage ~= "picking"     then return end
	if session.openedCases[caseIndex] then return end
	if caseIndex < 1 or caseIndex > 5 then return end

	if session.timerThread then task.cancel(session.timerThread); session.timerThread = nil end
	send(player, "Cases_StopTimer")
	send(player, "Risk_HideCasePick")
	session.stage = "opening"
	session.openedCases[caseIndex] = true

	local caseModel = session.cases[caseIndex]
	local amount    = session.caseValues[caseIndex]
	local caseName  = caseModel.Name

	send(player, "Cases_CamToCase", caseName, 1.0)
	task.wait(1.2)

	send(player, "Cases_PlaySound", SND_DRUMROLL, false)
	shakeCase(caseModel, 3.0)
	send(player, "Cases_PlaySound", SND_POOF, false)
	task.wait(0.08)
	send(player, "Cases_PlaySound", SND_OPEN, false)
	send(player, "Cases_OpenAndFreeze", caseName)
	task.wait(0.8)

	if amount == 0 then
		-- ── BUST ─────────────────────────────────────────────────────────────
		session.stage = "done"
		setBillboard(playerHead(player), "EMPTY! 💀", Color3.fromRGB(255, 60, 60))
		send(player, "Cases_PlaySound", SND_LOSE, false)
		task.wait(0.5)

		for i = 1, 5 do
			if not session.openedCases[i] then
				local idx = i
				task.spawn(function()
					task.wait(math.random() * 0.7)
					send(player, "Cases_PlaySound", SND_CASE_OPEN, false)
					send(player, "Cases_OpenAndFreeze", session.cases[idx].Name)
				end)
			end
		end
		task.wait(1.4)

		send(player, "Cases_ShowUI")
		send(player, "Risk_ShowResult", false, session.bank)  -- pass bank so client can show what was lost
		cleanupSession(player, false, 0)

	else
		-- ── CASH FOUND ───────────────────────────────────────────────────────
		session.bank += amount
		send(player, "Risk_UpdateBank", session.bank)

		local remaining = 0
		for i = 1, 5 do
			if not session.openedCases[i] then remaining += 1 end
		end

		if remaining == 1 then
			-- Auto-win: only the empty case is left
			session.stage = "done"
			setBillboard(playerHead(player), "SWEPT! 🎉", Color3.fromRGB(80, 255, 120))
			send(player, "Cases_PlaySound", SND_WIN, false)
			send(player, "Cases_Confetti")
			task.wait(0.5)
			for i = 1, 5 do
				if not session.openedCases[i] then
					send(player, "Cases_PlaySound", SND_CASE_OPEN, false)
					send(player, "Cases_OpenAndFreeze", session.cases[i].Name)
					break
				end
			end
			task.wait(0.9)
			send(player, "Cases_ShowUI")
			send(player, "Risk_ShowResult", true, session.bank)
			cleanupSession(player, true, session.bank)

		else
			-- Show cash-out decision
			session.stage = "cashout_prompt"
			send(player, "Cases_CamToPos", session.overviewCamCF, 0.8)
			task.wait(0.95)
			send(player, "Risk_ShowCashOut", amount, session.bank, remaining)
			send(player, "Cases_StartTimer", 20)

			session.timerThread = task.delay(20, function()
				if session.stage ~= "cashout_prompt" then return end
				session.timerThread = nil
				handleCashOutDecision(player, "keepgoing")
			end)
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
handleCashOutDecision = function(player, decision)
	local session = riskSessions[player.UserId]
	if not session                       then return end
	if session.stage ~= "cashout_prompt" then return end

	if session.timerThread then task.cancel(session.timerThread); session.timerThread = nil end
	send(player, "Cases_StopTimer")
	send(player, "Risk_HideCashOut")

	if decision == "cashout" then
		session.stage = "done"
		setBillboard(playerHead(player), "CASHED OUT! 💵", Color3.fromRGB(255, 215, 0))
		send(player, "Cases_PlaySound", SND_WIN, false)
		send(player, "Cases_Confetti")
		task.wait(0.5)
		send(player, "Cases_ShowUI")
		send(player, "Risk_ShowResult", true, session.bank)
		cleanupSession(player, true, session.bank)
	else
		send(player, "Cases_CamToPos", session.overviewCamCF, 0.5)
		task.wait(0.65)
		showPick(session)
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
cleanupSession = function(player, won, amount)
	local session = riskSessions[player.UserId]
	if not session then return end

	if DataHandler then
		if won and amount > 0 then
			DataHandler.AddCurrency(player, amount, "Cash")
			DataHandler.AddCurrency(player, 1, "Wins")
			DataHandler.AddCurrency(player, 1, "Streak")
		else
			DataHandler.SetCurrency(player, 0, "Streak")
		end
	end

	task.delay(1.5, function()
		local char = player.Character
		if not char then return end
		local h   = char:FindFirstChild("Humanoid")
		local hrp = char:FindFirstChild("HumanoidRootPart")
		local rSeat = session.tData.seat
		if rSeat then
			local sw = rSeat:FindFirstChild("SeatWeld")
			if sw then sw:Destroy() end
		end
		if hrp then
			for _, w in ipairs(hrp:GetChildren()) do
				if w:IsA("Weld") and w.Name == "SeatWeld" then w:Destroy() end
			end
		end
		if h then h.Sit = false; h.Jump = true end
		if rSeat and rSeat.Parent then
			rSeat.Disabled = false
		end
	end)

	task.delay(2.5, function()
		local char = player.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then hrp.CFrame = session.tData.seat.CFrame * CFrame.new(0, 3, 5) end
		send(player, "Cases_CamDirect3P")
	end)

	task.delay(6, function()
		clearBillboard(player)
		for i = 1, 5 do
			local cm = session.cases[i]
			if cm and cm.Parent then cm:Destroy() end
		end
		riskSessions[player.UserId] = nil
		session.tData.busy = false
		-- Ensure seat is unlocked for the next player
		if session.tData.seat and session.tData.seat.Parent then
			session.tData.seat.Disabled = false
		end
		showTableGui(session.tData)
		print("[RISK] Table", session.tData.tableGroup.Name, "reset")
	end)
end

-- ─── Remote listeners ────────────────────────────────────────────────────────

Network.onServer("Risk_CasePicked", function(player, caseIndex)
	handleCasePicked(player, tonumber(caseIndex))
end)

Network.onServer("Risk_CashOutDecision", function(player, decision)
	handleCashOutDecision(player, tostring(decision))
end)

-- ─── Init ────────────────────────────────────────────────────────────────────

if RISK_ENABLED then
	for _, tg in ipairs(RiskTablesFolder:GetChildren()) do
		if tg:IsA("Folder") or tg:IsA("Model") then
			task.spawn(function() initRiskTable(tg) end)
		end
	end
end

Players.PlayerRemoving:Connect(function(player)
	local session = riskSessions[player.UserId]
	if not session or session.stage == "done" then return end
	if session.timerThread then task.cancel(session.timerThread); session.timerThread = nil end
	for i = 1, 5 do
		local cm = session.cases[i]
		if cm and cm.Parent then cm:Destroy() end
	end
	riskSessions[player.UserId] = nil
	session.tData.busy = false
	if session.tData.seat and session.tData.seat.Parent then
		session.tData.seat.Disabled = false
	end
	showTableGui(session.tData)
	print("[RISK]", player.Name, "left mid-game — table", session.tData.tableGroup.Name, "reset")
end)

print("[RISK] RiskHandler ready |", #RiskTablesFolder:GetChildren(), "table(s) found")

return module