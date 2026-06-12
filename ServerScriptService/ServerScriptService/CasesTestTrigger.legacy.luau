local SSH     = game:GetService("ServerScriptService")
local RS      = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CasesHandler = require(SSH.Modules.CasesHandler)
local CashConfig   = require(RS.Modules.CashConfig)
local DataHandler  = require(SSH.Modules.DataHandler)
local Network      = require(RS.Modules.Network)

CasesHandler.Init()

local FLIP_X   = CFrame.Angles(math.pi, 0, 0)
local SIDE_ROT = CFrame.Angles(0, math.pi/2, 0)
local SND_TICK   = "99955064134003"
local SND_WINNER = "99873338511718"
local DEFAULT_JUMP_HEIGHT = 7.2
local DEFAULT_WALK_SPEED  = 16

local MODEL_DATA = {
	["1"]={flip=true},  ["2"]={flip=true},  ["3"]={flip=true},
	["4"]={flip=true},  ["5"]={flip=true},  ["6"]={flip=true},
	["7"]={flip=true},  ["8"]={flip=true},  ["9"]={flip=true},
	["10"]={side=true}, ["11"]={side=true}, ["12"]={side=true},
	["13"]={side=true}, ["14"]={flip=false}, ["15"]={flip=false},
	["16"]={flip=false},
}

local OP_MIN,      OP_MAX      = 7,  11
local SUPEROP_MIN, SUPEROP_MAX = 12, 16

local function pickWinner(combinedLuck, rollType)
	combinedLuck = combinedLuck or 0
	local entries = {}
	for name, entry in pairs(CashConfig) do
		table.insert(entries, {name=name, amount=entry.amount, weight=entry.weight})
	end
	table.sort(entries, function(a, b) return a.amount < b.amount end)
	local n = #entries
	local minIdx, maxIdx = 1, n
	if rollType == "op"      then minIdx, maxIdx = OP_MIN,      OP_MAX      end
	if rollType == "superOp" then minIdx, maxIdx = SUPEROP_MIN, SUPEROP_MAX end
	local luckFactor  = math.clamp(combinedLuck / 500, 0, 1)
	local totalBiased = 0
	local biased      = {}
	for i = minIdx, maxIdx do
		local rank = (i - minIdx) / math.max(maxIdx - minIdx, 1)
		-- shift so low tiers are penalised and high tiers are boosted
		local bw   = entries[i].weight * math.exp(luckFactor * (2 * rank - 1) * 3.0)
		biased[i]  = bw
		totalBiased += bw
	end
	local roll, cum = math.random() * totalBiased, 0
	for i = minIdx, maxIdx do
		cum += biased[i]
		if roll <= cum then return entries[i].name end
	end
	return entries[maxIdx].name
end

local function getRollType(presId, guesId)
	local pr = DataHandler.GetSessionRolls(presId)
	local gr = DataHandler.GetSessionRolls(guesId)
	if (pr.superOp or 0) > 0 or (gr.superOp or 0) > 0 then return "superOp" end
	if (pr.op     or 0) > 0 or (gr.op     or 0) > 0 then return "op"      end
	return nil
end

local function computeChance(targetName, combinedLuck, rollType)
	local CashConfig = require(RS.Modules.CashConfig)
	local entries = {}
	for name, entry in pairs(CashConfig) do
		table.insert(entries, {name=name, amount=entry.amount, weight=entry.weight})
	end
	table.sort(entries, function(a, b) return a.amount < b.amount end)
	local n = #entries
	local OP_MIN, OP_MAX = math.ceil(n * 0.5), n
	local SUPEROP_MIN, SUPEROP_MAX = math.ceil(n * 0.75), n
	local minIdx, maxIdx = 1, n
	if rollType == "op"      then minIdx, maxIdx = OP_MIN, OP_MAX end
	if rollType == "superOp" then minIdx, maxIdx = SUPEROP_MIN, SUPEROP_MAX end
	local luckFactor = math.clamp((combinedLuck or 0) / 500, 0, 1)
	local total, targetWeight = 0, 0
	for i = minIdx, maxIdx do
		local rank = (i - minIdx) / math.max(maxIdx - minIdx, 1)
		local bw = entries[i].weight * math.exp(luckFactor * (2 * rank - 1) * 3.0)
		total += bw
		if entries[i].name == targetName then targetWeight = bw end
	end
	if total == 0 then return 0 end
	return targetWeight / total * 100
