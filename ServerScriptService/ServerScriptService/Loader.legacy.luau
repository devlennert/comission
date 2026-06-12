local ok2, modules = pcall(function()
	for i,module in script.Parent.Modules:GetChildren() do
		print(module)
		if module:IsA("ModuleScript") then
			
			task.spawn(function()
				local module2 = require(module)
				if module.Name == "Leaderboard" then
					module2.Init(require(script.Parent.Modules.DataHandler))
				elseif module.Name == "CasesHandler" then
					module2.Init()
				end
			end)
		end
	end
	return script.Parent.Modules:GetChildren()
end)