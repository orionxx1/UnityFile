#ifndef UNIVERSAL_LIGHTING_INCLUDED
#define UNIVERSAL_LIGHTING_INCLUDED

#include "BRDF.hlsl"
#include "Debugging3D.hlsl"
#include "GlobalIllumination.hlsl"
#include "RealtimeLights.hlsl"
#include "AmbientOcclusion.hlsl"
#include "DBuffer.hlsl"

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

half3 LightingSpecular(half3 lightColor, half3 lightDir, half3 normal, half3 viewDir, half4 specular, half smoothness)
{
    float3 halfVec = SafeNormalize(float3(lightDir) + float3(viewDir));
    half NdotH = half(saturate(dot(normal, halfVec)));
    half modifier = pow(NdotH, smoothness);
    // NOTE: In order to fix internal compiler error on mobile platforms, this needs to be float3
    float3 specularReflection = specular.rgb * modifier;
    return lightColor * specularReflection;
}






//光照计算，强度衰减，颜色衰减————————————————————————————————
half3 LightingPhysicallyBased(BRDFData brdfData, BRDFData brdfDataClearCoat,
                              half3 lightColor, half3 lightDirectionWS, half lightAttenuation,
                              half3 normalWS, half3 viewDirectionWS,
                              half clearCoatMask, bool specularHighlightsOff)
{
    half NdotL = saturate(dot(normalWS, lightDirectionWS));      
    half3 radiance = lightColor * (lightAttenuation * NdotL);    // 光颜色   有衰减影响
    half3 brdf = brdfData.diffuse;  //自身颜色
    
    //直接光镜面反射计算——————
    half3 specularlight = DirectBRDFSpecular(brdfData, normalWS, lightDirectionWS, viewDirectionWS);    
    
    //控制高光启用
    #ifndef _SPECULARHIGHLIGHTS_OFF
        [branch] if (!specularHighlightsOff)
    {
        brdf += brdfData.specular * specularlight;
    }
    #endif // _SPECULARHIGHLIGHTS_OFF

    return brdf * radiance;
}

half3 LightingPhysicallyBased(BRDFData brdfData, BRDFData brdfDataClearCoat, Light light, half3 normalWS, half3 viewDirectionWS, half clearCoatMask, bool specularHighlightsOff)
{
    return LightingPhysicallyBased(brdfData, brdfDataClearCoat, light.color, light.direction, light.distanceAttenuation * light.shadowAttenuation, normalWS, viewDirectionWS, clearCoatMask, specularHighlightsOff);
}

// Backwards compatibility      向后兼容性
half3 LightingPhysicallyBased(BRDFData brdfData, Light light, half3 normalWS, half3 viewDirectionWS)
{
    // 判断高光是否禁用
    #ifdef _SPECULARHIGHLIGHTS_OFF
    bool specularHighlightsOff = true;
#else
    bool specularHighlightsOff = false;
#endif
    const BRDFData noClearCoat = (BRDFData)0;   //  禁用 Clear Coat（清漆层）  声明一个名为 noClearCoat 的常量结构体 
    return LightingPhysicallyBased(brdfData, noClearCoat, light, normalWS, viewDirectionWS, 0.0, specularHighlightsOff);
}


half3 LightingPhysicallyBased(BRDFData brdfData, half3 lightColor, half3 lightDirectionWS, half lightAttenuation, half3 normalWS, half3 viewDirectionWS)
{
    Light light;
    light.color = lightColor;
    light.direction = lightDirectionWS;
    light.distanceAttenuation = lightAttenuation;
    light.shadowAttenuation   = 1;
    return LightingPhysicallyBased(brdfData, light, normalWS, viewDirectionWS);
}

half3 LightingPhysicallyBased(BRDFData brdfData, Light light, half3 normalWS, half3 viewDirectionWS, bool specularHighlightsOff)
{
    const BRDFData noClearCoat = (BRDFData)0;
    return LightingPhysicallyBased(brdfData, noClearCoat, light, normalWS, viewDirectionWS, 0.0, specularHighlightsOff);
}

half3 LightingPhysicallyBased(BRDFData brdfData, half3 lightColor, half3 lightDirectionWS, half lightAttenuation, half3 normalWS, half3 viewDirectionWS, bool specularHighlightsOff)
{
    Light light;
    light.color = lightColor;
    light.direction = lightDirectionWS;
    light.distanceAttenuation = lightAttenuation;
    light.shadowAttenuation   = 1;
    return LightingPhysicallyBased(brdfData, light, viewDirectionWS, specularHighlightsOff, specularHighlightsOff);
}





// 计算 逐顶点光照 ; 在顶点着色器中计算所有附加光源对当前顶点的漫反射光照贡献——————————————————
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


