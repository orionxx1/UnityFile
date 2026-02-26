#ifndef UNIVERSAL_LIT_INPUT_INCLUDED
#define UNIVERSAL_LIT_INPUT_INCLUDED
#include "Core.hlsl"
#include "SurfaceData.hlsl"

CBUFFER_START(UnityPerMaterial)
float4 _BaseMap_ST;
half4  _BaseColor;
half4 _SpecularColor;
half4 _EmissionColor;
half _Cutoff;
half _Roughness;
half _RoughnessDef;
half _Metallic;
half _MetallicDef;
half _OcclusionScale;
half _NormalScale;
half _HeightScale;
half _Surface;

half4 _NoiseMap_ST;
half _Wetness;

half _SplatsSize;
half _SplatsIntensity;
half _SplatsNoise;
half _SplatOffest;
half _SplatsScale;
half _SplatsSpeed;
half _SplatsHeight;

half _DropletsSize;
half _DropletsIntensity;
half _DropletsNoise;
half _DropletMaxLength;
half _DropletMinLength;
half _DropletSpeed;
half _DropletHeight;

CBUFFER_END

TEXTURE2D(_BaseMap);            SAMPLER(sampler_BaseMap);
half4 _BaseMap_TexelSize;       half4 _BaseMap_MipInfo;
TEXTURE2D(_MaskMap);            SAMPLER(sampler_MaskMap);
TEXTURE2D(_BumpMap);            SAMPLER(sampler_BumpMap);
TEXTURE2D(_EmissionMap);        SAMPLER(sampler_EmissionMap);
TEXTURE2D(_NoiseMap);           SAMPLER(sampler_NoiseMap);


half Alpha(half Alpha, half4 color, half cutoff)
{
    half alpha = Alpha * color.a;

    #if defined(_ALPHATEST_ON)
        if (IsAlphaDiscardEnabled())
            alpha = AlphaClip(alpha, cutoff + offset);
    #endif

    return alpha;
}


#endif 
