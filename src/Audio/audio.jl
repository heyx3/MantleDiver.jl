using LibSndFile, PortAudio, SampledSignals, FileIO


#TODO: Limit the number of one audio asset playing at once
#TODO: Add volume sliders for individual sound categories, and give each AudioAsset a category.
#TODO: Remove type-instability/JIT overhead by auto-converting all audio assets to a common sample type and channel count.
#TODO: Auto-convert all audio assets to the audio device's sampling frequency


###################################
#     Files

"Points to one or more audio files on disk, and describes how to play them"
struct AudioAsset
    # Relative to the project's audio folder.
    # If loading a sequence of audio files, the file's name should have an '%i' in it
    #    which is replaced with 1, 2, etc.
    relative_path::String

    # Multiplies the amplitude of this asset when loading it
    volume::Float32

    # The importance of this audio asset relative to others,
    #    from 0 to 1 (just to establish a convention).
    priority::Float32
end

const AUDIO_FOLDER = "audio"

const AUDIO_DRILL = AudioAsset("Drill.wav", 1.0, 0.65)
const AUDIO_HIT_GROUND = AudioAsset("HitGround.wav", 1.0, 0.65)
const AUDIO_AMBIANCES_PLAIN = AudioAsset(joinpath("Ambiance", "Plain%i.wav"), 1.0, 0.2)
const AUDIO_AMBIANCES_SPECIAL = AudioAsset(joinpath("Ambiance", "Special%i.wav"), 1.0, 0.2)


###################################
#     Data

"Some number of audio files loaded from an `AudioAsset`"
struct LoadedAudio
    buffers::Union{SampleBuf, Vector{SampleBuf}}
    source::AudioAsset
end
function LoadedAudio(asset::AudioAsset, root_path::AbstractString = ".")
    # Get the first char of the actual file name.
    file_name_start = findlast('/', asset.relative_path)
    if isnothing(file_name_start)
        file_name_start = findlast('\\', asset.relative_path)
        if isnothing(file_name_start)
            file_name_start = 0
        end
    end
    file_name_start += 1

    # Look for a '%i' token indicating a sequence of files.
    is_multi::Bool = occursin("%i", @view(asset.relative_path[file_name_start:end]))
    if !is_multi
        return LoadedAudio(
            load(joinpath(root_path, AUDIO_FOLDER, asset.relative_path)),
            asset
        )
    else
        return LoadedAudio(
            collect(SampleBuf, IterSome() do i::Int
                relative_path = string(
                    @view(asset.relative_path[1:(file_name_start-1)]),
                    replace(@view(asset.relative_path[file_name_start:end]),
                            "%i"=>i)
                )
                path = joinpath(root_path, AUDIO_FOLDER, relative_path)
                if isfile(path)
                    Some(load(path))
                else
                    nothing
                end
            end),
            asset
        )
    end
end


"Manages audio assets loaded from disk"
mutable struct AudioFiles
    drill::LoadedAudio
    hit_ground::LoadedAudio
    ambiance_plain::LoadedAudio
    ambiance_special::LoadedAudio

    crossfade_seconds_ambiance_plain::Float32
    crossfade_seconds_ambiance_special::Float32
end
function AudioFiles(project_path::AbstractString = ".")
    return AudioFiles(
        LoadedAudio(AUDIO_DRILL, project_path),
        LoadedAudio(AUDIO_HIT_GROUND, project_path),
        LoadedAudio(AUDIO_AMBIANCES_PLAIN, project_path),
        LoadedAudio(AUDIO_AMBIANCES_SPECIAL, project_path),
        0.6, 0.6
    )
end


###################################################
#       Playback

#TODO: Handle multi-channel/spacial output

"
A one-off sound effect.
Construct it with the `LoadedAudio`, a buffer index if there's more than one buffer to pick from,
  and optionally the initial sample index.

Assumes the sound buffer(s) use first axis for sample and second axis for channel.
"
mutable struct PlayingSound
    current_sample_idx::Int
    priority::Float32
    volume::Float32
    sound::SampleBuf

    function PlayingSound(audio::LoadedAudio, buffer_idx::Optional{Int} = nothing
                          ;
                          first_sample_idx::Optional{Int} = nothing,
                          volume_scale::Float32 = one(Float32))
        buf::SampleBuf = if isnothing(buffer_idx)
            audio.buffers
        else
            audio.buffers[buffer_idx]
        end
        return new(
            if isnothing(first_sample_idx)
                first(axes(buf, 1))
            else
                first_sample_idx
            end,
            audio.source.priority,
            audio.source.volume * volume_scale,
            buf
        )
    end
end

"A playing sound's progress from 0 (just started) to 1 (just finished)"
playback_progress(p::PlayingSound)::Float64 = (p.current_sample_idx - 1) / size(p.sound, 1)::Int

