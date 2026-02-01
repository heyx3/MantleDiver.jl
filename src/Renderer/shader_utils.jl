const SHADER_CODE_UTILS = """
#ifndef SHADER_CODE_UTILS
#define SHADER_CODE_UTILS

    #define COMMA ,

    #define PI (3.1415926535897932384626433832795)
    #define PI_2 (PI * 2.0)
    #define INV_LERP(a, b, x) (((x) - (a)) / ((b) - (a)))

    //Inigo Quilez's idea: https://iquilezles.org/articles/palettes/
    //Recommend using the following values, to start:
    //   * scaler = 0.5
    //   * bias = 0.5
    //   * oscillation between 0 and 3
    //   * phase between 0 and 1
    #define PROCEDURAL_GRADIENT(t, bias, scaler, oscillation, phase) \
        clamp(((bias) + ((scaler) * cos(PI_2 * (((oscillation) * (t)) + (phase))))), \
              0.0, 1.0)


    //Utils copied from BpWorld:

    #define OSCILLATE(a, b, x) (mix(a, b, 0.5 + (0.5 * sin(PI_2 * (x)))))

    #define SATURATE(x) clamp(x, 0.0, 1.0)
    #define SHARPEN(t) smoothstep(0.0, 1.0, t)
    #define SHARPENER(t) SMOOTHERSTEP(t)

    #define RAND_IN_ARRAY(array, t) array[int(mix(0.0, float(array.length()) - 0.00001, t))]

    //A higher-quality smoothstep(), with a zero second-derivative at the edges.
    #define SMOOTHERSTEP(t) clamp(t * t * t * (t * (t*6.0 - 15.0) + 10.0), \
                                0.0, 1.0)

    //Returns a value that increases towards 1 as it gets closer to some target.
    //Thickness is the size of the transition from 0 to 1, and must be > 0.
    //Dropoff is an exponent to dim the growth from 0 to 1.
    float border(float x, float target, float thickness, float dropoff)
    {
        float dist = abs(x - target);
        float closeness = 1.0 - min(1.0, dist / thickness);
        return pow(closeness, dropoff);
    }

    //Distance-squared is faster to compute in 2D+, but not in 1D.
    //Some noise is defined with the help of macros to work with any-dimensional data.
    float efficientDist(float a, float b) { return abs(b - a); }
    float efficientDist(vec2 a, vec2 b) { vec2 delta = b - a; return dot(delta, delta); }
    float efficientDist(vec3 a, vec3 b) { vec3 delta = b - a; return dot(delta, delta); }
    float efficientDist(vec4 a, vec4 b) { vec4 delta = b - a; return dot(delta, delta); }
    float realDist(float efficientDist, float posType) { return efficientDist; }
    float realDist(float efficientDist, vec2 posType) { return sqrt(efficientDist); }
    float realDist(float efficientDist, vec3 posType) { return sqrt(efficientDist); }
    float realDist(float efficientDist, vec4 posType) { return sqrt(efficientDist); }

    float sumComponents(float f) { return f; }
    float sumComponents(vec2 v) { return v.x + v.y; }
    float sumComponents(vec3 v) { return v.x + v.y + v.z; }
    float sumComponents(vec4 v) { return v.x + v.y + v.z + v.w; }

    //Gets the angle of the given vector, in the range 0-1.
    float angleT(vec2 dir) { return 0.5 + (0.5 * atan(dir.y, dir.x)/PI); }

    //Given a uniformly-distributed value, and another target value,
    //    biases the uniform value towards the target.
    //The "biasStrength" should be between 0 and 1.
    float applyBias(float x, float target, float biasStrength)
    {
        //Degenerative case if x=0.
        if (x == 0.0)
            return mix(x, target, biasStrength);

        //Get the "scale" of the target relative to x.
        //Multiplying x by this number would give exactly the target.
        float scale = target / x;

        //Weaken the "scale" by pushing it towards 1.0, then apply it to 'x'.
        //Make sure to respect the sign, in case 'x' or 'target' is negative.
        return x * sign(scale) * pow(abs(scale), biasStrength);
    }

    //Linearly interpolates between a beginning, midpoint, and endpoint.
    float tripleLerp(float a, float b, float c, float t)
    {
        vec3 lerpArgs = mix(
            vec3(a, b, INV_LERP(0.0, 0.5, t)),
            vec3(b, c, INV_LERP(0.5, 1.0, t)),
            t >= 0.5
        );
        return mix(lerpArgs.x, lerpArgs.y, lerpArgs.z);
    }
    vec3 tripleLerp(vec3 a, vec3 b, vec3 c, float t)
    {
        bool isFirstHalf = (t < 0.5);
        return isFirstHalf ?
                mix(a, b, INV_LERP(0.0, 0.5, t)) :
                mix(b, c, INV_LERP(0.5, 1.0, t));
    }
    //Smoothly interpolates between a beginning, midpoint, and endpoint.
    float tripleSmoothstep(float a, float b, float c, float t)
    {
        vec4 lerpArgs = mix(
            vec4(a, b, 0.0, 0.5),
            vec4(b, c, 0.5, 1.0),
            t >= 0.5
        );
        return mix(lerpArgs.x, lerpArgs.y, smoothstep(lerpArgs.z, lerpArgs.w, t));
    }
    //Interpolates between a beginning, midpoint, and endpoint, with aggressive smoothing.
    float tripleSmoothSmoothstep(float a, float b, float c, float t)
    {
        vec4 lerpArgs = mix(
            vec4(a, b, 0.0, 0.5),
            vec4(b, c, 0.5, 1.0),
            t >= 0.5
        );
        return mix(lerpArgs.x, lerpArgs.y,
                   smoothstep(0.0, 1.0, smoothstep(lerpArgs.z, lerpArgs.w, t)));
    }

    vec2 randUnitVector2(float uniformRandom)
    {
        float theta = uniformRandom * PI_2;
        return vec2(cos(theta), sin(theta));
    }
    vec3 randUnitVector3(vec2 uniformRandom2)
    {
        //Source: https://math.stackexchange.com/a/44691
        vec2 coords = mix(vec2(0, -1), vec2(PI_2, 1), uniformRandom2);
        float determinant = sqrt(1.0 - (coords.y * coords.y));
        return vec3(
            cos(coords.x) * determinant,
            sin(coords.x) * determinant,
            coords.y
        );
    }

    float linearizedDepth(float renderedDepth, float zNear, float zFar)
    {
        //Reference: https://stackoverflow.com/questions/51108596/linearize-depth

        //OpenGL depth is from -1 to +1, but coming from the texture it'll be 0 to 1.
        float z = -1.0 + (2.0 * renderedDepth);
        return (2.0 * zNear * zFar) / ((zFar + zNear) - (z * (zFar - zNear)));
    }

    //Applies a world matrix (i.e. nothing weird like projection/skew) to a direction,
    //    ignoring the translation component.
    vec3 transformDir(vec3 dir, mat4 transform)
    {
        return (transform * vec4(dir, 0.0)).xyz;
    }

    //Recreates world-space position from a fragment's depth, given some world-space data.
    //Also returns the distance between the camera and fragment, in the W channel.
    vec4 positionFromDepth(mat4 projectionMatrix,
                           vec3 camPos, vec3 camForward,
                           vec3 normalizedDirToFragment,
                           float bufferDepth)
    {
        //Reference: https://mynameismjp.wordpress.com/2010/09/05/position-from-depth-3/
        //           https://cs.gmu.edu/~jchen/cs662/fog.pdf
    
        float rawDepth = -1.0 + (2.0 * bufferDepth);
        float viewZ = projectionMatrix[3][2] / (rawDepth + projectionMatrix[2][2]);
        float distToCam = viewZ / dot(normalizedDirToFragment, camForward);
        return vec4((normalizedDirToFragment * distToCam) - camPos, distToCam);
    }


    // Below noise and hashing functions are mostly taken from the following shaders:
    //    https://www.shadertoy.com/view/7stBDH

    ////////////////////
    //    Hashing     //
    ////////////////////

    // A modified version of this: https://www.shadertoy.com/view/4djSRW
    //Works best with seed values in the hundreds.

    //Hash 1D from 1D-3D data
    float hashTo1(float p)
    {
        p = fract(p * .1031);
        p *= p + 33.33;
        p *= p + p;
        return fract(p);
    }
    float hashTo1(vec2 p)
    {
        vec3 p3  = fract(vec3(p.xyx) * .1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
    }
    float hashTo1(vec3 p3)
    {
        p3  = fract(p3 * .1031);
        p3 += dot(p3, p3.zyx + 31.32);
        return fract((p3.x + p3.y) * p3.z);
    }
    float hashTo1(vec4 p4) { return hashTo1(p4.xyz + p4.w); }

    //Hash 2D from 1D-3D data
    vec2 hashTo2(float p)
    {
        vec3 p3 = fract(vec3(p) * vec3(.1031, .1030, .0973));
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.xx+p3.yz)*p3.zy);
    }
    vec2 hashTo2(vec2 p)
    {
        vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
        p3 += dot(p3, p3.yzx+33.33);
        return fract((p3.xx+p3.yz)*p3.zy);
    }
    vec2 hashTo2(vec3 p3)
    {
        p3 = fract(p3 * vec3(.1031, .1030, .0973));
        p3 += dot(p3, p3.yzx+33.33);
        return fract((p3.xx+p3.yz)*p3.zy);
    }
    vec2 hashTo2(vec4 p4) { return hashTo2(p4.xyz + p4.w); }

    //Hash 3D from 1D-3D data
    vec3 hashTo3(float p)
    {
        vec3 p3 = fract(vec3(p) * vec3(.1031, .1030, .0973));
        p3 += dot(p3, p3.yzx+33.33);
        return fract((p3.xxy+p3.yzz)*p3.zyx); 
    }
    vec3 hashTo3(vec2 p)
    {
        vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
        p3 += dot(p3, p3.yxz+33.33);
        return fract((p3.xxy+p3.yzz)*p3.zyx);
    }
    vec3 hashTo3(vec3 p3)
    {
        p3 = fract(p3 * vec3(.1031, .1030, .0973));
        p3 += dot(p3, p3.yxz+33.33);
        return fract((p3.xxy + p3.yxx)*p3.zyx);
    }
    vec3 hashTo3(vec4 p4) { return hashTo3(p4.xyz + p4.w); }

    //Hash 4D from 1D-4D data
    vec4 hashTo4(float p)
    {
        vec4 p4 = fract(vec4(p) * vec4(.1031, .1030, .0973, .1099));
        p4 += dot(p4, p4.wzxy+33.33);
        return fract((p4.xxyz+p4.yzzw)*p4.zywx);
    }
    vec4 hashTo4(vec2 p)
    {
        vec4 p4 = fract(vec4(p.xyxy) * vec4(.1031, .1030, .0973, .1099));
        p4 += dot(p4, p4.wzxy+33.33);
        return fract((p4.xxyz+p4.yzzw)*p4.zywx);
    }
    vec4 hashTo4(vec3 p)
    {
        vec4 p4 = fract(vec4(p.xyzx)  * vec4(.1031, .1030, .0973, .1099));
        p4 += dot(p4, p4.wzxy+33.33);
        return fract((p4.xxyz+p4.yzzw)*p4.zywx);
    }
    vec4 hashTo4(vec4 p4)
    {
        p4 = fract(p4  * vec4(.1031, .1030, .0973, .1099));
        p4 += dot(p4, p4.wzxy+33.33);
        return fract((p4.xxyz+p4.yzzw)*p4.zywx);
    }


    ///////////////////////////////
    //    Value/Octave Noise     //
    ///////////////////////////////

    float valueNoise(float x, float seed)
    {
        float xMin = floor(x),
            xMax = ceil(x);

        float noiseMin = hashTo1(vec2(xMin, seed) * 450.0),
            noiseMax = hashTo1(vec2(xMax, seed) * 450.0);

        float t = x - xMin;
        //t = SMOOTHERSTEP(t); //Actually gives worse results due to
                            //  the dumb simplicity of the underlying noise

        return mix(noiseMin, noiseMax, t);
    }
    float valueNoise(vec2 x, float seed)
    {
        vec2 xMin = floor(x),
             xMax = ceil(x);
        vec4 xMinMax = vec4(xMin, xMax);

        vec2 t = x - xMin;
        //t = SMOOTHERSTEP(t); //Actually gives worse results due to
                            //  the dumb simplicity of the underlying noise

        #define VALUE_NOISE_2D(pos) hashTo1(vec3(pos, seed) * 450.0)
        return mix(mix(VALUE_NOISE_2D(xMinMax.xy),
                       VALUE_NOISE_2D(xMinMax.zy),
                       t.x),
                   mix(VALUE_NOISE_2D(xMinMax.xw),
                       VALUE_NOISE_2D(xMinMax.zw),
                       t.x),
                   t.y);
    }
    float valueNoise(vec3 p, float seed)
    {
        vec3 pMin = floor(p),
             pMax = ceil(p);

        vec3 t = p - pMin;
        //t = SMOOTHERSTEP(t); //Actually gives worse results due to
                               //  the dumb simplicity of the underlying noise

        #define VALUE_NOISE_3D(pos) hashTo1(vec4(pos, seed) * 450.0)
        #define VALUE_NOISE_3D_X(y, z) mix(VALUE_NOISE_3D(vec3(pMin.x, y, z)), \
                                           VALUE_NOISE_3D(vec3(pMax.x, y, z)), \
                                           t.x)
        #define VALUE_NOISE_3D_XY(z) mix(VALUE_NOISE_3D_X(pMin.y, z), \
                                         VALUE_NOISE_3D_X(pMax.y, z), \
                                         t.y)
        return mix(VALUE_NOISE_3D_XY(pMin.z),
                   VALUE_NOISE_3D_XY(pMax.z),
                   t.z);
    }

    //Octave noise behaves the same regardless of dimension.
    #define IMPL_OCTAVE_NOISE(x, outputVar, persistence, seed, nOctaves, noiseFunc, noiseMidArg, octaveValueMod) \
        float outputVar; { \
        float sum = 0.0,                                                 \
            scale = 1.0,                                               \
            nextWeight = 1.0,                                          \
            totalWeight = 0.0;                                         \
        for (int i = 0; i < nOctaves; ++i)                               \
        {                                                                \
            float octaveValue = noiseFunc((x) * scale,                   \
                                        noiseMidArg                    \
                                        (seed) + float(i));            \
            octaveValueMod;                                              \
            sum += octaveValue * nextWeight;                             \
            totalWeight += nextWeight;                                   \
                                                                        \
            nextWeight /= (persistence);                                 \
            scale *= (persistence);                                      \
        }                                                                \
        outputVar = sum / totalWeight;                                   \
    }
    float octaveNoise(float x, float seed, int nOctaves, float persistence) { IMPL_OCTAVE_NOISE(x, outNoise, persistence, seed, nOctaves, valueNoise, ,); return outNoise; }
    float octaveNoise(vec2 x, float seed, int nOctaves, float persistence) { IMPL_OCTAVE_NOISE(x, outNoise, persistence, seed, nOctaves, valueNoise, ,); return outNoise; }
    float octaveNoise(vec3 x, float seed, int nOctaves, float persistence) { IMPL_OCTAVE_NOISE(x, outNoise, persistence, seed, nOctaves, valueNoise, ,); return outNoise; }

    #define PERLIN_MAX(nDimensions) (sqrt(float(nDimensions)) / 2.0)
    float perlinNoise(float x, float seed)
    {
        float xMin = floor(x),
              xMax = ceil(x),
              t = x - xMin;

        float value = mix(t         * sign(hashTo1(vec2(xMin, seed) * 450.0) - 0.5),
                          (1.0 - t) * sign(hashTo1(vec2(xMax, seed) * 450.0) - 0.5),
                          SHARPENER(t));
        return INV_LERP(-PERLIN_MAX(1), PERLIN_MAX(1), value);
    }

    vec2 perlinGradient2(float t)
    {
        return randUnitVector2(t);
    }
    float perlinNoise(vec2 p, float seed)
    {
        vec2 pMin = floor(p),
             pMax = pMin + 1.0,
             t = p - pMin;
        vec4 pMinMax = vec4(pMin, pMax),
             tMinMax = vec4(t, p - pMax);

        #define PERLIN2_POINT(ab) dot(tMinMax.ab, \
                                    perlinGradient2(hashTo1(vec3(pMinMax.ab, seed) * 450.0)))
        float noiseMinXMinY = PERLIN2_POINT(xy),
            noiseMaxXMinY = PERLIN2_POINT(zy),
            noiseMinXMaxY = PERLIN2_POINT(xw),
            noiseMaxXMaxY = PERLIN2_POINT(zw);

        t = SHARPENER(t);
        float value = mix(mix(noiseMinXMinY, noiseMaxXMinY, t.x),
                        mix(noiseMinXMaxY, noiseMaxXMaxY, t.x),
                        t.y);
        return INV_LERP(-PERLIN_MAX(2), PERLIN_MAX(2), value);
    }

    vec3 perlinGradient3(vec2 t)
    {
        return randUnitVector3(t);
    }
    float perlinNoise(vec3 p, float seed)
    {
        vec3 pMin = floor(p),
             pMax = pMin + 1.0,
             tMin = p - pMin,
             tMax = p - pMax,
             t = tMin;

        t = SHARPENER(t);
        #define PERLIN3_NOISE(xx, yy, zz) dot(vec3(t##xx .x, t##yy .y, t##zz .z), \
                                              perlinGradient3(hashTo2(450.0 * vec4(seed, \
                                                p##xx .x, p##yy .y, p##zz .z \
                                              ))))
        #define PERLIN3_NOISE_X(yy, zz) mix(PERLIN3_NOISE(Min, yy, zz), PERLIN3_NOISE(Max, yy, zz), t.x)
        #define PERLIN3_NOISE_XY(zz) mix(PERLIN3_NOISE_X(Min, zz), PERLIN3_NOISE_X(Max, zz), t.y)
        #define PERLIN3_NOISE_XYZ mix(PERLIN3_NOISE_XY(Min), PERLIN3_NOISE_XY(Max), t.z)
        float value = PERLIN3_NOISE_XYZ;
        return INV_LERP(-PERLIN_MAX(3), PERLIN_MAX(3), value);
    }



    /////////////////////////
    //    Worley Noise     //
    /////////////////////////

    //Helper function for worley noise that finds the point in a cell.
    //Outputs its position, and returns whether or not it really exists.
    bool getWorleyPoint(float cell, float chanceOfPoint, float seed, out float pos)
    {
        vec2 rng = hashTo2(vec2(cell * 450.0, seed));
        pos = cell + rng.x;
        return (rng.y < chanceOfPoint);
    }
    bool getWorleyPoint(vec2 cell, float chanceOfPoint, float seed, out vec2 pos)
    {
        vec3 rng = hashTo3(vec3(cell * 450.0, seed));
        pos = cell + rng.xy;
        return (rng.z < chanceOfPoint);
    }
    bool getWorleyPoint(vec3 cell, float chanceOfPoint, float seed, out vec3 pos)
    {
        vec4 rng = hashTo4(vec4(cell * 450.0, seed));
        pos = cell + rng.xyz;
        return (rng.w < chanceOfPoint);
    }

    //Generates worley-noise points that might influence the given position.
    //See the below functions for common use-cases.
    void worleyPoints(float x, float chanceOfPoint, float seed,
                      out int outNPoints, out float outPoints[3]);
    void worleyPoints(vec2 x, float chanceOfPoint, float seed,
                      out int outNPoints, out vec2 outPoints[9]);
    void worleyPoints(vec3 x, float chanceOfPoint, float seed,
                      out int outNPoints, out vec3 outPoints[27]);
    //Implementation below:
    #define IMPL_WORLEY_START(T)                                    \
        T xCenter = floor(x),                                       \
        xMin = xCenter - 1.0,                                     \
        xMax = xCenter + 1.0;                                     \
        nPoints = 0;                                                \
        T nextPoint
    //end #define
    #define IMPL_WORLEY_POINT(cellPos)                                  \
        if (getWorleyPoint(cellPos, chanceOfPoint, seed, nextPoint))    \
            points[nPoints++] = nextPoint
    //end #define
    void worleyPoints(float x, float chanceOfPoint, float seed,
                      out int nPoints, out float points[3])
    {
        IMPL_WORLEY_START(float);
        IMPL_WORLEY_POINT(xMin);
        IMPL_WORLEY_POINT(xCenter);
        IMPL_WORLEY_POINT(xMax);
    }
    void worleyPoints(vec2 x, float chanceOfPoint, float seed,
                      out int nPoints, out vec2 points[9])
    {
        IMPL_WORLEY_START(vec2);

        IMPL_WORLEY_POINT(xMin);
        IMPL_WORLEY_POINT(xCenter);
        IMPL_WORLEY_POINT(xMax);

        IMPL_WORLEY_POINT(vec2(xMin.x, xCenter.y));
        IMPL_WORLEY_POINT(vec2(xMin.x, xMax.y));

        IMPL_WORLEY_POINT(vec2(xCenter.x, xMin.y));
        IMPL_WORLEY_POINT(vec2(xCenter.x, xMax.y));

        IMPL_WORLEY_POINT(vec2(xMax.x, xMin.y));
        IMPL_WORLEY_POINT(vec2(xMax.x, xCenter.y));
    }
    void worleyPoints(vec3 x, float chanceOfPoint, float seed,
                      out int nPoints, out vec3 points[27])
    {
        IMPL_WORLEY_START(vec3);

        IMPL_WORLEY_POINT(vec3(xMin.x, xMin.y, xMin.z));
        IMPL_WORLEY_POINT(vec3(xMin.x, xMin.y, xCenter.z));
        IMPL_WORLEY_POINT(vec3(xMin.x, xMin.y, xMax.z));
        IMPL_WORLEY_POINT(vec3(xMin.x, xCenter.y, xMin.z));
        IMPL_WORLEY_POINT(vec3(xMin.x, xCenter.y, xCenter.z));
        IMPL_WORLEY_POINT(vec3(xMin.x, xCenter.y, xMax.z));
        IMPL_WORLEY_POINT(vec3(xMin.x, xMax.y, xMin.z));
        IMPL_WORLEY_POINT(vec3(xMin.x, xMax.y, xCenter.z));
        IMPL_WORLEY_POINT(vec3(xMin.x, xMax.y, xMax.z));

        IMPL_WORLEY_POINT(vec3(xCenter.x, xMin.y, xMin.z));
        IMPL_WORLEY_POINT(vec3(xCenter.x, xMin.y, xCenter.z));
        IMPL_WORLEY_POINT(vec3(xCenter.x, xMin.y, xMax.z));
        IMPL_WORLEY_POINT(vec3(xCenter.x, xCenter.y, xMin.z));
        IMPL_WORLEY_POINT(vec3(xCenter.x, xCenter.y, xCenter.z));
        IMPL_WORLEY_POINT(vec3(xCenter.x, xCenter.y, xMax.z));
        IMPL_WORLEY_POINT(vec3(xCenter.x, xMax.y, xMin.z));
        IMPL_WORLEY_POINT(vec3(xCenter.x, xMax.y, xCenter.z));
        IMPL_WORLEY_POINT(vec3(xCenter.x, xMax.y, xMax.z));

        IMPL_WORLEY_POINT(vec3(xMax.x, xMin.y, xMin.z));
        IMPL_WORLEY_POINT(vec3(xMax.x, xMin.y, xCenter.z));
        IMPL_WORLEY_POINT(vec3(xMax.x, xMin.y, xMax.z));
        IMPL_WORLEY_POINT(vec3(xMax.x, xCenter.y, xMin.z));
        IMPL_WORLEY_POINT(vec3(xMax.x, xCenter.y, xCenter.z));
        IMPL_WORLEY_POINT(vec3(xMax.x, xCenter.y, xMax.z));
        IMPL_WORLEY_POINT(vec3(xMax.x, xMax.y, xMin.z));
        IMPL_WORLEY_POINT(vec3(xMax.x, xMax.y, xCenter.z));
        IMPL_WORLEY_POINT(vec3(xMax.x, xMax.y, xMax.z));
    }

    //Variant 1: straight-line distance, to the nearest point.
    float worley1(float x, float chanceOfPoint, float seed);
    float worley1(vec2 x, float chanceOfPoint, float seed);
    float worley1(vec3 x, float chanceOfPoint, float seed);
    //Implementation below:
    #define IMPL_WORLEY1(T, nMaxPoints)                                              \
    float worley1(T x, float chanceOfPoint, float seed) {                            \
        int nPoints;                                                                 \
        T points[nMaxPoints];                                                        \
        worleyPoints(x, chanceOfPoint, seed, nPoints, points);                       \
                                                                                    \
        if (nPoints < 1)                                                             \
            return 1.0; /* The nearest point is far away */                          \
                                                                                    \
        float minDist = 9999999.9;                                                   \
        for (int i = 0; i < min(nMaxPoints, nPoints); ++i) /*Specify a hard-coded cap,  */            \
        {                                                  /*   in case it helps with unrolling   */  \
            minDist = min(minDist, efficientDist(points[i], x));                     \
        }                                                                            \
        return min(realDist(minDist, points[0]), 1.0);                \
    }
    //end #define
    IMPL_WORLEY1(float, 3)
    IMPL_WORLEY1(vec2,  9)
    IMPL_WORLEY1(vec3,  27)

    //Variant 2: manhattan distance, to the nearest point.
    float worley2(float x, float chanceOfPoint, float seed);
    float worley2(vec2 x, float chanceOfPoint, float seed);
    float worley2(vec3 x, float chanceOfPoint, float seed);
    //Implementation below:
    #define IMPL_WORLEY2(T, nMaxPoints)                                              \
    float worley2(T x, float chanceOfPoint, float seed) {                            \
        int nPoints;                                                                 \
        T points[nMaxPoints];                                                        \
        worleyPoints(x, chanceOfPoint, seed, nPoints, points);                       \
                                                                                    \
        if (nPoints < 1)                                                             \
            return 1.0; /* The nearest point is far away */                          \
                                                                                    \
        float minDist = 9999999.9;                                                   \
        for (int i = 0; i < min(nMaxPoints, nPoints); ++i) /* Specify a hard-coded cap,  */           \
        {                                                  /*   in case it helps with unrolling   */  \
            minDist = min(minDist, sumComponents(abs(points[i] - x)));               \
        }                                                                            \
        return min(realDist(minDist, points[0]), 1.0);                               \
    }
    //end #define
    IMPL_WORLEY2(float, 3)
    IMPL_WORLEY2(vec2,  9)
    IMPL_WORLEY2(vec3,  27)

    //Variant 3: straight-line distance, to the second- nearest point.
    float worley3(float x, float chanceOfPoint, float seed);
    float worley2(vec2 x, float chanceOfPoint, float seed);
    float worley3(vec3 x, float chanceOfPoint, float seed);
    //Implementation below:
    #define IMPL_WORLEY3(T, nMaxPoints)                                              \
    float worley3(T x, float chanceOfPoint, float seed) {                            \
        int nPoints;                                                                 \
        T points[nMaxPoints];                                                        \
        worleyPoints(x, chanceOfPoint, seed, nPoints, points);                       \
                                                                                    \
        if (nPoints < 1)                                                             \
            return 1.0; /* The nearest point is far away */                          \
                                                                                    \
        float minDist1 = 9999999.9,                                                  \
            minDist2 = 9999999.9;                                                  \
        for (int i = 0; i < min(nMaxPoints, nPoints); ++i) /* Specify a hard-coded cap,  */           \
        {                                                  /*   in case it helps with unrolling   */  \
            float newD = efficientDist(points[i], x);                                \
            if (newD < minDist1) {                                                   \
                minDist2 = minDist1; minDist1 = newD;                                \
            } else if (newD < minDist2) {                                            \
                minDist2 = newD;                                                     \
            }                                                                        \
        }                                                                            \
        return SATURATE(min(realDist(minDist2, points[0]) / 1.5, 1.0));                    \
    }
    //end #define
    IMPL_WORLEY3(float, 3)
    IMPL_WORLEY3(vec2,  9)
    IMPL_WORLEY3(vec3,  27)

    //TODO: More variants

    //Octave worley noise:
    float octaveWorley1Noise(float x, float seed, int nOctaves, float persistence, float chanceOfCell) { IMPL_OCTAVE_NOISE(x, outNoise, persistence, seed, nOctaves, worley1, chanceOfCell COMMA, ); return outNoise; }
    float octaveWorley1Noise(vec2 x, float seed, int nOctaves, float persistence, float chanceOfCell) { IMPL_OCTAVE_NOISE(x, outNoise, persistence, seed, nOctaves, worley1, chanceOfCell COMMA, ); return outNoise; }
    float octaveWorley2Noise(float x, float seed, int nOctaves, float persistence, float chanceOfCell) { IMPL_OCTAVE_NOISE(x, outNoise, persistence, seed, nOctaves, worley2, chanceOfCell COMMA, ); return outNoise; }
    float octaveWorley2Noise(vec2 x, float seed, int nOctaves, float persistence, float chanceOfCell) { IMPL_OCTAVE_NOISE(x, outNoise, persistence, seed, nOctaves, worley2, chanceOfCell COMMA, ); return outNoise; }

    //TODO: Profile worley noise compared to a more hard-coded implementation.

    /////////////////////////////////////////////////////////////////

    #endif
"""