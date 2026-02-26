#ifndef UNIVERSAL_FORWARD_LIT_PASS_INCLUDED
#define UNIVERSAL_FORWARD_LIT_PASS_INCLUDED

#include "Lighting.hlsl"
#include "Assets/ORIONXXRenderer/Shaders/HLSLInclude/NoiseLib.hlsl"
#include "Rain.hlsl"

// 顶点数据
struct Attributes
{
    float4 positionOS   : POSITION;
    float3 normalOS     : NORMAL;
    float4 tangentOS    : TANGENT;
    float2 texcoord     : TEXCOORD0;
    float2 staticLightmapUV   : TEXCOORD1;
    float2 dynamicLightmapUV  : TEXCOORD2;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

// 片元数据
struct Varyings
{
    float2 uv                       : TEXCOORD0;    // UV
    float3 positionWS               : TEXCOORD1;    // 世界空间位置
    float3 normalWS                 : TEXCOORD2;    // 世界空间法线
    half4 tangentWS                 : TEXCOORD3;    // 世界空间切线   xyz: tangent, w: sign
    float4 positionCS               : SV_POSITION;  // 裁切空间位置 

    #ifdef _ADDITIONAL_LIGHTS_VERTEX                    // 顶点光照
        half4 fogFactorAndVertexLight   : TEXCOORD5;    // x: fogFactor, yzw: vertex light
    #else
        half  fogFactor                 : TEXCOORD5;
    #endif
    
        float4 shadowCoord              : TEXCOORD6;    // 阴影UV
        half3 viewDirTS                 : TEXCOORD7;    // 视线切线
    
    DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 8);
    #ifdef DYNAMICLIGHTMAP_ON
        float2  dynamicLightmapUV : TEXCOORD9;          // 动态光照UV  Dynamic lightmap UVs
    #endif

    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};


// 表面数据准备——————————————————
inline void InitializeStandardLitSurfaceData(float2 uv, out SurfaceData outSurfaceData)
{
    half4 albedoAlpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap,uv);
    half4 MaskMap   = SAMPLE_TEXTURE2D(_MaskMap, sampler_MaskMap,uv);
    float3 normalMap = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, uv), _NormalScale);
    half3 emission  = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap,uv).rgb;
    half  Metallic  = lerp(_MetallicDef,MaskMap.r,_Metallic);
    half  roughness = lerp(_RoughnessDef,MaskMap.g,_Roughness);
    half  occlusion = lerp(1,MaskMap.a,_OcclusionScale);
   
    outSurfaceData.albedo = albedoAlpha.rgb * _BaseColor.rgb;
    outSurfaceData.alpha = Alpha(albedoAlpha.a, _BaseColor, _Cutoff);
    outSurfaceData.metallic = Metallic;
    outSurfaceData.specular = _SpecularColor.rgb;
    outSurfaceData.smoothness = 1 - roughness;
    outSurfaceData.normalTS = normalMap;
    outSurfaceData.occlusion = occlusion;
    outSurfaceData.emission = emission;
    outSurfaceData.height = MaskMap.b * _HeightScale;

}


