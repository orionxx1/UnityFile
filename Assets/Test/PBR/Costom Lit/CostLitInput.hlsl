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
half _NormalScale;
half _OcclusionScale;
half _Surface;
CBUFFER_END

TEXTURE2D(_BaseMap);            SAMPLER(sampler_BaseMap);
float4 _BaseMap_TexelSize;      float4 _BaseMap_MipInfo;
TEXTURE2D(_MaskMap);            SAMPLER(sampler_MaskMap);
TEXTURE2D(_BumpMap);            SAMPLER(sampler_BumpMap);
TEXTURE2D(_EmissionMap);        SAMPLER(sampler_EmissionMap);


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
