#ifndef UNIVERSAL_LIGHTING_INCLUDED
#define UNIVERSAL_LIGHTING_INCLUDED

#include "BRDF.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Debug/Debugging3D.hlsl"
#include "GlobalIllumination.hlsl"
#include "RealtimeLights.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/AmbientOcclusion.hlsl"
#include "DBuffer.hlsl"
// #include "Assets/ORION_XX/PBR/PBR Shader/PBRFunction.hlsl"

#if defined(LIGHTMAP_ON)
    #define DECLARE_LIGHTMAP_OR_SH(lmName, shName, index) float2 lmName : TEXCOORD##index
    #define OUTPUT_LIGHTMAP_UV(lightmapUV, lightmapScaleOffset, OUT) OUT.xy = lightmapUV.xy * lightmapScaleOffset.xy + lightmapScaleOffset.zw;
    #define OUTPUT_SH(normalWS, OUT)
#else
    #define DECLARE_LIGHTMAP_OR_SH(lmName, shName, index) half3 shName : TEXCOORD##index
    #define OUTPUT_LIGHTMAP_UV(lightmapUV, lightmapScaleOffset, OUT)
    #define OUTPUT_SH(normalWS, OUT) OUT.xyz = SampleSHVertex(normalWS)
#endif

///////////////////////////////////////////////////////////////////////////////
//                      Lighting Functions          照明功能                  //
///////////////////////////////////////////////////////////////////////////////
//基础兰伯特模型，+颜色
half3 LightingLambert(half3 lightColor, half3 lightDir, half3 normal)
{
    half NdotL = saturate(dot(normal, lightDir));
    return lightColor * NdotL;
}


// 头发高光计算方式
half3 HariSpeculer(BRDFData brdfData, half3 normalWS, half3 lightDirectionWS, half3 viewDirectionWS , half2 uv)
{
    half3 HVLDir = normalize(lightDirectionWS + viewDirectionWS);      // 半角向量
    half NdotH = saturate( dot(normalWS,HVLDir));
    half hairSpecStrength = pow(NdotH,_HairSpeRange);   
    
    half uvOffset = - viewDirectionWS.y * 0.05;
    half hairSpecTex = SAMPLE_TEXTURE2D(_MaskMap, sampler_MaskMap, uv).g;  // 限定范围   //float2(uv.x, uv.y + uvOffset) 
    hairSpecTex = saturate((hairSpecTex-0.5)*2);
    
    half3 hairSpecColor = hairSpecTex * hairSpecStrength * _SpecularColor ;
    
    return hairSpecColor;
}


//光照计算——————————————
half3 Lightwork(BRDFData brdfData, BRDFData brdfDataClearCoat, 
                Light light, half3 normalWS, half3 viewDirectionWS, 
                half clearCoatMask, half lightIndex, half shadowoffset, half2 UV)
{   
    half lightAttenuation = light.distanceAttenuation * light.shadowAttenuation;
    half NdotL = dot(normalWS, light.direction); 
    
    // 采样头发阴影的偏移
    #if defined(_ISHAIR)
        NdotL += shadowoffset ;
    #endif

    half HalfNdotL  = NdotL*0.5+0.5;
    HalfNdotL = lerp(HalfNdotL,smoothstep(0,1,HalfNdotL),_ShadowSmooth);
    NdotL = HalfNdotL*2-1;
    
    // 对暗面和亮面分别控制颜色
    half3 Ramp = lerp(_ShadowColor.rgb, _FrontColor.rgb, saturate(NdotL));

    // 采样Ramp贴图
    if (lightIndex == -1)   // 主光下用ramp
    {   
        half2 RampUV = (0.5,HalfNdotL);
        half4 RampColor = SAMPLE_TEXTURE2D(_RampMap, sampler_RampMap,RampUV); 
        Ramp = lerp(Ramp,RampColor.rgb,_RampScale);
    }

    half3 radiance = light.color * (lightAttenuation * Ramp);    // 光颜色   有衰减影响


    //高光计算 
    half3 specularlight = DirectBRDFSpecular(brdfData, normalWS, light.direction, viewDirectionWS) ;
    specularlight *=  brdfData.specular ;


    return (brdfData.diffuse + specularlight) * radiance;

}



// 计算 逐顶点光照 ; 在顶点着色器中计算所有附加光源对当前顶点的漫反射光照贡献
half3 VertexLighting(float3 positionWS, half3 normalWS)
{
    half3 vertexLightColor = half3(0.0, 0.0, 0.0);

#ifdef _ADDITIONAL_LIGHTS_VERTEX
    uint lightsCount = GetAdditionalLightsCount();
    uint meshRenderingLayers = GetMeshRenderingLayer();

    LIGHT_LOOP_BEGIN(lightsCount)
        Light light = GetAdditionalLight(lightIndex, positionWS);

#ifdef _LIGHT_LAYERS
    if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
#endif
    {
        half3 lightColor = light.color * light.distanceAttenuation;
        vertexLightColor += LightingLambert(lightColor, light.direction, normalWS);
    }

    LIGHT_LOOP_END
#endif

    return vertexLightColor;
}