// 初始化数据结构——————————————————
void InitializeInputData(Varyings input, half3 normalTS, out InputData inputData)
{
    inputData = (InputData)0;       //初始化inputData结构体

    inputData.positionWS = input.positionWS;        // 获取世界空间位置

    float sgn = input.tangentWS.w;       // should be either +1 or -1        获取副切线方向符号
    float3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);                    // 计算副切线  cross_叉积
    half3x3 tangentToWorld = half3x3(input.tangentWS.xyz, bitangent.xyz, input.normalWS.xyz);   // TBN矩阵
    
    inputData.tangentToWorld = tangentToWorld;
    inputData.normalWS = NormalizeNormalPerPixel(TransformTangentToWorld(normalTS, tangentToWorld));  // 法线转换到世界空间
    inputData.viewDirectionWS =  GetWorldSpaceNormalizeViewDir(input.positionWS);     // 相机朝向顶点位置的方向，世界空间下，并且进行了归一化

    // 阴影贴图的UV
    #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)      // 需要顶点阴影坐标插值器
        inputData.shadowCoord = input.shadowCoord;              // 使用插值的阴影坐标
    #elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)                 // 主光计算阴影
        inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);
        // 从世界坐标转换阴影坐标(通常是光源的视角空间，如平行光的正交投影空间)
    #else
        inputData.shadowCoord = float4(0, 0, 0, 0);             // 无阴影
    #endif


    // 根据unity设置的雾的配置，生成实际上的雾的强度。如果有顶点计算的多光源颜色，那么也将生成顶点光的值
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

    // debug使用
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
Varyings Vertex(Attributes input)
{
    Varyings output = (Varyings)0;

    UNITY_SETUP_INSTANCE_ID(input);                   //设置当前绘制的 Instance ID
    UNITY_TRANSFER_INSTANCE_ID(input, output);        //将 Instance ID 从输入结构传递到输出结构
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);    //初始化 VR 立体渲染所需的变量   
   
   // UV
    output.uv = input.texcoord;
    
    //输入模型空间位置，获取世界空间位置，观察空间位置、裁剪空间位置、NDC设备空间位置
    //      positionOS         positionWS  positionVS    positionCS       positionNDC
    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
    
    //输入模型空间法线，获取世界空间法线，世界空间切线，世界空间副切线
    //       normalOS           normalWS      tangentWS    bitangentWS
    VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

    output.normalWS = normalInput.normalWS; // 输出法线
    
    real sign = input.tangentOS.w * GetOddNegativeScale();
    half4 tangentWS = half4(normalInput.tangentWS.xyz, sign);
    
    output.tangentWS = tangentWS;
    output.positionWS = vertexInput.positionWS;
    output.positionCS = vertexInput.positionCS;

    // 如果使用视差偏移，将计算出世界空间下的视线方向，并根据此计算出在切线空间的视角朝向
    #if defined(REQUIRES_TANGENT_SPACE_VIEW_DIR_INTERPOLATOR)
        half3 viewDirWS = GetWorldSpaceNormalizeViewDir(vertexInput.positionWS);                 
        half3 viewDirTS = GetViewDirectionTangentSpace(tangentWS, output.normalWS, viewDirWS);  
        output.viewDirTS = viewDirTS;       
        // viewDirWS 世界空间的视角方向   viewDirTS 切线空间视角方向
    #endif

    // 计算除主光源后和额外光的顶点光照，如果设置的是使用顶点去计算附加光源
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
        // 将动态光照烘焙的UV传输给片元
    #endif
      
    // 球谐光照,顶点光照
    OUTPUT_SH(output.normalWS.xyz, output.vertexSH);    //vertexSH 存储球谐光照数据的变量
    #ifdef _ADDITIONAL_LIGHTS_VERTEX                    //如果有顶点光照颜色，那么将顶点光照和雾的强度一块传出
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
void Fragment( Varyings input, out half4 outColor : SV_Target0)
{
    // 开头设置instance和vr兼容函数，必须放在最前面
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    float2 uv = TRANSFORM_TEX(input.uv, _BaseMap);

    // 水————————————————————————————
    // 噪波
    half2 uvNoise = TRANSFORM_TEX(input.uv, _NoiseMap);
    half3 NoiseColor = SAMPLE_TEXTURE2D(_NoiseMap, sampler_NoiseMap,uvNoise);
    NoiseColor = NoiseColor*2-1;

    // 水滴
    half3 SplatsEngine = SplatsEngineF( input.uv, NoiseColor.rg, _Time.x*_SplatsSpeed, _SplatsSize, _SplatsNoise, _SplatsScale );
    half2 SplatsMask = SplatsMaskF( SplatsEngine , _SplatsIntensity ,0.5);
    // 水波纹
    half4 RippleEngine = SplatsEngineF( input.uv, NoiseColor.rg, _Time.x*_RippleSpeed, _RippleSize, _RippleNoise, _RippleScale);
    half  RippleMask = RippleMaskF(RippleEngine, _RippleIntensity ,_RippleSize, _RingFrequency) ;

    half4 RippleEngine2 = SplatsEngineF( input.uv+0.33, NoiseColor.rg,_Time.x*_RippleSpeed, _RippleSize, _RippleNoise, _RippleScale);
    RippleMask += RippleMaskF(RippleEngine2, _RippleIntensity, _RippleSize, _RingFrequency) ;

    // 紊流
    half3 WaveNoise1 = SAMPLE_TEXTURE2D(_NoiseNormal, sampler_NoiseNormal, input.uv*_WaveScale*2    +_Time.x*_WaveSpeed*1.5);
    half3 WaveNoise2 = SAMPLE_TEXTURE2D(_NoiseNormal, sampler_NoiseNormal, input.uv*_WaveScale      -_Time.x*_WaveSpeed);
    half3 WaveNoise3 = SAMPLE_TEXTURE2D(_NoiseNormal, sampler_NoiseNormal, input.uv*_WaveScale*0.5  +_Time.x*_WaveSpeed*0.5);
    half wateNoise = (WaveNoise1.y+WaveNoise2.x +WaveNoise3.z)*0.001;
    half3 NoiseNormal = (WaveNoise1*0.4 + WaveNoise2*0.6 + WaveNoise3)-1;
    NoiseNormal = lerp( half3(0,0,1),NoiseNormal,_WaveNoise);

    // uv视差
    float3 ViewDir = GetWorldSpaceViewDir(input.positionWS);  // 引入
    half HeightMask = saturate(_WaterHeight - SAMPLE_TEXTURE2D(_MaskMap, sampler_MaskMap,uv).b )/_WaterHeight;  // 水部分遮罩
    uv = RainParallax(uv, HeightMask, _WaterDepth, wateNoise, RippleMask*_RippleHeight*0.5, ViewDir);

    // ——————————————————————————————
    
    SurfaceData surfaceData;
    InitializeStandardLitSurfaceData(uv, surfaceData);

    // 基础色 粗糙度  法线
    surfaceData.albedo = lerp(surfaceData.albedo, _WaterColor.rgb, HeightMask*_WaterColor.a*10);
    HeightMask =smoothstep(0,1-_WaterEdge,HeightMask);

    surfaceData.smoothness += SplatsMask.r + HeightMask + _Wetness;
    surfaceData.smoothness = saturate(surfaceData.smoothness);
    surfaceData.normalTS = lerp(surfaceData.normalTS, NoiseNormal ,HeightMask);
    surfaceData.normalTS =normalize(surfaceData.normalTS);

    InputData inputData;    
    InitializeInputData(input, surfaceData.normalTS, inputData);

    // 法线调整
    float HeightData = SplatsMask.g * _SplatsHeight * 0.01 * saturate(1-HeightMask);
    HeightData += RippleMask * _RippleHeight*0.01 * HeightMask;
    
    inputData.normalWS = height2BumpWS(inputData.positionWS, inputData.normalWS, HeightData, 1, 1, 1, 1 );

    SETUP_DEBUG_TEXTURE_DATA(inputData, uv, _BaseMap);

    #ifdef _DBUFFER
        ApplyDecalToSurfaceData(input.positionCS, surfaceData, inputData);
    #endif

    //————————————————————————————————————————————
    half4 color = UniversalFragmentPBR(inputData, surfaceData);             // 实现pbr
    color.rgb = MixFog(color.rgb, inputData.fogCoord);                      // 颜色根据雾的强度进行一个混合，模拟雾的效果
    color.a = OutputAlpha(color.a, IsSurfaceTypeTransparent(_Surface));     // 计算颜色的透明度

    outColor = color;
}

#endif
