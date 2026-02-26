#ifndef UT_INDIRECTINPUT_INPUT_INCLUDED
#define UT_INDIRECTINPUT_INPUT_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

#ifdef _UT_INSTANCING_ON
    uniform float _VegDataMapRes;
    uniform float _InstanceIDOffsetMapRes;
    uniform uint _DrawCallIndex;
    TEXTURE2D_FLOAT(_VegDataMap);								SAMPLER(sampler_VegDataMap);
    TEXTURE2D_FLOAT(_InstanceIDOffsetMap);						SAMPLER(sampler_InstanceIDOffsetMap);
#endif

float4 DecodeFloatRGBAFloat(float4 rgba)
{
    uint4 val = uint4(rgba * 4294967295.0);
    return asfloat(val);
}

uint DecodeIntRGBAFloat(float r)
{
    uint val = uint(r * 4294967295.0);
    return val;
}

#endif // UNIVERSAL_INPUT_SURFACE_PBR_INCLUDED
