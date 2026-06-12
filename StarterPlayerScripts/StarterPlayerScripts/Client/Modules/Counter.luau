local module = {}
local Player = game.Players.LocalPlayer
local PlayerGui = Player.PlayerGui
local TweenService = game:GetService("TweenService")
local activeTweens = {}


local function watchVal(Currency,txtLabel : TextLabel,Prefix,Suffix)
	for _,it : ValueBase in Player:GetDescendants() do
		if it:IsA("ValueBase") and it.Name == Currency then
			local function applyText()
				local formatted = it.Value
				if Prefix == nil and Suffix == nil then
					txtLabel.Text = formatted
				elseif Prefix then
					txtLabel.Text = Prefix..formatted
				elseif Suffix then
					txtLabel.Text = formatted..Suffix
				elseif Prefix and Suffix then
					txtLabel.Text = Prefix..formatted..Suffix
				end
			end
			applyText()
			it:GetPropertyChangedSignal("Value"):Connect(function()
				applyText()
				local gp = txtLabel.Parent and txtLabel.Parent.Parent
				if gp and gp:IsA("GuiObject") then
					local orig = gp.Size
					local factor = 1.15
					local goalUp = UDim2.new(orig.X.Scale * factor, orig.X.Offset * factor, orig.Y.Scale * factor, orig.Y.Offset * factor)
					local goalDown = orig
					if activeTweens[gp] then
						pcall(function() activeTweens[gp]:Cancel() end)
						activeTweens[gp] = nil
					end
					local t1 = TweenService:Create(gp, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = goalUp})
					local t2 = TweenService:Create(gp, TweenInfo.new(0.18, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {Size = goalDown})
					activeTweens[gp] = t1
					t1:Play()
					t1.Completed:Connect(function()
						activeTweens[gp] = t2
						t2:Play()
						t2.Completed:Connect(function()
							activeTweens[gp] = nil
						end)
					end)
				end
			end)
		end
	end
end

local function attachCounter(Currency,txtLabel : TextLabel,Prefix,Suffix)
	if not txtLabel then 
		print("not textlabel")
	end
	watchVal(Currency,txtLabel,Prefix,Suffix)
end

attachCounter("Cash",PlayerGui.UI.CashLabel,"$",nil)
attachCounter("Wins",PlayerGui.UI.WinsLabel,nil,nil)

return module
