"Provides access to important singletons outside this ECS world"
@component Services {worldSingleton} begin
    audio::AudioManager
    audio_files::AudioFiles

    assets::Assets
end