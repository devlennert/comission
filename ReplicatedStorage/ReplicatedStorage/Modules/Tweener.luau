local TweenService = game:GetService("TweenService")

local module = {}

function module:Tween(obj : Instance,tweeninfo : TweenInfo,goal,yield : boolean)
	if obj and tweeninfo and goal then
		local function Tween()
			local tween = TweenService:Create(obj,tweeninfo,goal)
			tween:Play()

			if not yield then
				tween.Completed:Connect(function()
					tween:Destroy()
					tween = nil
				end)
				
				return tween
			else
				tween.Completed:Wait()
				tween:Destroy()
				tween = nil
			end
		end

		local tween = Tween()
		return tween
	end
end

return module
