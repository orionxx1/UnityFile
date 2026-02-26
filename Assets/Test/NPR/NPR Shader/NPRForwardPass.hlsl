#ifndef UNIVERSAL_FORWARD_LIT_PASS_INCLUDED
#define UNIVERSAL_FORWARD_LIT_PASS_INCLUDED

#include "Lighting.hlsl"

// 顶点数据————————————————
struct Attributes
{
    float4 positionOS   : POSITION;
    float3 normalOS     : NORMAL;
    float4 tangentOS    : TANGENT;
    float2 texcoord     : TEXCOORD0;
    float4 VertexColor  :COLOR;
    float2 staticLightmapUV   : TEXCOORD1;
    float2 dynamicLightmapUV  : TEXCOORD2;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

// 片元数据————————————————————
struct Varyings
{
    float4 positionCS               : SV_POSITION;  // 裁切空间位置 
    float2 uv                       : TEXCOORD0;    // UV
    float3 positionWS               : TEXCOORD1;    // 世界空间位置
    float3 normalWS                 : TEXCOORD2;    // 世界空间法线
    half4 tangentWS                 : TEXCOORD3;    // 世界空间切线   xyz: tangent, w: sign
    float4 VertexColor              : TEXCOORD4;    // 顶点颜色
    float4 positionNDC              : TEXCOORD5; 

#ifdef _ADDITIONAL_LIGHTS_VERTEX                    // 顶点光照
    half4 fogFactorAndVertexLight   : TEXCOORD6;    // x: fogFactor, yzw: vertex light
#else
    half  fogFactor                 : TEXCOORD6;
#endif
    float4 shadowCoord              : TEXCOORD7;    // 阴影UV

DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 8);
#ifdef DYNAMICLIGHTMAP_ON
    float2  dynamicLightmapUV       : TEXCOORD8;    // 动态光照UV  Dynamic lightmap UVs
#endif

    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};



// 表面数据准备——————————————————
inline void InitializeStandardLitSurfaceData(float2 uv, out SurfaceData outSurfaceData)
{
    half4 albedoAlpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap,uv);
    half4 MaskMap   = SAMPLE_TEXTURE2D(_MaskMap, sampler_MaskMap,uv);
    float3 normalMap =  UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv),_NormalScale);
    normalMap.z = sqrt(1- saturate(dot(normalMap.rg,normalMap.rg)));
    half3 emission  = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap,uv);
    //normalMap = float3(0,0,1);

    #if defined(_ISHAIR)
       half  smoothness = lerp(_SmoothnessDef,MaskMap.g,_Smoothness);
    #else
       half  smoothness = lerp(_SmoothnessDef,MaskMap.a,_Smoothness);
    #endif

    half  Metallic  = lerp(_MetallicDef,MaskMap.r,_Metallic);
    half  occlusion = lerp(1,MaskMap.b,_OcclusionScale);

    outSurfaceData.albedo = albedoAlpha.rgb * _BaseColor.rgb;
    outSurfaceData.alpha = AlphaTest(albedoAlpha.a, _BaseColor, _Cutoff, uv);
    outSurfaceData.metallic = Metallic;
    outSurfaceData.specular = _SpecularColor;
    outSurfaceData.smoothness = smoothness;
    outSurfaceData.normalTS = normalize( normalMap );
    outSurfaceData.shadowoffset =  (SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv).a-0.5)*_NormalScale;
    outSurfaceData.occlusion = occlusion;
    outSurfaceData.emission = albedoAlpha.rgb * emission *_EmissionScale;

    //未使用的数据就输出一个默认值，保持 SurfaceData 数据结构完整
    outSurfaceData.clearCoatMask       = half(0.0);
    outSurfaceData.clearCoatSmoothness = half(0.0);
}