// 灯光数据  汇总所有光照贡献 的通用数据结构
struct LightingData
{
    half3 giColor;                  //全局光照（GI） 贡献，包含间接光（Light Probes/光照贴图）和漫反射环境光
    half3 mainLightColor;           //主光源（如平行光） 的直接光照贡献（漫反射 + 高光）
    half3 additionalLightsColor;    //所有附加光源（点光、聚光） 的叠加光照贡献（逐像素或逐顶点计算）
    half3 vertexLightingColor;      //逐顶点光照 的贡献（通常用于性能优化，替代逐像素附加光源）
    half3 emissionColor;            //自发光 颜色
};



// 所有光整合  除去主光
half3 CalculateLightingColor(LightingData lightingData, half3 albedo)
{
    half3 lightingColor = 0;

    if (IsOnlyAOLightingFeatureEnabled())
    {
        return lightingData.giColor; // Contains white + AO
    }

    if (IsLightingFeatureEnabled(DEBUGLIGHTINGFEATUREFLAGS_GLOBAL_ILLUMINATION))
    {
        lightingColor += lightingData.giColor ; // 背景影响
    }

    // if (IsLightingFeatureEnabled(DEBUGLIGHTINGFEATUREFLAGS_MAIN_LIGHT))
    // {
    //     lightingColor += lightingData.mainLightColor;
    // }

    if (IsLightingFeatureEnabled(DEBUGLIGHTINGFEATUREFLAGS_ADDITIONAL_LIGHTS))
    {
        lightingColor += lightingData.additionalLightsColor;
    }

    if (IsLightingFeatureEnabled(DEBUGLIGHTINGFEATUREFLAGS_VERTEX_LIGHTING))
    {
        lightingColor += lightingData.vertexLightingColor;
    }

    lightingColor *= albedo;

    if (IsLightingFeatureEnabled(DEBUGLIGHTINGFEATUREFLAGS_EMISSION))
    {
        lightingColor += lightingData.emissionColor;
    }

    return lightingColor;
}





half4 CalculateFinalColor(LightingData lightingData, half alpha)
{
    half3 finalColor = CalculateLightingColor(lightingData, 1);

    return half4(finalColor, alpha);
}

// 计算雾
half4 CalculateFinalColor(LightingData lightingData, half3 albedo, half alpha, float fogCoord)
{
    #if defined(_FOG_FRAGMENT)
        #if (defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2))
        float viewZ = -fogCoord;
        float nearToFarZ = max(viewZ - _ProjectionParams.y, 0);
        half fogFactor = ComputeFogFactorZ0ToFar(nearToFarZ);
    #else
        half fogFactor = 0;
        #endif
    #else
        half fogFactor = fogCoord;
    #endif
    half3 lightingColor = CalculateLightingColor(lightingData, albedo);
    half3 finalColor = MixFog(lightingColor, fogFactor);
     
    return half4(finalColor, alpha);
}


// 实现全局光照（GI） 和 自发光（Emission）部分   其他光照贡献（如主光源、附加光源）被初始化为 0
LightingData CreateLightingData(InputData inputData, SurfaceData surfaceData)
{
    LightingData lightingData;

    lightingData.giColor = inputData.bakedGI;
    lightingData.emissionColor = surfaceData.emission;
    lightingData.vertexLightingColor = 0;
    lightingData.mainLightColor = 0;
    lightingData.additionalLightsColor = 0;

    return lightingData;
}

half3 CalculateBlinnPhong(Light light, InputData inputData, SurfaceData surfaceData)
{
    half3 attenuatedLightColor = light.color * (light.distanceAttenuation * light.shadowAttenuation);
    half3 lightDiffuseColor = LightingLambert(attenuatedLightColor, light.direction, inputData.normalWS);

    half3 lightSpecularColor = half3(0,0,0);
    #if defined(_SPECGLOSSMAP) || defined(_SPECULAR_COLOR)
    half smoothness = exp2(10 * surfaceData.smoothness + 1);

    lightSpecularColor += LightingSpecular(attenuatedLightColor, light.direction, inputData.normalWS, inputData.viewDirectionWS, half4(surfaceData.specular, 1), smoothness);
    #endif

#if _ALPHAPREMULTIPLY_ON
    return lightDiffuseColor * surfaceData.albedo * surfaceData.alpha + lightSpecularColor;
#else
    return lightDiffuseColor * surfaceData.albedo + lightSpecularColor;
#endif
}






#endif
