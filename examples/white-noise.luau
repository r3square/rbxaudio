local rbxaudio = require(script.rbxaudio).new()
rbxaudio:set_channel_count(1) -- set to 1 for mono, set to 2 for stereo
rbxaudio:initialize()

game:GetService("RunService").RenderStepped:Connect(function()
	
	local c = rbxaudio:get_clock()
	local buf = {}
	
	for channel_i = 1, rbxaudio:get_channel_count() do
		
		buf[channel_i] = {}
		
		for i = 1, rbxaudio:get_buffer_size() do
			buf[channel_i][i] = math.random() * 2 - 1
		end
		
	end;
	
	rbxaudio:update_buffer(buf, c)
	
end)
