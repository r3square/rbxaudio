--[[

rbxaudio v0.3
this module allows you to create an audio buffer inside of roblox (even though you're not supposed to)

don't expect this module to be entirely readable
i was experimenting a lot while making this and there's a lot of hackiness going on
feel free to contribute

]]

local render_stepped = game:GetService("RunService").RenderStepped
local http_service = game:GetService("HttpService")

local master_assets = {
	-- desired_buffer_size = 1024 sample_rate = 24000 print(math.ceil(desired_buffer_size/(sample_rate/1000)) * math.floor(sample_rate/1000))
	-- ^--- run this on the command line to get the nearest possible buffer size for a given sample rate

	[24000] = {
		id = "rbxasset://sounds/master1.wav"; -- change this id so that it uses assets/master1.wav
		buffer_size = 1056; -- dont touch
		speed = 1; -- dont touch either
	};
}

local master_minimum_delay = 0.001

local channel_isolation_angle = 34.5 -- 34.5 seems to be the most optimal angle to prevent leaking into the other channel
local channel_distance = 512 -- should be far enough for roblox to consider it as a mono sound played in 3D space
local channel_max_volume = 0.35 -- max volume before it starts saturating and causing issues
local channel_attenuation = {
	[0] = 1;
	[math.huge] = 1;
}

local function connect_wire(source, target, name, parent)

	local wire = Instance.new("Wire")
	wire.SourceInstance = source
	wire.TargetInstance = target
	wire.Name = name or target.Name .. "_wire"
	wire.Parent = parent or source

	return wire

end

local rbxaudio = {}
rbxaudio.__index = rbxaudio

function rbxaudio.new()

	local self = setmetatable({}, rbxaudio)

	self.initialized = false
	self.parent = game:GetService("SoundService")

	return self

end

function rbxaudio:set_samplerate(new_samplerate)

	if self.initialized then
		error("Cannot set sample rate while initialized")
	end

	local asset = master_assets[new_samplerate]
	if asset == nil then
		error("Unsupported sample rate: "..tostring(new_samplerate))
	end

	self.master_samplerate = new_samplerate

	return new_samplerate

end

function rbxaudio:set_channel_count(new_channel_count)

	if self.initialized then
		error("Cannot set channel count while initialized")
	end

	if new_channel_count <= 0 then
		error("are you stupid")
	end

	if new_channel_count ~= 1 and new_channel_count ~= 2 then
		error("Invalid channel count, must either be 1 (Mono) or 2 (Stereo)")
	end

	self.channel_count = new_channel_count

	return new_channel_count

end

function rbxaudio:get_channel_count()

	return self.channel_count

end

function rbxaudio:get_sample_rate()

	return self.master_samplerate

end

function rbxaudio:set_parent(new_parent)

	self.parent = new_parent

	if self.folder then

		self.folder.Parent = new_parent

	end

end

function rbxaudio:set_output(new_output)

	if self.initialized then error("Cannot change output while initialized") end

	self.output = new_output

end

function rbxaudio:is_initialized()

	return self.initialized

end

function rbxaudio:get_clock(dt)

	if not self.initialized then
		warn("Cannot get clock if not initialized")
		return 0
	end

	return os.clock()

end

function rbxaudio:get_buffer_size()

	if not self.initialized then
		warn("Cannot get buffer size if not initialized")
		return 0
	end

	local master_asset_data = self.master_asset_data
	local buffer_size = master_asset_data.buffer_size

	return buffer_size

end

function rbxaudio:get_sample_index_from_clock(clock)

	if not self.initialized then
		warn("Cannot get sample index if not initialized")
		return 0
	end

	local sample_rate = self.master_samplerate
	local buffer_size = self:get_buffer_size()

	return math.floor(((clock) * sample_rate) % buffer_size)

end

function rbxaudio:set_sync(new_sync)
	self.sync = new_sync
end

function rbxaudio:update_buffer(new_buffer, clock)

	if not self.initialized then
		warn("Cannot update buffer if not initialized")
		return
	end

	if not clock then
		warn("Clock is needed to update buffer")
		return
	end

	debug.profilebegin("rbxaudio_upd")

	if type(new_buffer[1]) ~= "table" then
		new_buffer = {new_buffer}
	end

	local channels = self.channels
	local buffer_size = self.master_asset_data.buffer_size

	local offset = self:get_sample_index_from_clock(clock) + math.round(self.sync * buffer_size)

	for channel_id, channel in pairs(channels) do

		local channel_samples = channel.samples
		local new_samples = new_buffer[channel_id] or new_buffer[1]

		for index = 0, buffer_size - 1 do

			local actual_index = (index + offset) % buffer_size

			local new_value = ((new_samples[index + 1] or 0) + 1) * 3/2
			channel_samples[actual_index].Volume = new_value

		end

	end

	debug.profileend()

end

function rbxaudio:get_master_position(index, asset, master_samplerate, clock)

	local master_length = asset.buffer_size / master_samplerate
	local master_offset = (index + 1/2) / master_samplerate
	local master_position = (master_length - master_offset + clock) % master_length

	return master_position * asset.speed

end

function rbxaudio:initialize()
	
	print("initializing rbxaudio...")
	
	local init_start = os.clock()

	if self.initialized then
		warn("Cannot initialize if already initialized")
		return
	end

	-- constants

	local channel_count = self.channel_count or self:set_channel_count(1)

	local master_samplerate = self.master_samplerate or self:set_samplerate(24000)

	local master_sample_count = master_minimum_delay * master_samplerate
	local master_asset_data = master_assets[master_samplerate]

	local master_asset = master_asset_data.id
	local master_buffersize = master_asset_data.buffer_size
	local master_asset_speed = master_asset_data.speed
	local master_length = master_buffersize / master_samplerate -- length in seconds for a single loop

	if master_sample_count > 64 then -- normally this shouldn't happen unless the master sample rate is higher than 64khz
		error("Maximum master sample count exceeded (maybe sample rate is too high?)")
	end

	-- create main folder

	local main_folder = Instance.new("Folder")
	main_folder.Name = "rbxaudio_buf"

	local master_folder = Instance.new("Folder")
	master_folder.Name = "master"
	master_folder.Parent = main_folder

	local linked_folder = Instance.new("Folder")
	linked_folder.Name = "linked"
	linked_folder.Parent = main_folder

	local channels_folder = Instance.new("Folder")
	channels_folder.Name = "channels"
	channels_folder.Parent = main_folder

	self.folder = main_folder

	-- make output if not defined

	local final_fader = Instance.new("AudioFader")
	final_fader.Volume = 0
	final_fader.Name = "final_fader"
	final_fader.Parent = main_folder

	local output = self.output
	if not output then

		output = Instance.new("AudioDeviceOutput")
		output.Name = "output"
		output.Parent = main_folder

		connect_wire(final_fader, output)

		self:set_output(output)

	end

	-- create channel entries

	local channels = {}
	local audio_interaction_group = "RBXAUDIO-" .. http_service:GenerateGUID(false)

	local channel_listener_part = Instance.new("Part")
	channel_listener_part.Transparency = .5
	channel_listener_part.Color = Color3.fromRGB(0, 155, 255)
	channel_listener_part.CFrame = CFrame.identity
	channel_listener_part.Anchored = true
	channel_listener_part.CanCollide = false
	channel_listener_part.Size = Vector3.new(1,1,1)
	channel_listener_part.Name = "channel_listener_part"
	channel_listener_part.Parent = channels_folder

	local channel_listener = Instance.new("AudioListener")
	channel_listener.AudioInteractionGroup = audio_interaction_group
	channel_listener.Name = "channel_listener"
	channel_listener.Parent = channel_listener_part

	local is_mono = channel_count == 1

	for channel_id = 1, channel_count do

		local channel_data = {}

		-- determine channel name

		local channel_name = "Mono"
		if not is_mono then
			channel_name = channel_id == 1 and "Stereo Left" or "Stereo Right"
		end

		-- determine channel angle

		local channel_angle = 0
		if not is_mono then
			channel_angle = channel_id == 1 and -channel_isolation_angle or channel_isolation_angle
		end

		-- make folder

		local channel_folder = Instance.new("Folder")
		channel_folder.Name = channel_name
		channel_folder.Parent = channels_folder

		-- make fader

		local channel_fader = Instance.new("AudioFader")
		channel_fader.Name = "channel_fader"
		channel_fader.Volume = channel_max_volume
		channel_fader.Parent = channel_folder

		channel_data.fader = channel_fader

		-- make channel emitter

		local channel_emitter_part = Instance.fromExisting(channel_listener_part)
		channel_emitter_part.Color = Color3.fromRGB(255, 155, 0)
		channel_emitter_part.Name = "channel_emitter_part"
		channel_emitter_part.Parent = channel_folder

		channel_emitter_part.CFrame = channel_listener_part.CFrame * CFrame.new(
			math.sin(math.rad(channel_angle)) * channel_distance,
			0,
			-math.cos(math.rad(channel_angle)) * channel_distance
		)

		local channel_emitter = Instance.new("AudioEmitter")
		channel_emitter.Name = "channel_emitter"
		channel_emitter.AudioInteractionGroup = audio_interaction_group
		channel_emitter:SetDistanceAttenuation(channel_attenuation)
		channel_emitter.Parent = channel_emitter_part

		connect_wire(channel_fader, channel_emitter)

		channel_data.emitter = channel_emitter

		-- done

		channels[channel_id] = channel_data

	end

	-- connect channel listener to final fader

	connect_wire(channel_listener, final_fader)

	-- create master samples

	local samples = {}
	local master_samples = {}

	for i = 0, master_sample_count - 1 do -- i hate lua

		local master_sample = Instance.new("AudioPlayer")
		master_sample.PlaybackSpeed = master_asset_speed
		master_sample.AssetId = master_asset
		master_sample.Looping = true
		master_sample.Name = "master_sample_" .. i
		master_sample.Parent = master_folder

		master_samples[i] = master_sample
		samples[i] = master_sample

	end

	-- create linked samples

	local first_linked_sample
	local linked_samples = {}
	local linked_sample_count_per_master = master_buffersize / master_sample_count
	for master_index, master_sample in pairs(master_samples) do

		local last_linked_sample = master_sample
		local linked_offset = master_index * linked_sample_count_per_master

		for i = master_index + master_sample_count, master_buffersize - 1, master_sample_count do

			local linked_sample = Instance.new("AudioEcho")
			linked_sample.DelayTime = master_minimum_delay
			linked_sample.DryLevel = -80
			linked_sample.Feedback = 0
			linked_sample.Name = "linked_sample_" .. i
			linked_sample.Parent = linked_folder

			connect_wire(last_linked_sample, linked_sample, "link_wire")

			last_linked_sample = linked_sample

			linked_samples[i] = linked_sample
			samples[i] = linked_sample

		end

	end

	-- create channel samples

	for channel_id, channel in pairs(channels) do

		local channel_sample_entry = channel.fader
		if not channel_sample_entry then error("NO FADER FOUND IN CHANNEL") end

		local channel_samples = {}

		for i, sample in pairs(samples) do

			local channel_sample = Instance.new("AudioFader")
			channel_sample.Name = "channelsample_" .. channel_id
			channel_sample.Volume = 1
			channel_sample.Parent = sample

			connect_wire(channel_sample, channel_sample_entry)
			connect_wire(sample, channel_sample, "sample_wire", channel_sample)

			channel_samples[i] = channel_sample

		end

		channel.samples = channel_samples

	end

	-- parent the main folder

	main_folder.Parent = self.parent

	do
		local wait_start = os.clock()
		local warned = false

		repeat

			render_stepped:Wait()
			if not warned and os.clock() - wait_start >= 5 then
				warn("seems like the asset is still not loaded... are you sure the id is correct?")
				warned = true
			end

		until master_samples[0].IsReady
	end

	-- initialize all of the master samples

	do
		local sync_success = false

		local sync_analyzer = Instance.new("AudioAnalyzer")
		sync_analyzer.Name = "sync_analyzer"
		sync_analyzer.Parent = main_folder

		local sync_reference = channels[1].fader
		local sync_reference_previous_volume = sync_reference.Volume

		local sync_attempts = 0

		sync_reference.Volume = 1

		local sync_wire = connect_wire(sync_reference, sync_analyzer)

		while not sync_success do

			sync_attempts += 1

			if sync_attempts == 20 then
				warn("seems like synchronizing master is taking a while, maybe your device is slow, or the asset id is invalid, OR this module isn't working anymore")
			end

			print("synchronizing master...")

			-- set master sample positions

			for i, master_sample in pairs(master_samples) do
				local master_position = self:get_master_position(i, master_asset_data, master_samplerate, 0)

				master_sample:Stop()
				master_sample.TimePosition = master_position
			end

			-- play master samples

			for i, master_sample in pairs(master_samples) do
				master_sample:Play()
			end

			task.wait(.2)

			-- sync master samples

			local verified = false

			repeat

				local peak_level = sync_analyzer.PeakLevel -- 0.5652818083763123
				if peak_level > 0 then

					verified = true

					if peak_level > .37 and peak_level < .38 then
						sync_success = true
					else
						sync_success = false
					end

				end

				if not verified then
					print("waiting for master to respond...")
					task.wait(.1)
				end

			until verified

		end

		sync_reference.Volume = sync_reference_previous_volume

		sync_wire:Destroy()
		sync_analyzer:Destroy()

		self.sync_analyzer = sync_analyzer

		print("done synchronizing master, attempts:", sync_attempts)
	end

	-- done :-)

	self.master_samples = master_samples
	self.master_asset_data = master_asset_data
	self.master_sample_count = master_sample_count
	self.master_length = master_length
	self.channels = channels
	self.final_fader = final_fader
	self.sync = 0

	local init_elapsed = (os.clock() - init_start)
	print("successfully initialized rbxaudio after ".. tostring(math.floor(init_elapsed * 1000)) .. "ms!")

	final_fader.Volume = 1

	self.initialized = true

end

function rbxaudio:destroy()

	if self.folder then
		self.folder:Destroy()
	end

end

return rbxaudio
