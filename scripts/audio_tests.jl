using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using LibSndFile, PortAudio, SampledSignals, FileIO
using Bplus; @using_bplus

SAMPLING_RATE::Int = 44100
test_snd(f, m=1/60) = begin
    data = map(1:(SAMPLING_RATE * 60 * m)) do i
        t = i/SAMPLING_RATE
        return convert(Float32, f(t))
    end
    PortAudioStream(1, 1, samplerate=SAMPLING_RATE, latency=0.4) do stream
        write(stream, data)
    end
    save("test.wav", SampleBuf{Float32, 1}(data, SAMPLING_RATE))
end
test_snd(f::AbstractField{1, 1, F}, args...) where {F} = let data = Bplus.Fields.prepare_field(f)
    test_snd(t -> Bplus.Fields.get_field(f, Vec(convert(F, t)), data).x, args...)
end


"
Weighted combination of noise signals (of known value ranges),
    nomalized to some output range
"
snd_sum(inputs::Tuple, weights::Tuple, ranges::Tuple, out_min, out_max) = t -> begin
    values = invoke.(inputs, Tuple{typeof(t)}, t)
    norm_values = (values .- Tuple(r[1] for r in ranges)) ./ Tuple((r[2]-r[1]) for r in ranges)
    weighted_values = norm_values .* weights
    t = sum(weighted_values ./ sum(weights))
    return lerp(out_min, out_max, t)
end

"Oscillates between two sounds, using 0-1 space (not 0-pi or 0-360)"
snd_oscillate(a_func, b_func, period, sharpness, dullness, phase=0) = x -> begin
    # Evaluate the endpoints.
    a = a_func(x)
    b = b_func(x)

    # Blend between the endpoints using the oscillator and the parameters.
    t = 0.5 + (0.5 * sin(3.1415926 * 2 * (phase + (period * x))))
    dull_target = (t < 0.5) ? 0 : 1
    t = lerp(t, dull_target, dullness) ^ sharpness
    return lerp(a, b, t)
end

"Low droning noise, normalized to [0, 1]"
snd_drone(pitch_scale) = begin
    scale = 99 * pitch_scale
    return (t -> let f = t * scale
        f - trunc(f)
    end)
end
"Perlin noise, normalized to [0, 1]"
snd_perlin(pitch_scale) = t -> perlin(t * 1000 * pitch_scale)

const SND_DRONE = snd_sum(
    (
        snd_drone(0.9),
        snd_drone(1.8),
        snd_drone(0.65),
        snd_perlin(1),
        snd_perlin(0.5)
    ),
    (
        0.5,
        0.5,
        1.5,
        1.0,
        0.7
    ),
    (
        (0, 1),
        (0, 1),
        (0, 1),
        (0, 1),
        (0, 1)
    ),
    -1, 1
)
const SND_VOICE = snd_sum(
    (
        snd_oscillate(
            snd_drone(0.6),
            snd_drone(1.6),
            4, 1.0, 0.0, 0.0
        ),
        snd_perlin(0.77)
    ),
    (
        0.5,
        1.0
    ),
    (
        (0, 1),
        (0, 1)
    ),
    -1, 1
)


# "OscillateField" oscillates between two values, given a normalized period/phase and some parameters.
function OscillateField(a::AbstractField{NIn, NOut, F},
                        b::AbstractField{NIn, NOut, F},
                        t::AbstractField{NIn, 1, F},
                        period::AbstractField{NIn, 1, F} = Bplus.Fields.ConstantField{NIn}(Vec{1, F}(1)),
                        sharpness::AbstractField{NIn, 1, F} = Bplus.Fields.ConstantField{NIn}(Vec{1, F}(1)),
                        dullness::AbstractField{NIn, 1, F} = Bplus.Fields.ConstantField{NIn}(Vec{1, F}(0)),
                        phase::AbstractField{NIn, 1, F} = Bplus.Fields.ConstantField{NIn}(Vec{1, F}(0))
                       ) where {NIn, NOut, F}
    raw_sine_field = Bplus.Fields.LerpField(
        Bplus.Fields.ConstantField{1}(Vec{1, F}(0.5)),
        Bplus.Fields.ConstantField{1}(Vec{1, F}(1.0)),
        Bplus.Fields.SinField(
            Bplus.Fields.MultiplyField(
                Bplus.Fields.ConstantField{1}(Vec{1, F}(3.14159265 * 2)),
                Bplus.Fields.AddField(
                    phase,
                    Bplus.Fields.MultiplyField(
                        period,
                        t
                    )
                )
            )
        )
    )
    #TODO: re-use the raw_sine_field computation somehow 

    dull_target_field = Bplus.Fields.StepField(
        Bplus.Fields.ConstantField{NIn}(Vec{1, F}(0.5)),
        raw_sine_field
    )

    output_t_field = Bplus.Fields.PowField(
        Bplus.Fields.LerpField(
            raw_sine_field,
            dull_target_field,
            dullness
        ),
        sharpness
    )

    return Bplus.Fields.LerpField(a, b, output_t_field)
end
#TODO: Rest of interface, OscillateField should be a real type
function Bplus.Fields.field_from_dsl_func(::Val{:oscillate},
                                          context::DslContext,
                                          state::DslState,
                                          args::Tuple)
    return OscillateField(Bplus.Fields.field_from_dsl.(args, Ref(context), Ref(state))...)
end


const SND_FIELD = Bplus.Fields.@field(1, Float32,
    (0.65 * oscillate(-1, 1, pos, 110,
        oscillate(3, 5, pos, 20),
        oscillate(0.0, 0.7, pos, 51, 4)
    )) + (0.35 * lerp(-1, 1, perlin(pos * 850)))
)

println(stderr, "Generating...")
test_snd(SND_FIELD, 3/60)
println(stderr, "Done!")