// 初始化数据结构——————————————————
void InitializeInputData(Varyings input, half3 normalTS, out InputData inputData)
{
    inputData = (InputData)0;       //初始化inputData结构体

    inputData.positionWS = input.positionWS;        // 获取世界空间位置
    input.normalWS = normalize(input.normalWS);
    input.tangentWS = normalize(input.tangentWS);

    float sgn = input.tangentWS.w;       // should be either +1 or -1        获取副切线方向符号
    float3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);                    // 计算副切线  cross_叉积
    half3x3 tangentToWorld = half3x3(input.tangentWS.xyz, bitangent.xyz, input.normalWS.xyz);   // TBN矩阵
    
    inputData.tangentToWorld = tangentToWorld;
    inputData.normalWS = NormalizeNormalPerPixel(TransformTangentToWorld(normalTS, tangentToWorld));  // 法线转换到世界空间
    inputData.viewDirectionWS =  GetWorldSpaceNormalizeViewDir(input.positionWS);                    // 相机空间下位置



    // 阴影坐标计算
    #if defined(MAIN_LIGHT_CALCULATE_SHADOWS)                 
        inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS)+(1,1,1,1)*0.0;
        // 从世界坐标转换阴影坐标(通常是光源的视角空间，如平行光的正交投影空间)
    #else
        inputData.shadowCoord = float4(0, 0, 0, 0);             // 无阴影
    #endif

    // 雾效和顶点光照
    #ifdef _ADDITIONAL_LIGHTS_VERTEX
        inputData.fogCoord = InitializeInputDataFog(float4(input.positionWS, 1.0), input.fogFactorAndVertexLight.x);
        inputData.vertexLighting = input.fogFactorAndVertexLight.yzw;
        // 存储顶点光照数据
    #else
        inputData.fogCoord = InitializeInputDataFog(float4(input.positionWS, 1.0), input.fogFactor);
    #endif
    
    // 计算全局光照（烘焙光照）  
    #if defined(DYNAMICLIGHTMAP_ON)
        inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.dynamicLightmapUV, input.vertexSH, inputData.normalWS);
    #else
        inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.vertexSH, inputData.normalWS);
    #endif

    // 屏幕空间UV和阴影遮罩
    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
    inputData.shadowMask = SAMPLE_SHADOWMASK(input.staticLightmapUV);


    // 调试显示相关数据
    #if defined(DEBUG_DISPLAY)
        #if defined(DYNAMICLIGHTMAP_ON)
            inputData.dynamicLightmapUV = input.dynamicLightmapUV;
        #endif
        
        #if defined(LIGHTMAP_ON)
            inputData.staticLightmapUV = input.staticLightmapUV;
        #else
            inputData.vertexSH = input.vertexSH;
        #endif
    #endif
}




// 顶点着色器——————————————————
Varyings LitPassVertex(Attributes input)
{
    Varyings output = (Varyings)0;

    UNITY_SETUP_INSTANCE_ID(input);                   //设置当前绘制的 Instance ID
    UNITY_TRANSFER_INSTANCE_ID(input, output);        //将 Instance ID 从输入结构传递到输出结构
   
   // UV + 顶点色
    output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
    output.VertexColor = input.VertexColor;

    //输入模型空间位置，获取世界空间位置，观察空间位置、裁剪空间位置、NDC设备空间位置
    //      positionOS         positionWS  positionVS    positionCS       positionNDC
    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
    
    //输入模型空间法线，获取世界空间法线，世界空间切线，世界空间副切线
    //       normalOS           normalWS      tangentWS    bitangentWS
    VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

    output.normalWS = normalInput.normalWS;
    
    real sign = input.tangentOS.w * GetOddNegativeScale();
    half4 tangentWS = half4(normalInput.tangentWS.xyz, sign);
    
    output.tangentWS = tangentWS;
    output.positionWS = vertexInput.positionWS;
    output.positionCS = vertexInput.positionCS;
    output.positionNDC = vertexInput.positionNDC;

    // 顶点光照
    half3 vertexLight = VertexLighting(vertexInput.positionWS, normalInput.normalWS);
    
    // 雾效因子初始化
    half fogFactor = 0;
    #if !defined(_FOG_FRAGMENT)
        fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
    #endif

    // 计算静态光照贴图 UV
    OUTPUT_LIGHTMAP_UV(input.staticLightmapUV, unity_LightmapST, output.staticLightmapUV);
    #ifdef DYNAMICLIGHTMAP_ON       //如果启用动态光照贴图（Realtime GI）
        output.dynamicLightmapUV = input.dynamicLightmapUV.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
        // unity_DynamicLightmapST,Unity 提供的 动态光照贴图的缩放和偏移（Scale & Offset）
    #endif
    
    // 球谐光照,顶点光照
    OUTPUT_SH(output.normalWS.xyz, output.vertexSH);    //vertexSH 存储球谐光照数据的变量
    #ifdef _ADDITIONAL_LIGHTS_VERTEX
        output.fogFactorAndVertexLight = half4(fogFactor, vertexLight); // .xyz 存储 vertexLight  .w 存储 fogFactor
    #else
        output.fogFactor = fogFactor;   // 仅存储雾效因子，忽略顶点光照
    #endif
    

    //传递阴影坐标
    #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
        output.shadowCoord = GetShadowCoord(vertexInput);       
    #endif

    return output;
}



