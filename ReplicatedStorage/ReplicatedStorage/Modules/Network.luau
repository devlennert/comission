local Network = {}

-- Cache services & folders
local Replicated = game:GetService("ReplicatedStorage")
local Remotes    = Replicated:WaitForChild("Remotes")
Network.Events   = Remotes:WaitForChild("RemoteEvents")
Network.Functions= Remotes:WaitForChild("RemoteFunctions")

-- Define a new action (creates RemoteEvent & RemoteFunction if missing)
function Network.define(name)
	if not Network.Events:FindFirstChild(name) then
		Instance.new("RemoteEvent", Network.Events).Name = name
	end
	if not Network.Functions:FindFirstChild(name) then
		Instance.new("RemoteFunction", Network.Functions).Name = name
	end
end

-- CLIENT → SERVER (fire-and-forget)
function Network.send(action, ...)
	local evt = Network.Events:FindFirstChild(action)
	assert(evt, ("[%s] RemoteEvent missing"):format(action))
	evt:FireServer(...)
end

-- SERVER → CLIENT (single player)
function Network.sendToClient(player, action, ...)
	local evt = Network.Events:FindFirstChild(action)
	assert(evt, ("[%s] RemoteEvent missing"):format(action))
	evt:FireClient(player, ...)
end

-- SERVER → ALL CLIENTS
function Network.broadcast(action, ...)
	local evt = Network.Events:FindFirstChild(action)
	assert(evt, ("[%s] RemoteEvent missing"):format(action))
	evt:FireAllClients(...)
end

-- SERVER: handle send() from clients
function Network.onServer(action, handler)
	local evt = Network.Events:FindFirstChild(action)
	assert(evt, ("[%s] RemoteEvent missing"):format(action))
	evt.OnServerEvent:Connect(function(player, ...)
		handler(player, ...)
	end)
end

-- CLIENT: handle server sends
function Network.onClient(action, handler)
	local evt = Network.Events:FindFirstChild(action)
	assert(evt, ("[%s] RemoteEvent missing"):format(action))
	evt.OnClientEvent:Connect(handler)
end

-- CLIENT → SERVER (returns value)
function Network.request(action, ...)
	local fn = Network.Functions:FindFirstChild(action)
	assert(fn, ("[%s] RemoteFunction missing"):format(action))
	return fn:InvokeServer(...)
end

-- SERVER: handle request()
function Network.onServerInvoke(action, handler)
	local fn = Network.Functions:FindFirstChild(action)
	assert(fn, ("[%s] RemoteFunction missing"):format(action))
	fn.OnServerInvoke = function(player, ...)
		return handler(player, ...)
	end
end

-- CLIENT: handle server InvokeClient (rare)
function Network.onClientInvoke(action, handler)
	local fn = Network.Functions:FindFirstChild(action)
	assert(fn, ("[%s] RemoteFunction missing"):format(action))
	fn.OnClientInvoke = handler
end

return Network