"A playing sound's remaning samples left before it's done"
playback_samples_left(p::PlayingSound)::Int = (size(p.sound, 1)::Int - p.current_sample_idx + 1)

"A playing sound's progress, in elapsed seconds"
playback_seconds_elapsed(p::PlayingSound)::Float64 =
    # Dispatch to a lambda where the sound buffer's type is known at compile time.
    ((sound) -> (p.current_sample_idx - 1) / samplerate(sound))(p.sound)

"A playing sound's time left before it's done, in seconds"
playback_seconds_left(p::PlayingSound)::Float64 =
    # Dispatch to a lambda where the sound buffer's type is known at compile time.
    ((sound) -> (size(sound, 1) - p.current_sample_idx + 1) / samplerate(sound))(p.sound)

"
Writes a playing sound's next samples into the entire given buffer
  (you probably want to pass a `@view` of the real buffer).
Returns whether the sound is still active.

Any output samples past the end of the sound wave are not touched.
Assumes all sound buffers are 2D, first axis for samples and second axis for channels.
"
function advance_playback!(p::PlayingSound, output_buf, volume_priority_scale::Float32)::Bool
    n_desired_samples = size(output_buf, 1)
    wave_scale::Float32 = p.volume * p.priority * volume_priority_scale

    # Dispatch so the sound buffer is type-stable.
    # Capture the total number of samples in that sound.
    n_sound_samples = ((sound) -> begin
        n_sound_samples = size(sound, 1)
        in_channels = axes(sound, 2)

        # Write as much of the sound as we can.
        n_written_samples = min(n_desired_samples,
                                n_sound_samples - p.current_sample_idx + 1)
        buffer_output_range = let a = first(axes(output_buf, 1))
            a : (a + n_written_samples - 1)
        end
        sound_sample_range = p.current_sample_idx : (p.current_sample_idx + n_written_samples - 1)

        #TODO: The per-channel stuff can probably be worked into the broadcast operator
        for out_channel in axes(output_buf, 2)
            in_channel = clamp(out_channel, first(in_channels), last(in_channels))
            output_buf[buffer_output_range, out_channel] .+= wave_scale .* sound[sound_sample_range, in_channel]
        end

        p.current_sample_idx += n_written_samples
        return n_sound_samples::Int
    end)(p.sound)::Int

    return p.current_sample_idx <= n_sound_samples
end


"
A continuously-looping sound effect, cross-fading new fragments as old ones fade out.
Construct it with a `LoadedAudio` that holds multiple buffers,
   and cross-fading parameters.

Assumes the sound buffer(s) use first axis for sample and second axis for channel.
"
mutable struct PlayingLoop
    @atomic volume::Float32 # Can be modified from the game loop
    @atomic should_stop::Bool # Set this to kill the loop

    sounds::Vector{SampleBuf}
    priority::Float32

    rng::Bplus.PRNG
    crossfade_samples::UInt32

    current_sound::PlayingSound
    previous_sound::PlayingSound # sample index set to 0 if nonexistent

    function PlayingLoop(audio::LoadedAudio,
                         crossfade_seconds::Float64,
                         seed = 0x12345678,
                         ;
                         volume_scale::Float32 = one(Float32))
        sounds = if audio.buffers isa Vector{SampleBuf}
            audio.buffers
        elseif audio.buffers isa SampleBuf
            SampleBuf[ audio.buffers ]
        else
            error(typeof(audio.buffers))
        end
        if isempty(sounds)
            error("The array of sounds is empty!")
        end
        sample_rate = SampledSignals.samplerate(sounds[1])

        crossfade_samples = round(UInt32, crossfade_seconds * sample_rate)
        if any(s -> size(s, 1) < crossfade_samples*2, sounds)
            original_crossfade_samples = crossfade_samples
            crossfade_samples = minimum((size(s, 1)÷2) for s in sounds)
            @warn "Crossfade length is too long for these sounds; it's being shortened from $original_crossfade_samples to $crossfade_samples"
        end

        rng = Bplus.PRNG(seed, 0xa12bc43d)
        out_seed = rand(rng, Int64)
        first_buffer_idx = rand(rng, 1:length(sounds))

        current_sound = PlayingSound(LoadedAudio(sounds[first_buffer_idx], audio.source),
                                     nothing)
        previous_sound = PlayingSound(LoadedAudio(sounds[1], audio.source),
                                      nothing,
                                      first_sample_idx=0)

        return new(
            volume_scale, false,
            sounds, audio.source.priority,
            rng, crossfade_samples,
            current_sound, previous_sound
        )
    end
end

"
Writes a playing loop's next samples into the entire given buffer
  (you probably want to pass a `@view` of the real buffer).
Returns whether the loop is still playing.

