My notes on how to use Julia's audio packages.

# SampledSignals.jl

Provides all the core data, collections, and interfaces for audio (and other signals).

* Audio samples are stored in an `AbstractSampleBuf{TSample, NChannels}`. Which is either a time-domain `SampleBuf{T, N}` or a frequency-domain `SpectrumBuf{T, N}`.
* Sources of audio (like a microphone device) are an `abstract type SampleSource`.
  * `SampleBufSource` is an audio source backed by an `AbstractSampleBuf`.
  * Sample sources should implement a particular interface, including `eltype()` and `nchannels()`
* Destinations for audio (like a computer speaker) are an `abstract type SampleSink`.
  * `SampleBufSink` is an audio destination backed by an `AbstractSampleBuf`.
* To set up direct stream-to-stream connections, call `write(my_sink, my_source[; blocksize])`. `blocksize` is the number of frames to write t a time, defaulting to 4096.
* To convert audio from one buffer (sample type/channel count/sampling rate) to another, wrap the source in `SampleBufSource`, wrap the destination in `SampleBufSink`, and write one to the other.
* Uses units from *Unitful.jl* -- seconds `[n|u|m]s`, frequencies `[k|M|G|T]Hz`, and `dB`, to do automatic conversion when sampling. For example, `four_seconds_of_audio = read(audio_source, 4s)`.

# LibSndFile.jl

The library `libsndfile` provides loading and saving audio files, using `sample_buffer = load(stream_or_path)` and `save(stream_or_path, sample_buffer)`.

You can also stream in an audio file using `loadstreaming()`, which returns a file stream instead of an entire buffer.

# PortAudio.jl

Provides cross-platform access to audio devices, using *libportaudio.dll*, through the interfaces defined in *SampledSignals.jl*. A `PortAudioStream` is a combination of `source` and `sink`, for example the computer's microphone and speaker.

Create a stream using the system's default in/out devices with `PortAudioStream([inchans][, outchans]; [eltype=Float32][, samplerate=48000][, latency=0.1])`.
Automatically close the stream by wrapping your audio code in a `do` block: `PortAudioStream(...) do stream ... end`.

List the system devices with `PortAudio.devices()::Vector{PortAudioDevice}`.
Create a stream with specific named devices using `PortAudioStream([code_block, ] name1, name2, ...)`
For example, to pass through input from microphone to speaker indefinitely and auto-clean-up when interrupting with Ctrl+C, do `PortAudioStream(s -> write(s, s))`.