//片元着色器——————————————————
void LitPassFragment( Varyings input, out half4 outColor : SV_Target0)
{
    UNITY_SETUP_INSTANCE_ID(inpu);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
    
    float2 uv = input.uv;

    // 表面数据准备
    SurfaceData surfaceData;
    InitializeStandardLitSurfaceData(uv, surfaceData);

    #ifdef LOD_FADE_CROSSFADE
        LODFadeCrossFade(input.positionCS);
    #endif

    // 将表面数据转换到世界坐标系下的，  同时准备阴影贴图，全局光照，雾效因子等数据
    InputData inputData;
    InitializeInputData(input, surfaceData.normalTS, inputData);

    SETUP_DEBUG_TEXTURE_DATA(inputData, uv, _BaseMap);

    //————————————————————————————————————————————
    BRDFData brdfData;
    BRDFData brdfDataClearCoat = (BRDFData)0;                                                   //计算清漆
    half4 shadowMask = CalculateShadowMask(inputData);                                          //计算 Shadowmask阴影
    AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData, surfaceData);     //AO 
    uint meshRenderingLayers = GetMeshRenderingLayer();
    Light mainLight = GetMainLight(inputData, shadowMask, aoFactor);                          
    // 获取主光源数据:方向,阴影遮罩，距离阴影衰减（主光源默认为1，有距离衰减的光源才有渐变值）,光源颜色,
        // 暂时去掉主光自阴影 ——————
        mainLight.shadowAttenuation = 1;  
    

    //基础矢量数据 ——————
    half3 HVLDir = normalize(mainLight.direction + inputData.viewDirectionWS);      // 半角向量
    float3 normalVS = mul(GetWorldToViewMatrix(), inputData.normalWS );             // 视线空间法线
    float3 ViewDir = mul(GetWorldToViewMatrix(), float3(0, 0, -1));                 // 视线朝向

    half NdotL0 = dot(input.normalWS, mainLight.direction);                         // 原始法线兰伯特
    half NdotL = dot(inputData.normalWS,mainLight.direction);                       // 兰伯特
    half HNdotL = saturate( (NdotL*0.5+0.5));                                       // 半兰伯特
    half NdotH = dot(inputData.normalWS,HVLDir);                                    // BLing - Fong
    half VdotN =  dot( inputData.viewDirectionWS, inputData.normalWS);              // 菲尼尔

    // MatCap
    half2 MatCapUV = (normalVS*0.45+0.5).rg;
    float3 MatCap = SAMPLE_TEXTURE2D(_MatCap, sampler_MatCap,MatCapUV);
    MatCap = saturate(MatCap);

    // 基础色调整 ——————
    surfaceData.albedo = MatCapBlendColor( surfaceData.albedo, MatCap, surfaceData.metallic, HNdotL);    //MatCap
    half FinierVdotN = pow(1-saturate(VdotN),_FinierPow);
    surfaceData.albedo = lerp(surfaceData.albedo , _FinierColor.rgb, FinierVdotN * _FinierColor.a);   // 菲尼尔
    surfaceData.albedo = GammaRectify(surfaceData.albedo, NdotL0, NdotL);                              // 伽马  有问题
    

    // BRGF参数初始化
    InitializeBRDFData(surfaceData, brdfData);
    

    // 混合实时全局光照（Realtime GI）和烘焙全局光照（Baked GI）   不包含AO
    inputData.bakedGI = SubtractDirectMainLightFromLightmap(mainLight, inputData.normalWS, inputData.bakedGI);
    // 实现全局光照（GI）和 自发光部分        其他光照贡献（如主光源、附加光源）被初始化为 0
    LightingData lightingData = CreateLightingData(inputData, surfaceData);
    // 全局光照 计算的函数  处理了材质的反射、菲涅尔效应、环境光照、以及烘焙光照等因素
    lightingData.giColor = GlobalIllumination(brdfData, brdfDataClearCoat, surfaceData.clearCoatMask,
                                              inputData.bakedGI, aoFactor.indirectAmbientOcclusion, inputData.positionWS,
                                              inputData.normalWS, inputData.viewDirectionWS, inputData.normalizedScreenSpaceUV);

    
    
    // 主灯光影响下的模型颜色  —————————————————————                                       
    // 检查主光是否影响当前物体的渲染层（meshRenderingLayers）
    #ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(mainLight.layerMask, meshRenderingLayers))
    #endif
    // 计算主灯光影响下的模型颜色， 包括强度衰减，颜色衰减
    lightingData.mainLightColor = Lightwork(brdfData, brdfDataClearCoat, mainLight, inputData.normalWS,
                                            inputData.viewDirectionWS, surfaceData.clearCoatMask, 
                                            -1,surfaceData.shadowoffset, uv);


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
                    lightingData.additionalLightsColor += 
                                            Lightwork( brdfData, brdfDataClearCoat, light, nputData.normalWS,
                                            inputData.viewDirectionWS, surfaceData.clearCoatMask, 
                                            lightIndex,surfaceData.shadowoffset, uv );
                }
        }
    #endif
    


    // 额外逐像素光源计算——————————————————————————
    LIGHT_LOOP_BEGIN(pixelLightCount)
    Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
    //暂时去掉额外光自阴影———————
    light.shadowAttenuation = 1;

    // 检查 光源 是否影响当前物体的渲染层（meshRenderingLayers）
    #ifdef _LIGHT_LAYERS
            if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))  //获得的光源数量
    #endif
            {
               lightingData.additionalLightsColor += Lightwork(brdfData, brdfDataClearCoat, light, inputData.normalWS, 
                                                               inputData.viewDirectionWS, surfaceData.clearCoatMask, 
                                                               lightIndex, surfaceData.shadowoffset, uv);
            }
    LIGHT_LOOP_END
    #endif

    // 整合所有光照——————
    float3 ColorRGB = CalculateLightingColor(lightingData,1);  //添加除主光外的所有光影响
   

    // 眼睛
    #if defined(_ISEYE)
        float3 BitangentWS = cross( input.normalWS , input.tangentWS );
        float3x3 TBN = { input.tangentWS.xyz , BitangentWS , input.normalWS };
        float3 ViewDirTS = TransformWorldToTangent( SafeNormalize( _WorldSpaceCameraPos - input.positionWS ) ,TBN);
        float2 offset = POM(input.uv, ViewDirTS);
        
        float3 Eyeclor = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap,uv + offset)*_EmissionScale * _EmissionColor.rgb;  //眼睛基础
        half EyeMask  = SAMPLE_TEXTURE2D(_OtherMap, sampler_OtherMap,uv - offset*2).r;    // 额外眼睛高光
        half3 EyeMaskColor = EyeMask * _EyeSpeCol.rgb * _EyeSpeCol.a*3;  
        
        half liangdu = saturate(dot( mainLight.direction , _FaceForward)*0.5+0.5);

        ColorRGB = (Eyeclor + EyeMaskColor)* (liangdu*0.5+0.5); 
        surfaceData.alpha *=  saturate(dot(-ViewDir, inputData.normalWS)); 

    #endif

    // 面部颜色
    #if defined(_ISFACE)
        float4 FaceMask  = SAMPLE_TEXTURE2D(_OtherMap, sampler_OtherMap,uv);           
        float3 FaceColor = FaceSDF( surfaceData.albedo ,ViewDir, mainLight.direction , _FaceRight, _FaceForward, FaceMask.a , uv );
        FaceColor *= mainLight.color;
        ColorRGB += lerp(FaceColor , lightingData.mainLightColor ,FaceMask.g)  ;        // 脖子过度区域

        // 嘴唇动态高光
        float angle =  dot( mainLight.direction, _FaceForward )*0.5 + 0.5;
        float2 FlpUV = uv + ( _FaceForward + ViewDir).rg * float2(0.02,0.01);
        float  FlpMask = SAMPLE_TEXTURE2D(_OtherMap, sampler_OtherMap, FlpUV).r;  
        ColorRGB *= ( 1 + FlpMask * surfaceData.specular * _SpeculerScale * sqrt(angle));

    #elif !defined(_ISEYE)
        ColorRGB += lightingData.mainLightColor ;
    #endif
    
    // 头发高光——————
    #if defined(_ISHAIR) 
        half3 HairColor =  HariSpeculer(brdfData, inputData.normalWS, mainLight.direction, inputData.viewDirectionWS, uv);
        HairColor *=  MatCap * _SpeculerScale ; 
        ColorRGB += HairColor;
    #endif


    // 边缘高光
    float2 screenUV = input.positionNDC.xy/input.positionNDC.w ;           
    float rawdepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, screenUV ).r;        // 采样深度图
    float linedepth = LinearEyeDepth(rawdepth, _ZBufferParams);                         // 转为线性，_ZBufferParams 内置值
    
    float2 screenOffset = float2( lerp(-1,1,step(0,normalVS.x)) * _RimOffset/_ScreenParams.x/max(pow(linedepth,2), 1), 0);
    float offsetDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, screenUV + screenOffset).r;
    float offsetLinearDepth = LinearEyeDepth(offsetDepth,_ZBufferParams);

    float Rim = saturate( offsetLinearDepth-linedepth);
    Rim = min(step(0.03,Rim),0.5) * FinierVdotN * _RimScale * HNdotL * HNdotL;                // 钳制最大值  阈值  菲尼尔  强度

    ColorRGB = 1- (1-Rim)* (1-ColorRGB);
   
    // 深度阴影
    half2 DepthShadowDir = mainLight.direction.xy + ViewDir.xy;
    float2 DepthShadowUV = screenUV*0.97+0.015 + (DepthShadowDir * 0.02)/length(_WorldSpaceCameraPos-input.positionWS );
    float DepthShadow = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, DepthShadowUV).r;
    float DepthLinearShadow = LinearEyeDepth(DepthShadow,_ZBufferParams);   
    float DShadow = saturate( linedepth - DepthLinearShadow );               // 插值
    DShadow = DShadow * saturate( lerp(1,0,DShadow*5));
    //DShadow = step(0.01,DShadow) * (0.01/saturate(DShadow));
    DShadow = saturate( 1 - DShadow * _DepthShadowScale);
    ColorRGB *= DShadow;

    // 颜色混合雾效   透明度设置——————
    ColorRGB =  MixFogColor(ColorRGB, unity_FogColor.rgb, inputData.fogCoord);
    half colorAlpha = surfaceData.alpha;



    // 定义deabug输出——————
    #if defined(DEBUG_DISPLAY)
        half4 debugColor;
        if (CanDebugOverrideOutputColor(inputData, surfaceData, brdfData, debugColor))
        {   ColorRGB = debugColor;     }
    #endif
    

    outColor = float4( ColorRGB , colorAlpha);
}


#endif