Assumes all sound buffers are 2D, first axis for samples and second axis for channels.
"
function advance_playback!(p::PlayingLoop, output_buf, volume_priority_scale::Float32)::Bool
    if @atomic(p.should_stop)
        return false
    end

    n_desired_samples = size(output_buf, 1)
    volume_priority_scale *= @atomic(p.volume)

    # Note that we already checked in the constructor that the individual sounds
    #    are long enough to not overlap improperly when crossfading.

    # Advance in stages, until we've exhausted the buffer:
    #    1. To the end of the fading-out sound
    #    2. To the start of the new fading-in sound
    #    3. Go to 1

    # Put the buffer in a type-stable view.
    output_buf_view = @view(output_buf[:, :])

    while true
        # Play the fading-out sound.
        if p.previous_sound.current_sample_idx > 0
            still_fading_out::Bool = advance_playback!(p.previous_sound, output_buf_view, volume_priority_scale)

            # If we're still fading out the previous sound, then
            #    we certainly won't finish the current sound either.
            if still_fading_out
                still_playing_primary::Bool = advance_playback!(p.current_sound, output_buf_view, volume_priority_scale)
                @d8_assert(still_playing_primary)
                @d8_assert(playback_samples_left(p.current_sound) > p.crossfade_samples)
                break
            else
                p.previous_sound.current_sample_idx = 0
            end
        end

        # At this point the fading-out sound definitely doesn't exist (just played out, or never existed).
        # Play the primary sound, but only up to the point where *it* starts cross-fading out.
        first_crossfading_sample::Int = size(p.current_sound.sound, 1)::Int - p.crossfade_samples + 1
        n_samples_before_crossfade::Int = first_crossfading_sample - p.current_sound.current_sample_idx
        if n_samples_before_crossfade < n_desired_samples
            # Play the non-crossfaded part of the sound, if any exists.
            first_idx = first(axes(output_buf_view, 1))
            output_buf_non_crossfading = @view(output_buf_view[first_idx : (first_idx + n_samples_before_crossfade - 1)])
            if !isempty(output_buf_non_crossfading)
                still_playing_primary = advance_playback!(p.current_sound, output_buf_non_crossfading, volume_priority_scale)
                @d8_assert(still_playing_primary)
            end

            # Switch this sound to fade out, and the new one to fade in.
            temp_sound = p.previous_sound
            p.previous_sound = p.current_sound
            p.current_sound = temp_sound

            p.current_sound.current_sample_idx = 1
            p.current_sound.sound = rand(p.rng, p.sounds)
        else
            still_playing_primary = advance_playback!(p.current_sound, output_buf_view, volume_priority_scale)
            @d8_assert(still_playing_primary)
            break
        end

        # At this point we've handled all buffer outputs up until cross-fading starts again.
        @d8_assert(first_crossfading_sample > first(axes(output_buf_view, 1)),
                   "first_crossfading_sample is ", first_crossfading_sample)
        output_buf_view = @view(output_buf_view[first_crossfading_sample:end, :])
        @d8_assert(p.previous_sound.current_sample_idx > 0)
    end

    return true
end


"
An audio stream that blends multiple `PlayingSound`s and `PlayingLoop`s together.
All sounds must have the same sampling rate as this manager,
    but do not need to have the same number of channels (output channel index is clamped to the input range).
"
mutable struct AudioManager{NChannels, TSample} <: SampledSignals.SampleSource
    stream::PortAudioStream
    sample_rate::Float64 # All playing sounds must have this sample rate.
    disable_new_sounds::Bool # Useful for precompile/debug reasons

    @atomic total_volume::TSample # Change at will
    @atomic should_close::Bool # Set this to end the audio stream.
    @atomic is_closed::Bool # Gets set to true once the audio stream has effectively closed.

    # Access to these lists should be done with the corresponding locker.
    sounds_main_list::Vector{PlayingSound}
    loops_main_list::Vector{PlayingLoop}
    sounds_main_list_locker::ReentrantLock
    loops_main_list_locker::ReentrantLock

    # The audio playback thread will temporarily pull sounds out of the master list
    #    to manipulate them itself.
    sounds_audio_thread::Vector{PlayingSound}
    loops_audio_thread::Vector{PlayingLoop}
end

# Life cycle:
function AudioManager{NChannels, TSample}(sample_rate::Float64,
                                          initial_volume::TSample = one(TSample),
                                          output_device::Optional{String} = nothing
                                         ) where {NChannels, TSample}
    stream = if exists(output_device)
        PortAudioStream("", output_device, 0, 2)
    else
        PortAudioStream(0, 2)
    end

    manager = AudioManager{NChannels, TSample}(
        stream, sample_rate, false,
        initial_volume,
        false, false,
        Vector{PlayingSound}(), Vector{PlayingLoop}(),
        ReentrantLock(), ReentrantLock(),
        Vector{PlayingSound}(), Vector{PlayingLoop}()
    )

    @async write(stream, manager) # Starts the audio-reading callback
    return manager
