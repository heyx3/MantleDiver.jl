/*  Assume the following are defined:
        * N_MINERALS
        * N_MINERALS_AND_ROCK
        * MINERAL_[X] (all mineral types, 0-based)
        * SHAPE_[X] (all char shape types, 0-based)
    Also assume all other shader code is available to us (e.x. noise functions).
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
                           vec3 worldPos, vec2 uv, vec3 normal, vec2 worldPosAlongSurface)
{
    mOuts[MINERAL_storage] = defineMineralSurface(
        6, SHAPE_block, 0.3,
        6, 0.1
    );
    mOuts[MINERAL_hull] = defineMineralSurface(
        2, SHAPE_block, 0.7,
        6, 0.1
    );
    mOuts[MINERAL_drill] = defineMineralSurface(
        6, SHAPE_unusual, 0.2,
        1, 0.3
    );
    mOuts[MINERAL_specials] = defineMineralSurface(
        7, SHAPE_unusual, 0.8,
        1, 0.0
    );
    mOuts[MINERAL_sensors] = defineMineralSurface(
        4, SHAPE_tall, 0.75,
        1, 0.0
    );
    mOuts[MINERAL_maneuvers] = defineMineralSurface(
        4, SHAPE_wide, 0.275,
        1, 0.0
    );

    //Plain rock:
    mOuts[N_MINERALS] = defineMineralSurface(
        1, SHAPE_round,
          mix(0.05, 0.4,
              pow(perlinNoise(worldPosAlongSurface * 2, 1.42341), 2.4)),
        3, 0.4
    );
}

//Implements the core logic for rock coloring, assuming all other shader stuff is defined for us.
MaterialSurface getRockMaterial(vec3 worldPos, vec2 uv, vec3 normal, in float mineralDensitiesThenRock[N_MINERALS_AND_ROCK])
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
    defineMineralSurfaces(mineralSurfaces, worldPos, uv, normal, posAlongSurface);

    //Pick the surface data of the densest mineral in this rock.
    //TODO: Pick a mineral in a more interesting way.
    int densestI = 0;
    for (int i = 1; i < N_MINERALS + 1; ++i)
        if (mineralDensitiesThenRock[i] > mineralDensitiesThenRock[densestI])
            densestI = i;
    return mineralSurfaces[densestI];
}