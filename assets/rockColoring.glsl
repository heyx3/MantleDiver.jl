/*  Assume the following are defined:
        * N_MINERALS
        * N_MINERALS_AND_ROCK
        * MINERAL_[X] (all mineral types, 0-based)
        * SHAPE_[X] (all char shape types, 0-based)
        * MINERAL_SHAPE_[X] (the official shape type for each mineral)
        * MINERAL_COLOR_[X] (the official color for each mineral)
        * u_gameSeconds
        * The various UBO's defined in the project (e.g. camera, framebuffer)
        * Our shader utilities code (e.g. perlin noise)
*/

MaterialSurface defineMineralSurface(uint fgColor, uint fgShape, float fgDensity,
                                     uint bgColor, float bgDensity,
                                     float fgShine)
{
    MaterialSurface mOut;

    mOut.foregroundColor = fgColor;
    mOut.foregroundShape = fgShape;
    mOut.foregroundDensity = fgDensity;

    mOut.backgroundColor = bgColor;
    mOut.backgroundDensity = bgDensity;

    mOut.isTransparent = false;

    mOut.foregroundShine = fgShine;

    return mOut;
}
void defineMineralSurfaces(out MaterialSurface mOuts[N_MINERALS_AND_ROCK],
                           vec3 worldPos, vec2 uv, vec3 normal, ivec3 gridCell,
                           vec2 worldPosAlongSurface, vec3 camToSurface)
{
    //Pre-define some noise values for all minerals to use.
    float noises[] = {
        perlinNoise(worldPos * 0.5, 1.42341),
        perlinNoise(worldPos * 2, 1.42341),
        perlinNoise(worldPos * 4, 5.334498471),
        perlinNoise(worldPos * 8, 0.7),
        perlinNoise(worldPos * 4, 1.42341),
        worley2(worldPosAlongSurface * 2, 0.5, -1.3321310),
        worley1(worldPosAlongSurface * 3, 0.5, -1.3321310)
    };
    #define NOISED(i, a, b, exponent) (mix(float(a), float(b), pow(noises[i], float(exponent))))

    //When the surface gets close to the camera, interleave some faux-chatoyancy.
    float chatCloseness = border(length(camToSurface), 0.0,   10.0, 2.0);
    float chatInterval = mix(20.0, 2.0, chatCloseness);
    ivec2 chatMaskSurface = sign(ivec2(floor(mod(gl_FragCoord.xy, chatInterval))));
    bool chatMask = (chatMaskSurface.x + chatMaskSurface.y) == 0 &&
                    (perlinNoise(worldPos * 2.0, 3.08384) > 0.55),
         chatFlip = false && (hashTo1(floor(vec4(u_gameSeconds, worldPos)
                                    * vec4(2, 20, 20, 20))) > 0.275);
    #define CHATTED(normal, ifChat, ifChatFlipped) (chatMask ? (chatFlip ? (ifChatFlipped) : (ifChat)) : (normal))

    mOuts[MINERAL_storage] = defineMineralSurface(
        MINERAL_COLOR_storage, MINERAL_SHAPE_storage,
        NOISED(5,   0.23, 0.73,   1.0),
        MINERAL_COLOR_storage, 0.1,
        CHATTED(0.0, 50.0, 0.5)
    );
    mOuts[MINERAL_hull] = defineMineralSurface(
        MINERAL_COLOR_hull, MINERAL_SHAPE_hull,
        NOISED(1,   0.1, 0.7,   0.3),
        6, 0.1,
        CHATTED(0.0, 70.0, 0.5)
    );
    mOuts[MINERAL_drill] = defineMineralSurface(
        MINERAL_COLOR_drill, MINERAL_SHAPE_drill,
        NOISED(5,    0.1, 0.63,   4.0),
        1, NOISED(2,    0.05, 0.3,     5.0),
        CHATTED(0.0, 90.0, 0.5)
    );
    mOuts[MINERAL_specials] = defineMineralSurface(
        MINERAL_COLOR_specials, MINERAL_SHAPE_specials,
        NOISED(1,    0.2, 1,   6.0),
        1, 0.0,
        CHATTED(0.0, 110.0, 0.5)
    );
    mOuts[MINERAL_sensors] = defineMineralSurface(
        MINERAL_COLOR_sensors, MINERAL_SHAPE_sensors,
        0.75,
        1, 0.0,
        CHATTED(0.0, 130.0, 0.5)
    );
    mOuts[MINERAL_maneuvers] = defineMineralSurface(
        MINERAL_COLOR_maneuvers, MINERAL_SHAPE_maneuvers,
        0.475,
        MINERAL_COLOR_maneuvers, NOISED(2,    0.05, 0.7,     5.0),
        CHATTED(0.0, 150.0, 0.5)
    );

    //Plain rock:
    mOuts[N_MINERALS] = defineMineralSurface(
        1, SHAPE_round, NOISED(1,    0.05, 0.9,    5.0),
        1,              NOISED(0,    0.0,  0.15,   1.5),
        NOISED(1,    0.0, 2.0,    8.0)
    );
}

//Implements the core logic for rock coloring, assuming all other shader stuff is defined for us.
MaterialSurface getRockMaterial(vec3 worldPos, vec2 uv, vec3 normal, ivec3 gridCell,
                                in float mineralDensitiesThenRock[N_MINERALS_AND_ROCK])
{
    //Get the 2D world position along this surface.
    vec3 absNormal = abs(normal);
    vec2 posAlongSurface;
    if (absNormal.z > max(absNormal.x, absNormal.y))
        posAlongSurface = worldPos.xy;
    else if (absNormal.y > max(absNormal.x, absNormal.z))
        posAlongSurface = worldPos.xz;
    else
        posAlongSurface = worldPos.yz;

    //Get the primary mineral in this rock.
    mineralDensitiesThenRock[N_MINERALS] = 0.00001;
    int mineralIdx = 0;
    float mineralDensity = mineralDensitiesThenRock[0];
    for (int i = 1; i < N_MINERALS_AND_ROCK; ++i)
        if (mineralDensitiesThenRock[i] > mineralDensity)
        {
            mineralIdx = i;
            mineralDensity = mineralDensitiesThenRock[i];
        }

    //Evaluate a global 3D noise that interpolates between this rock's mineral and a plain surface.
    float mineralNoise = worley3(worldPos * 1.0, 1.0, 2.2222222),
          mineralCentrality = border(mineralNoise, 0.0, 1.0, 1.0);
    bool isMineral = (mineralCentrality < mineralDensity*1.0);

    //Pick the kind surface to render here.
    MaterialSurface mineralSurfaces[N_MINERALS_AND_ROCK];
    defineMineralSurfaces(mineralSurfaces,
                          worldPos, uv, normal, gridCell,
                          posAlongSurface, worldPos - u_world_cam.cam_pos.xyz);
    return isMineral ? mineralSurfaces[mineralIdx] : mineralSurfaces[N_MINERALS];
}