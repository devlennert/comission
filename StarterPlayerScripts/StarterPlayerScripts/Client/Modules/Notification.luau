local module = {}
local Player = game.Players.LocalPlayer
local PlayerGui =  Player.PlayerGui
local UI = PlayerGui:WaitForChild("UI")
local NotiFrame = UI.NotiFrame
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Network = require(ReplicatedStorage.Modules.Network)
local SoundModule = require(ReplicatedStorage.Modules.SoundModule)
local Animate = require(ReplicatedStorage.Modules.Animate)

function module.Notify(txt,txtType)
	local NotiLabel = NotiFrame.TextFrame:Clone()
	NotiLabel.Parent = NotiFrame
	if txtType == "Confirmation" then
		SoundModule.PlaySound("Noti")
		NotiLabel.TextLabel.TextColor3 =  Color3.new(0.108003, 1, 0.00204471)
		NotiLabel.Size = UDim2.new(0,0,0,0)
		Animate.EaseUISize(NotiLabel,UDim2.new(1.006, 0,0.265, 0),0.35,nil,function()
	
		task.spawn(function()
				task.wait(2.4)
				Animate.EaseUISize(NotiLabel,UDim2.new(0,0,0,0),0.35)
			end)
		end)	end
	if txtType == "Warning" then
		SoundModule.PlaySound("Error")
		NotiLabel.TextLabel.TextColor3 =  Color3.new(1, 0, 0.122103)
		NotiLabel.Size = UDim2.new(0,0,0,0)
		
		
		Animate.EaseUISize(NotiLabel,UDim2.new(1.006, 0,0.265, 0),0.35,nil,function()

			task.spawn(function()
				task.wait(2.4)
				Animate.EaseUISize(NotiLabel,UDim2.new(0,0,0,0),0.35)
			end)
		end)
			
			
		
	
		
	
	end
	NotiLabel.Visible = true
	NotiLabel.TextLabel.Text  = txt
end

--task.wait(3)
--module.Notify("HELLOOOO","Confirmation")

Network.onClient("Notify",function(txt,txtype)
	module.Notify(txt,txtype)
end)



return module