end
function Base.close(a::AudioManager)
    # Kill the audio thread.
    @atomic a.should_close = true
    while !(@atomic a.is_closed)
        sleep(0.1)
    end

    # Kill the audio output resource.
    close(a.stream)
end

# Implement the interface for sample sources.
SampledSignals.samplerate(m::AudioManager) = m.sample_rate
SampledSignals.nchannels(::AudioManager{NChannels}) where {NChannels} = NChannels
SampledSignals.eltype(::AudioManager{NChannels, TSample}) where {NChannels, TSample} = TSample
function SampledSignals.unsafe_read!(m::AudioManager{NChannels, TSample},
                                     out_samples_buf::Array,
                                     output_offset, output_count
                                    )::typeof(output_count) where {NChannels, TSample}
    # If it's time to close, write 0 audio samples and PortAudio will close this ongoing write operation.
    if @atomic m.should_close
        @atomic m.is_closed = true
        return zero(typeof(output_count))
    end

    # Initialize the output to 0.
    out_samples = @view(out_samples_buf[(1+output_offset):(output_count+output_offset), :])
    fill!(out_samples, zero(eltype(out_samples)))

    volume = @atomic m.total_volume

    # Move all sounds and loops from the game thread to the audio thread.
    # After this current frame has been written to the audio buffers,
    #    some of those sounds stop playing.
    # At the end of this frame, all sounds which are still playing are appended
    #    back into the game-thread buffer, on top of any new sounds from the game.
    #TODO: Locking in this audio thread is a bad idea; we need a lock-free technique. But that seems very complicated to implement...
    empty!(m.sounds_audio_thread)
    empty!(m.loops_audio_thread)
    lock(m.sounds_main_list_locker) do
        append!(m.sounds_audio_thread, m.sounds_main_list)
        empty!(m.sounds_main_list)
    end
    lock(m.loops_main_list_locker) do
        append!(m.loops_audio_thread, m.loops_main_list)
        empty!(m.loops_main_list)
    end

    # Scale each active sound by its priority.
    # Note that sounds which stop playing during this callback
    #    will cause subsequent samples to sound quieter;
    #    we may need a more dynamic way of scaling sounds by priority.
    priority_scaling = let s = sum((s.priority for s in m.sounds_audio_thread), init=zero(Float32)) +
                                sum((s.priority for s in m.loops_audio_thread), init=zero(Float32))
        if s <= 0
            one(Float32)
        else
            one(Float32) / s
        end
    end

    # Write all the sounds to the output buffer.
    sound_idx::Int = 1
    while sound_idx <= length(m.sounds_audio_thread)
        if advance_playback!(m.sounds_audio_thread[sound_idx], out_samples, volume / priority_scaling)
            sound_idx += 1
        else
            deleteat!(m.sounds_audio_thread, sound_idx)
        end
    end
    # Write all the loops to the output buffer in the same way.
    sound_idx = 1
    while sound_idx <= length(m.loops_audio_thread)
        if advance_playback!(m.loops_audio_thread[sound_idx], out_samples, volume / priority_scaling)
            sound_idx += 1
        else
            deleteat!(m.loops_audio_thread, sound_idx)
        end
    end

    # Give the sounds back to the game thread, in a way that preserves
    #    any new sounds the game thread has added in the meantime.
    lock(m.sounds_main_list_locker) do
        append!(m.sounds_main_list, m.sounds_audio_thread)
    end
    lock(m.loops_main_list_locker) do
        append!(m.loops_main_list, m.loops_audio_thread)
    end

    return output_count
end

function play_sound(manager::AudioManager{N, F},
                    sound::LoadedAudio,
                    volume_scale::F = one(F),
                    buffer_idx::Optional{Int} = nothing
                   ) where {N, F}
    if !manager.disable_new_sounds
        lock(manager.sounds_main_list_locker) do
            push!(manager.sounds_main_list, PlayingSound(
                sound, buffer_idx,
                volume_scale=volume_scale
            ))
        end
    end

    return nothing
end
function play_loop(manager::AudioManager{N, F},
                   sounds::LoadedAudio,
                   crossfade_seconds::F,
                   volume_scale::F = one(F),
                   seed = rand(Int)
                  )::PlayingLoop where {N, F}
    loop = PlayingLoop(
        sounds, convert(Float64, crossfade_seconds), seed,
        volume_scale=volume_scale
    )
    if !manager.disable_new_sounds
        lock(manager.loops_main_list_locker) do
            push!(manager.loops_main_list, loop)
        end
    end
    return loop
end