/*  Assume the following are defined:
        * N_MINERALS
        * N_MINERALS_AND_ROCK
        * MINERAL_[X] (all mineral types, 0-based)
        * SHAPE_[X] (all char shape types, 0-based)
        * u_gameSeconds
        * The various UBO's defined in the project (e.g. camera, framebuffer)
        * Our shader utilities code (e.g. perlin noise)
*/

MaterialSurface defineMineralSurface(uint fgColor, uint fgShape, float fgDensity,
                                     uint bgColor, float bgDensity)
{
    MaterialSurface mOut;

    mOut.foregroundColor = fgColor;
    mOut.foregroundShape = fgShape;
    mOut.foregroundDensity = fgDensity;

    mOut.backgroundColor = bgColor;
    mOut.backgroundDensity = bgDensity;

    mOut.isTransparent = false;

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
    };
    #define NOISED(i, a, b, exponent) (mix(float(a), float(b), pow(noises[i], float(exponent))))

    //When the surface gets close to the camera, interleave some faux-chatoyancy.
    float chatCloseness = border(length(camToSurface), 0.0,   10.0, 2.0);
    float chatInterval = mix(20.0, 2.0, chatCloseness);
    ivec2 chatMaskSurface = sign(ivec2(floor(mod(gl_FragCoord.xy, chatInterval))));
    bool chatMask = (chatMaskSurface.x + chatMaskSurface.y) == 0 &&
                    (perlinNoise(worldPos * 5.0, 3.08384) > 0.35),
         chatFlip = hashTo1(floor(vec4(u_gameSeconds, worldPos)
                                    * vec4(2, 20, 20, 20))) > 0.275;
    #define CHATTED(normal, ifChat, ifChatFlipped) (chatMask ? (chatFlip ? (ifChatFlipped) : (ifChat)) : (normal))

    mOuts[MINERAL_storage] = defineMineralSurface(
        6, SHAPE_block,
        NOISED(1,   0.23, 0.43,   1.0),
        6, 0.1
    );
    mOuts[MINERAL_hull] = defineMineralSurface(
        CHATTED(2, 1, 0), SHAPE_block,
        NOISED(1,   0.1, 0.7,   0.3),
        6, 0.1
    );
    mOuts[MINERAL_drill] = defineMineralSurface(
        6, SHAPE_unusual,
        NOISED(1,    0.2, 0.3,   4.0),
        1, NOISED(2,    0.05, 0.3,     5.0)
    );
    mOuts[MINERAL_specials] = defineMineralSurface(
        CHATTED(7, 0, 1), SHAPE_unusual,
        NOISED(1,    0.8, 1,   6.0),
        1, 0.0
    );
    mOuts[MINERAL_sensors] = defineMineralSurface(
        CHATTED(4, 0, 1), SHAPE_tall,
        0.75,
        1, 0.0
    );
    mOuts[MINERAL_maneuvers] = defineMineralSurface(
        CHATTED(4, 1, 0), SHAPE_wide,
        0.275,
        4, NOISED(2,    0.05, 0.7,     5.0)
    );

    //Plain rock:
    mOuts[N_MINERALS] = defineMineralSurface(
        1, SHAPE_round, NOISED(1,    0.05, 0.4,    3.0),
        1,              NOISED(0,    0.0,  0.15,   1.5)
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

    //Define the surface properties of each mineral, and plain rock.
    MaterialSurface mineralSurfaces[N_MINERALS_AND_ROCK];
    defineMineralSurfaces(mineralSurfaces,
                          worldPos, uv, normal, gridCell,
                          posAlongSurface, worldPos - u_world_cam.cam_pos.xyz);

    //Pick the surface data of the densest mineral in this rock.
    int densestI = 0;
    for (int i = 1; i < N_MINERALS_AND_ROCK; ++i)
        if (mineralDensitiesThenRock[i] > mineralDensitiesThenRock[densestI])
            densestI = i;
    MaterialSurface surface = mineralSurfaces[densestI];

    return surface;
}