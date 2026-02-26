#ifndef UNIVERSAL_SHADOW_CASTER_PASS_INCLUDED
#define UNIVERSAL_SHADOW_CASTER_PASS_INCLUDED

#include "LitInput.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

// Shadow Casting Light geometric parameters. These variables are used when applying the shadow Normal Bias and are set by UnityEngine.Rendering.Universal.ShadowUtils.SetupShadowCasterConstantBuffer in com.unity.render-pipelines.universal/Runtime/ShadowUtils.cs
// For Directional lights, _LightDirection is used when applying shadow Normal Bias.
// For Spot lights and Point lights, _LightPosition is used to compute the actual light direction because it is different at each shadow caster geometry vertex.
float3 _LightDirection;
float3 _LightPosition;

struct Attributes
{
    float4 positionOS   : POSITION;
    float3 normalOS     : NORMAL;
    float2 texcoord     : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};


struct Varyings
{
    float2 uv           : TEXCOORD0;
    float4 positionCS   : SV_POSITION;
};

//获取阴影裁剪空间下位置  
float4 GetShadowPositionHClip(Attributes input)
{
    float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
    float3 normalWS = TransformObjectToWorldNormal(input.normalOS);

    // 获取光线方向
    // 是否启用了 点光源阴影
    #if _CASTING_PUNCTUAL_LIGHT_SHADOW
        float3 lightDirectionWS = normalize(_LightPosition - positionWS);   //点光光线方向 需要用世界空间位置
    #else
        float3 lightDirectionWS = _LightDirection;
    #endif

    // 计算顶点在裁剪空间的位置，并应用阴影偏移
    float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
    // ApplyShadowBias：        应用阴影偏移（Shadow Bias），解决 阴影痤疮（Shadow Acne） 和 悬浮阴影（Peter Panning）
    // TransformWorldToHClip：  将偏移后的世界空间位置转换到裁剪空间

    // 确保裁剪空间的 Z 值不会超出平台的近裁剪面（Near Clip Plane）限制
    // 主要处理两种情况：Reversed-Z 平台 / 传统 Z 平台
    #if UNITY_REVERSED_Z
        positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
    #else
        positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
    #endif

    return positionCS;
}

// 阴影投射  将模型顶点转换到阴影贴图空间
Varyings ShadowPassVertex(Attributes input)
{
    Varyings output;
    UNITY_SETUP_INSTANCE_ID(input);   //启用GPU实例化时，正确处理每个实例的ID

    output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);  // 应用纹理的缩放和偏移
    output.positionCS = GetShadowPositionHClip(input);    // 获取阴影裁剪空间下位置
    
    return output;
}




// 阴影投射  同时处理阴影生成时的 Alpha裁剪
half4 ShadowPassFragment(Varyings input) : SV_TARGET
{
    // Alpha测试
    half4 alphy = half4(SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv)) ;
    Alpha(alphy.a, _BaseColor, _Cutoff);  //alphy裁剪

    return 0;  // 实际颜色值不影响阴影深度
}

#endif