// 所有光整合————————————————————————
half3 CalculateLightingColor(LightingData lightingData, half3 albedo)
{
    half3 lightingColor = 0;

    if (IsOnlyAOLightingFeatureEnabled())
    {
        return lightingData.giColor; // Contains white + AO
    }

    if (IsLightingFeatureEnabled(DEBUGLIGHTINGFEATUREFLAGS_GLOBAL_ILLUMINATION))
    {
        lightingColor += lightingData.giColor;
    }

    if (IsLightingFeatureEnabled(DEBUGLIGHTINGFEATUREFLAGS_MAIN_LIGHT))
    {
        lightingColor += lightingData.mainLightColor;
    }

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


// 计算雾————————————————————————
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


// ——————————————————————————
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





////////////////////////////////////////////////////////////////////////////////
/// PBR lighting...             PBR实现
////////////////////////////////////////////////////////////////////////////////
half4 UniversalFragmentPBR(InputData inputData, SurfaceData surfaceData)
{
    // 高光的开关，这个宏可以在材质上开和关
    #if defined(_SPECULARHIGHLIGHTS_OFF)
        bool specularHighlightsOff = true;
    #else
        bool specularHighlightsOff = false;
    #endif

    BRDFData brdfData;

    // BRDF参数初始化
    InitializeBRDFData(surfaceData, brdfData);


    // 定义debug输出————————————————
    #if defined(DEBUG_DISPLAY)
    half4 debugColor;

    if (CanDebugOverrideOutputColor(inputData, surfaceData, brdfData, debugColor))
    {
        return debugColor;
    }
    #endif


    half4 shadowMask = CalculateShadowMask(inputData);                                          //计算 阴影遮罩
    AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData, surfaceData);     //直接光的遮蔽和间接光的遮蔽。和AO贴图取一个最小值 
    uint meshRenderingLayers = GetMeshRenderingLayer();                                         // 灯光影响层级
    Light mainLight = GetMainLight(inputData, shadowMask, aoFactor);                            //获取主光阴影衰减和光照效果...
    //获取主光源数据:方向,距离阴影衰减（主光源默认为1，有距离衰减的光源才有渐变值）,光源颜色,阴影遮罩
    //如果传入了环境光遮蔽并且开启了SSAO（屏幕空间环境光遮蔽）它还能够帮你合并计算出最终的环境光遮蔽
    //  暂时去掉主光自阴影———————
    //  mainLight.shadowAttenuation = 1;  

    // 混合实时全局光照（Realtime GI）和烘焙全局光照（Baked GI）   不包含AO
    MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI);

    // 实现全局光照（GI）和 自发光部分   其他光照贡献（如主光源、附加光源）被初始化为 0
    LightingData lightingData = CreateLightingData(inputData, surfaceData);
    
    // 全局光照计算  环境漫反射和环境镜面反射
    lightingData.giColor = GlobalIllumination(brdfData, 
                                              inputData.bakedGI, 
                                              aoFactor.indirectAmbientOcclusion, 
                                              inputData.positionWS,
                                              inputData.normalWS, 
                                              inputData.viewDirectionWS, 
                                              inputData.normalizedScreenSpaceUV);

                                                  
    // 主灯光影响下的模型颜色  —————————————————————                                       
    // 检查主光是否影响当前物体的渲染层（meshRenderingLayers）
    #ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(mainLight.layerMask, meshRenderingLayers))
    #endif
        {
             // 计算主灯光影响下的模型颜色， 包括强度衰减，颜色衰减
            lightingData.mainLightColor = LightingPhysicallyBased(brdfData, mainLight,
                                                                  inputData.normalWS, 
                                                                  inputData.viewDirectionWS,
                                                                  specularHighlightsOff);
        }

    // 额外灯光影响下的模型颜色  ————————————————————— 
    // 是否定义了额外光源
    #if defined(_ADDITIONAL_LIGHTS)
    uint pixelLightCount = GetAdditionalLightsCount();

    //处理 聚簇光照（Clustered Lighting） 的循环结构
    #if USE_FORWARD_PLUS
    for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
    {
        FORWARD_PLUS_SUBTRACTIVE_LIGHT_CHECK
        
        //获取 附加光源（Additional Lights） 数据
        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);

        // 检查 Light 是否影响当前物体的渲染层（meshRenderingLayers）
        #ifdef _LIGHT_LAYERS
            if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
        #endif
            {
                // 计算灯光影响，强度衰减，颜色衰减
                lightingData.additionalLightsColor += \LightingPhysicallyBased(brdfData, 
                                                                        light,
                                                                        nputData.normalWS, 
                                                                        inputData.viewDirectionWS,
                                                                        specularHighlightsOff);
            }
        }
    #endif



    // 额外逐像素光源计算——————————————————————————
    LIGHT_LOOP_BEGIN(pixelLightCount)
    Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);

    // 检查 mainLight 是否影响当前物体的渲染层（meshRenderingLayers）
    #ifdef _LIGHT_LAYERS
            if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))     //获得的光源数量
    #endif
            {
                lightingData.additionalLightsColor += LightingPhysicallyBased(brdfData, 
                                                                              light,
                                                                              inputData.normalWS, 
                                                                              inputData.viewDirectionWS,
                                                                              specularHighlightsOff);
            }
    LIGHT_LOOP_END
    #endif

    //顶点光照————————————————————————
    #if defined(_ADDITIONAL_LIGHTS_VERTEX)
    lightingData.vertexLightingColor += inputData.vertexLighting * brdfData.diffuse;
    #endif

    // 整合所有光照
    #if REAL_IS_HALF
        // Clamp any half.inf+ to HALF_MAX
        return min(CalculateFinalColor(lightingData, surfaceData.alpha), HALF_MAX);
    #else
        return CalculateFinalColor(lightingData, surfaceData.alpha);
    #endif

}


#endif
