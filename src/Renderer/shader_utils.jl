const SHADER_CODE_UTILS = """
#ifndef SHADER_CODE_UTILS
#define SHADER_CODE_UTILS

    #define COMMA ,

    #define PI (3.14159265)
    #define PI_2 (PI * 2.0)
    #define INV_LERP(a, b, x) (((x) - (a)) / ((b) - (a))

    //Inigo Quilez's idea: https://iquilezles.org/articles/palettes/
    //Recommend using the following values, to start:
    //   * scaler = 0.5
    //   * bias = 0.5
    //   * oscillation between 0 and 3
    //   * phase between 0 and 1 
    #define PROCEDURAL_GRADIENT(t, bias, scaler, oscillation, phase) \
        clamp(((bias) + ((scaler) * cos(PI_2 * (((oscillation) * (t)) + (phase))))), \
              0.0, 1.0)

#endif
"""