end

local function doCashRoll(p1, p2, cashSpawn, cashFloorY, combinedLuck)
	local cashFolder = RS.Cash
	local allNames   = {}
	for _, m in ipairs(cashFolder:GetChildren()) do table.insert(allNames, m.Name) end

	local FILLER = 27
	local seq    = {}
	for _ = 1, FILLER do table.insert(seq, allNames[math.random(1, #allNames)]) end
	table.insert(seq, nil)

	local times = {}
	for _ = 1, 12 do table.insert(times, 0.07) end
	for _ = 1, 8  do table.insert(times, 0.15) end
	for _ = 1, 5  do table.insert(times, 0.30) end
	for _ = 1, 2  do table.insert(times, 0.55) end
	table.insert(times, 0)

	local spawnX, spawnZ = cashSpawn.Position.X, cashSpawn.Position.Z
	local current      = nil
	local winnerName   = nil
	local rollTypeUsed = nil
	local LOCK_AT      = FILLER

	for i = 1, #seq do
		if i == LOCK_AT then
			rollTypeUsed = getRollType(p1.UserId, p2.UserId)
			if rollTypeUsed then
				DataHandler.ConsumeOneRoll(p1.UserId, rollTypeUsed)
				DataHandler.ConsumeOneRoll(p2.UserId, rollTypeUsed)
			end
			winnerName = pickWinner(combinedLuck, rollTypeUsed)
			seq[#seq]  = winnerName
			DataHandler.SetRollLocked(p1.UserId, true)
			DataHandler.SetRollLocked(p2.UserId, true)
			if rollTypeUsed then
				local pr = DataHandler.GetSessionRolls(p1.UserId)
				local gr = DataHandler.GetSessionRolls(p2.UserId)
				Network.sendToClient(p1, "OPRolls_Update", pr.op or 0, pr.superOp or 0)
				Network.sendToClient(p2, "OPRolls_Update", gr.op or 0, gr.superOp or 0)
			end
		end

		local name = seq[i]
		if not name then
			local w = times[i] or 0.55
			if w > 0 then task.wait(w) end
			continue
		end

		if current then current:Destroy() end
		local tmpl = cashFolder:FindFirstChild(name)
		if tmpl then
			current = tmpl:Clone()
			current.Parent = workspace
			for _, p in ipairs(current:GetDescendants()) do
				if p:IsA("BasePart") then p.Anchored = true; p.CanCollide = false end
			end
			local d     = MODEL_DATA[name] or {flip=false}
			local rotCF = d.flip and FLIP_X or (d.side and SIDE_ROT or CFrame.new())
			current:PivotTo(CFrame.new(spawnX, cashFloorY, spawnZ) * rotCF)
			local bbCF, bbSize = current:GetBoundingBox()
			current:PivotTo(current:GetPivot() + Vector3.new(
				spawnX - bbCF.X,
				cashFloorY - (bbCF.Y - bbSize.Y / 2),
				spawnZ - bbCF.Z
			))
			if i < #seq then
				Network.sendToClient(p1, "Cases_PlaySound", SND_TICK, false)
				Network.sendToClient(p2, "Cases_PlaySound", SND_TICK, false)
			else
				Network.sendToClient(p1, "Cases_PlaySound", SND_WINNER, false)
				Network.sendToClient(p2, "Cases_PlaySound", SND_WINNER, false)
			end
		end

		local w = times[i] or 0.55
		if w > 0 then task.wait(w) end
	end

	task.wait(1.2)
	DataHandler.SetRollLocked(p1.UserId, false)
	DataHandler.SetRollLocked(p2.UserId, false)

	return current, winnerName, rollTypeUsed
end

local function setMovementLocked(player, locked)
	local char = player.Character; if not char then return end
	local h = char:FindFirstChild("Humanoid"); if not h then return end
	h.JumpHeight = locked and 0 or DEFAULT_JUMP_HEIGHT
	h.WalkSpeed  = locked and 0 or DEFAULT_WALK_SPEED
end

local function getChairLuck(player)
	local ChairInfo = require(RS.Modules.ChairInfo)
	local eq = player:FindFirstChild("EquippedChair"); if not eq then return 0 end
	local data = ChairInfo[eq.Value]
	return data and (data.Luck or 0) or 0
end

local playerToReset = {}

CasesHandler.onGameEnd = function(presenter, guesser)
	if presenter then setMovementLocked(presenter, false) end
	if guesser   then setMovementLocked(guesser,   false) end
	local resetFn = (presenter and playerToReset[presenter.UserId])
		or (guesser and playerToReset[guesser.UserId])
	if presenter then playerToReset[presenter.UserId] = nil end
	if guesser   then playerToReset[guesser.UserId]   = nil end
	if resetFn   then resetFn() end
end

local function initTable(tg)
	local seat1      = tg:WaitForChild("Seat1")
	local seat2      = tg:WaitForChild("Seat2")
	local seat1CF    = seat1.CFrame
	local seat2CF    = seat2.CFrame
	local cashSpawn  = tg:WaitForChild("CashSpawn")
	local tableGui   = tg.table:WaitForChild("TableGui")
	local waitLabel  = tableGui:WaitForChild("WaitingLabel")
	local cashFloorY = cashSpawn.Position.Y + cashSpawn.Size.Y / 2

	local camPart    = tg:FindFirstChild("CameraPart")
	local tableCamCF = camPart and camPart.CFrame

	local cooldown   = false
	local gameGen    = 0
	local seatChairs = {}
		-- ── Stale object cleanup ──────────────────────────────────────────────────
		local function cleanupStaleGameObjects()
			local tablePos  = cashSpawn.Position
			local RANGE     = 35
			local cashNames = {}
			for _, m in ipairs(RS.Cash:GetChildren()) do cashNames[m.Name] = true end
			for _, obj in ipairs(workspace:GetChildren()) do
				local n = obj.Name
				if n:match("^BriefcaseLeft") or n:match("^BriefcaseRight") then
					local ok, pos = pcall(function() return obj:GetPivot().Position end)
					if ok and (pos - tablePos).Magnitude < RANGE then
						print("[CASES] Cleaning stale case:", n)
						obj:Destroy()
					end
				elseif cashNames[n] then
					local ok, pos = pcall(function() return obj:GetPivot().Position end)
					if ok and (pos - tablePos).Magnitude < RANGE then
						print("[CASES] Cleaning stale cash model:", n)
						obj:Destroy()
					end
				end
			end
		end


	local function updateWaiting()
		local count = 0
		if seat1.Occupant then count += 1 end
		if seat2.Occupant then count += 1 end
		if count > 0 then
			waitLabel.Text   = count .. "/2"
			tableGui.Enabled = true
		else
			tableGui.Enabled = false
		end
	end

	local function onOccupantChanged(seat)
		local player  = seat.Occupant and Players:GetPlayerFromCharacter(seat.Occupant.Parent)
		local existing = seatChairs[seat]
		-- Always clean up the old chair model when occupant changes
		if existing then CasesHandler.RemoveChair(existing, seat); seatChairs[seat] = nil end
		-- Only apply a new chair if we're not mid-game
		if player and not cooldown then
			seatChairs[seat] = CasesHandler.ApplyChair(player, seat, seat == seat1 and seat1CF or seat2CF)
		end
	end

	local function watchForForfeit(p1, p1Seat, p2, p2Seat)
		local c1, c2
		c1 = p1Seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			if not p1Seat.Occupant and cooldown then
				CasesHandler.HandlePlayerLeft(p1)
				c1:Disconnect(); c2:Disconnect()
			end
		end)
		c2 = p2Seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			if not p2Seat.Occupant and cooldown then
				CasesHandler.HandlePlayerLeft(p2)
				c1:Disconnect(); c2:Disconnect()
			end
		end)
	end

	local function tryStart()
		updateWaiting()
		if cooldown then return end
		cooldown = true
		local occ1, occ2 = seat1.Occupant, seat2.Occupant
		if not occ1 or not occ2 then cooldown = false; return end
		local p1 = Players:GetPlayerFromCharacter(occ1.Parent)
		local p2 = Players:GetPlayerFromCharacter(occ2.Parent)
		if not p1 or not p2 or p1 == p2 then cooldown = false; return end

		local presenter, presenterSeat, guesser, guesserSeat
		if math.random() > 0.5 then
			presenter=p1; presenterSeat=seat1; guesser=p2; guesserSeat=seat2
		else
			presenter=p2; presenterSeat=seat2; guesser=p1; guesserSeat=seat1
		end

		task.spawn(function()
			gameGen += 1
			local myGen = gameGen

			for i = 5, 1, -1 do
				if not seat1.Occupant or not seat2.Occupant then
					Network.sendToClient(presenter, "OPRolls_HideButtons")
					Network.sendToClient(guesser,   "OPRolls_HideButtons")
					if seatChairs[seat1] then CasesHandler.RemoveChair(seatChairs[seat1], seat1); seatChairs[seat1] = nil end
					if seatChairs[seat2] then CasesHandler.RemoveChair(seatChairs[seat2], seat2); seatChairs[seat2] = nil end
					if seat1.Parent then seat1.Disabled = false end
					if seat2.Parent then seat2.Disabled = false end
					cooldown = false; updateWaiting(); return
				end
				waitLabel.Text = tostring(i)
				task.wait(1)
			end
			if not seat1.Occupant or not seat2.Occupant then
				Network.sendToClient(presenter, "OPRolls_HideButtons")
				Network.sendToClient(guesser,   "OPRolls_HideButtons")
				if seatChairs[seat1] then CasesHandler.RemoveChair(seatChairs[seat1], seat1); seatChairs[seat1] = nil end
				if seatChairs[seat2] then CasesHandler.RemoveChair(seatChairs[seat2], seat2); seatChairs[seat2] = nil end
				if seat1.Parent then seat1.Disabled = false end
				if seat2.Parent then seat2.Disabled = false end
				cooldown = false; updateWaiting(); return
			end

			setMovementLocked(presenter, true)
			setMovementLocked(guesser,   true)

			watchForForfeit(presenter, presenterSeat, guesser, guesserSeat)

			local function resetTable()
				gameGen += 1
				-- Clear stale chair references so next game starts clean
				seatChairs[seat1] = nil
				seatChairs[seat2] = nil
				-- Ensure seats are not left disabled
				if seat1.Parent then seat1.Disabled = false end
				if seat2.Parent then seat2.Disabled = false end
				cooldown = false
				tryStart()
			end
			playerToReset[presenter.UserId] = resetTable
			playerToReset[guesser.UserId]   = resetTable

			DataHandler.FlushPendingBoughtNotifs(presenter, guesser)

			local presRolls = DataHandler.GetSessionRolls(presenter.UserId)
			local guesRolls = DataHandler.GetSessionRolls(guesser.UserId)
			Network.sendToClient(presenter, "OPRolls_ShowButtons")
			Network.sendToClient(guesser,   "OPRolls_ShowButtons")
			Network.sendToClient(presenter, "OPRolls_Update", presRolls.op, presRolls.superOp)
			Network.sendToClient(guesser,   "OPRolls_Update", guesRolls.op, guesRolls.superOp)

			Network.sendToClient(presenter, "Cases_CamToTableCam", tableCamCF)
			Network.sendToClient(guesser,   "Cases_CamToTableCam", tableCamCF)
			task.wait(1.4)

			tableGui.Enabled = false
			local combinedLuck = getChairLuck(presenter) + getChairLuck(guesser)

			cleanupStaleGameObjects()
			local cashModel, winnerName, rollTypeUsed =
				doCashRoll(presenter, guesser, cashSpawn, cashFloorY, combinedLuck)

			-- If either player disconnected DURING the roll animation, destroy the
			-- cash model immediately (no session exists yet so HandlePlayerLeft missed it)
			local presenterGone = not Players:FindFirstChild(presenter.Name)
			local guesserGone   = not Players:FindFirstChild(guesser.Name)
			if presenterGone or guesserGone then
				if cashModel and cashModel.Parent then cashModel:Destroy() end
				-- Unlock the surviving player if any
				if not presenterGone then
					setMovementLocked(presenter, false)
					pcall(function() CasesHandler.HandlePlayerLeft(presenter) end)
				end
				if not guesserGone then
					setMovementLocked(guesser, false)
					pcall(function() CasesHandler.HandlePlayerLeft(guesser) end)
				end
				if seat1.Parent then seat1.CFrame = seat1CF; seat1.Disabled = false end
				if seat2.Parent then seat2.CFrame = seat2CF; seat2.Disabled = false end
				seatChairs[seat1] = nil
				seatChairs[seat2] = nil
				cooldown = false
				return
			end

			-- Update the Percentage label to reflect actual luck-adjusted odds
			if cashModel then
				local chance = computeChance(winnerName, combinedLuck, rollTypeUsed)
				local pctText
				if chance >= 1 then
					pctText = math.floor(chance + 0.5) .. "%"
				elseif chance >= 0.1 then
					pctText = string.format("%.1f%%", chance)
				else
					pctText = string.format("%.2f%%", chance)
				end
				for _, gui in ipairs(cashModel:GetDescendants()) do
					if gui:IsA("TextLabel") and gui.Name == "Percentage" then
						gui.Text = pctText
					end
				end
			end

			Network.sendToClient(presenter, "OPRolls_HideButtons")
			Network.sendToClient(guesser,   "OPRolls_HideButtons")

			local session = CasesHandler.SpawnCases(
				presenter, guesser, presenterSeat, guesserSeat, cashModel,
				seatChairs[presenterSeat], seatChairs[guesserSeat])
			if session then CasesHandler.PlayCaseReveal(session) end

			task.wait(90)
			if cooldown and myGen == gameGen then
				setMovementLocked(presenter, false)
				setMovementLocked(guesser,   false)
				-- Force cleanup of cases/cash that session cleanup would normally handle
				CasesHandler.HandlePlayerLeft(presenter)
				CasesHandler.HandlePlayerLeft(guesser)
				-- Snap seats back to original CFrames so they don't drift
				if seat1.Parent then seat1.CFrame = seat1CF; seat1.Disabled = false end
				if seat2.Parent then seat2.CFrame = seat2CF; seat2.Disabled = false end
				seatChairs[seat1] = nil
				seatChairs[seat2] = nil
				cooldown = false
				tryStart()
			end
		end)
	end

	seat1:GetPropertyChangedSignal("Occupant"):Connect(function() onOccupantChanged(seat1); tryStart() end)
	seat2:GetPropertyChangedSignal("Occupant"):Connect(function() onOccupantChanged(seat2); tryStart() end)
	updateWaiting()
end

local tablesFolder = workspace:WaitForChild("Map"):WaitForChild("Tables")
for _, tg in ipairs(tablesFolder:GetChildren()) do
	if tg:IsA("Model") and tg.Name == "TableGroup" then
		task.spawn(function() initTable(tg) end)
	end
end

Players.PlayerRemoving:Connect(function(player)
	CasesHandler.HandlePlayerLeft(player)
	playerToReset[player.UserId] = nil
end)
