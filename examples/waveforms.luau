
-- change these values on the explorer while it's running

local frequency = Instance.new("NumberValue", workspace)
frequency.Name = "frequency"
frequency.Value = 440

local amplitude = Instance.new("NumberValue", workspace)
amplitude.Name = "amplitude"
amplitude.Value = 1

-- if the audio sounds bad change the sync value between 0 and 1 until it sounds decent
-- it will gradually desync depending on how stable your pc is
local sync = Instance.new("NumberValue", workspace)
sync.Name = "sync"

local waveform = Instance.new("StringValue", workspace)
waveform.Name = "waveform"
waveform.Value = "sine" -- can be "square", "sawtooth", "triangle" or "sine"

-- actual program

local rbxaudio = require(script.rbxaudio).new()
rbxaudio:initialize()

game:GetService("RunService").RenderStepped:Connect(function()
	
	local c = rbxaudio:get_clock()
	local buf = {}
	
	for i = 1, rbxaudio:get_buffer_size() do
		
		local t = c + (i - 1) / rbxaudio:get_sample_rate()
		
		if waveform.Value == "sine" then
			
			buf[i] = math.sin(t * frequency.Value * 2 * math.pi) * amplitude.Value
			
		elseif waveform.Value == "square" then
			
			buf[i] = amplitude.Value
			if t * frequency.Value % 1 > .5 then
				buf[i] = -amplitude.Value
			end
			
		elseif waveform.Value == "sawtooth" then
			
			buf[i] = ((t * frequency.Value % 1) * 2 - 1) * amplitude.Value
			
		elseif waveform.Value == "triangle" then

			buf[i] = (2 * math.abs(2 * (t * frequency.Value % 1) - 1) - 1) * amplitude.Value
			
		else
			buf[i] = 0
		end
		
	end
	
	rbxaudio:set_sync(sync.Value)
	rbxaudio:update_buffer(buf, c)
	
end)
