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
end
function AudioFiles(project_path::AbstractString = ".")
    return AudioFiles(
        LoadedAudio(AUDIO_DRILL, project_path),
        LoadedAudio(AUDIO_HIT_GROUND, project_path),
        LoadedAudio(AUDIO_AMBIANCES_PLAIN, project_path),
        LoadedAudio(AUDIO_AMBIANCES_SPECIAL, project_path)
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

    sounds::Vector{SampleBuf}
    priority::Float32

    seed::Int

    current_buffer_idx::Int
    current_sample_idx::Int

    #PlayingLoop(audio::LoadedAudio, )
end

#TODO: PlayingLoop, for continuously cross-fading between sounds


"
An audio stream that blends multiple `PlayingSound`s together.
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

    sounds_game_thread::Vector{PlayingSound} # Access should be wrapped in the below locker.
    sounds_game_thread_locker::ReentrantLock # Used to prevent race conditions
                                             #   when accessing 'sounds_game_thread'.
    sounds_audio_thread::Vector{PlayingSound} # Internal buffer
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
        Vector{PlayingSound}(), ReentrantLock(),
        Vector{PlayingSound}()
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

    # Move all sounds from the game thread to the audio thread.
    # After this current frame has been written to the audio buffers,
    #    some of those sounds stop playing.
    # At the end of this frame, all sounds which are still playing are appended
    #    back into the game-thread buffer, on top of any new sounds from the game.
    #TODO: Locking in this audio thread is a bad idea; we need a lock-free technique. But that seems very complicated to implement...
    empty!(m.sounds_audio_thread)
    lock(m.sounds_game_thread_locker) do
        append!(m.sounds_audio_thread, m.sounds_game_thread)
        empty!(m.sounds_game_thread)
    end

    # Scale each active sound by its priority.
    # Note that sounds which stop playing during this callback
    #    will cause subsequent samples to sound quieter;
    #    we may need a more dynamic way of scaling sounds by priority.
    priority_scaling = let s = sum((s.priority for s in m.sounds_audio_thread), init=zero(Float32))
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

    # Give the sounds back to the game thread, in a way that preserves
    #    any new sounds the game thread has added in the meantime.
    lock(m.sounds_game_thread_locker) do
        append!(m.sounds_game_thread, m.sounds_audio_thread)
    end

    return output_count
end

function play_sound(manager::AudioManager{N, F},
                    sound::LoadedAudio,
                    volume_scale::F = one(F),
                    buffer_idx::Optional{Int} = nothing
                   ) where {N, F}
    if !manager.disable_new_sounds
        lock(manager.sounds_game_thread_locker) do
            push!(manager.sounds_game_thread, PlayingSound(
                sound, buffer_idx,
                volume_scale=volume_scale
            ))
        end
    end
end