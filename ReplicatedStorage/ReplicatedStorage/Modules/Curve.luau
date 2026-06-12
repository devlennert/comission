-- BezierCurve Module
-- Supports both Quadratic and Cubic Bezier curves for Parts and UI

local BezierCurve = {}

-- Quadratic Bezier (3 points: start, control, end)
function BezierCurve.QuadraticPosition(t, p0, p1, p2)
	local it = 1 - t
	return it * it * p0 + 2 * it * t * p1 + t * t * p2
end

-- Cubic Bezier (4 points: start, control1, control2, end)
function BezierCurve.CubicPosition(t, p0, p1, p2, p3)
	local it = 1 - t
	return it * it * it * p0 + 3 * it * it * t * p1 + 3 * it * t * t * p2 + t * t * t * p3
end

-- Helper: Convert UDim2 to Vector2 for calculations
local function UDim2ToVector2(udim)
	return Vector2.new(udim.X.Scale, udim.Y.Scale)
end

-- Helper: Convert Vector2 back to UDim2 with offsets
local function Vector2ToUDim2(vec, offsetX, offsetY)
	return UDim2.new(vec.X, offsetX or 0, vec.Y, offsetY or 0)
end

-- Animate a Part along a Quadratic Bezier curve
function BezierCurve.AnimatePartQuadratic(part, startPos, controlPos, endPos, duration, callback)
	local startTime = tick()
	local connection

	connection = game:GetService("RunService").Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local t = math.min(elapsed / duration, 1)

		part.CFrame = CFrame.new(BezierCurve.QuadraticPosition(t, startPos, controlPos, endPos))

		if t >= 1 then
			connection:Disconnect()
			if callback then callback() end
		end
	end)

	return connection
end

-- Animate a Part along a Cubic Bezier curve
function BezierCurve.AnimatePartCubic(part, startPos, control1Pos, control2Pos, endPos, duration, callback)
	local startTime = tick()
	local connection

	connection = game:GetService("RunService").Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local t = math.min(elapsed / duration, 1)

		part.CFrame = CFrame.new(BezierCurve.CubicPosition(t, startPos, control1Pos, control2Pos, endPos))

		if t >= 1 then
			connection:Disconnect()
			if callback then callback() end
		end
	end)

	return connection
end

-- Animate UI element along a Quadratic Bezier curve
function BezierCurve.AnimateUIQuadratic(uiElement, startPos, controlPos, endPos, duration, callback)
	local startTime = tick()
	local connection

	-- Convert UDim2 to Vector2 for math, but preserve offsets
	local startVec = UDim2ToVector2(startPos)
	local controlVec = UDim2ToVector2(controlPos)
	local endVec = UDim2ToVector2(endPos)

	-- Store offsets (we'll interpolate these separately)
	local startOffsetX, startOffsetY = startPos.X.Offset, startPos.Y.Offset
	local endOffsetX, endOffsetY = endPos.X.Offset, endPos.Y.Offset

	connection = game:GetService("RunService").RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		local t = math.min(elapsed / duration, 1)

		-- Calculate position using Vector2
		local pos = BezierCurve.QuadraticPosition(t, startVec, controlVec, endVec)

		-- Lerp the offsets
		local offsetX = startOffsetX + (endOffsetX - startOffsetX) * t
		local offsetY = startOffsetY + (endOffsetY - startOffsetY) * t

		uiElement.Position = Vector2ToUDim2(pos, offsetX, offsetY)

		if t >= 1 then
			connection:Disconnect()
			if callback then callback() end
		end
	end)

	return connection
end

-- Animate UI element along a Cubic Bezier curve
function BezierCurve.AnimateUICubic(uiElement, startPos, control1Pos, control2Pos, endPos, duration, callback)
	local startTime = tick()
	local connection

	-- Convert UDim2 to Vector2 for math
	local startVec = UDim2ToVector2(startPos)
	local control1Vec = UDim2ToVector2(control1Pos)
	local control2Vec = UDim2ToVector2(control2Pos)
	local endVec = UDim2ToVector2(endPos)

	-- Store offsets
	local startOffsetX, startOffsetY = startPos.X.Offset, startPos.Y.Offset
	local endOffsetX, endOffsetY = endPos.X.Offset, endPos.Y.Offset

	connection = game:GetService("RunService").RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		local t = math.min(elapsed / duration, 1)

		-- Calculate position using Vector2
		local pos = BezierCurve.CubicPosition(t, startVec, control1Vec, control2Vec, endVec)

		-- Lerp the offsets
		local offsetX = startOffsetX + (endOffsetX - startOffsetX) * t
		local offsetY = startOffsetY + (endOffsetY - startOffsetY) * t

		uiElement.Position = Vector2ToUDim2(pos, offsetX, offsetY)

		if t >= 1 then
			connection:Disconnect()
			if callback then callback() end
		end
	end)

	return connection
end

-- Generate points along a curve (useful for visualization or path following)
function BezierCurve.GenerateQuadraticPoints(p0, p1, p2, numPoints)
	local points = {}
	for i = 0, numPoints do
		local t = i / numPoints
		table.insert(points, BezierCurve.QuadraticPosition(t, p0, p1, p2))
	end
	return points
end

function BezierCurve.GenerateCubicPoints(p0, p1, p2, p3, numPoints)
	local points = {}
	for i = 0, numPoints do
		local t = i / numPoints
		table.insert(points, BezierCurve.CubicPosition(t, p0, p1, p2, p3))
	end
	return points
end

return BezierCurve

--a.AnimateUIQuadratic(script.Parent,UDim2.new(0.05,0,0.88,0),UDim2.new(0.6,0,0,0),UDim2.new(0.9,0,0.88,0),1)
--b.Pulse(script.Parent,0.5,0.1,50)
--b.Shake(script.Parent,15,0.5)
--b.PopIn(script.Parent,1)
--b.EaseUIRotation(script.Parent,15,0.2)
--b.EaseTransparency(
--	script.Parent,
--	1,
--	0.3,
--	b.Easing.OutQuad
--)
--b.Wobble(script.Parent,10,1,2)
--b.ShakeCamera(workspace.CurrentCamera, 2, 0.5)