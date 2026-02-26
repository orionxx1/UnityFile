#ifndef SCENESEAGRASS_INCLUDED
#define SCENESEAGRASS_INCLUDED

#include "SeaLighting.hlsl"
#include "SeaGrassSpaceTransforms.hlsl"

#define MAXWINDSTRENGTH 10


struct AttributesSceneObject
{
	float4 positionOS   : POSITION;
	half3 normalOS      : NORMAL;
	half4 tangentOS     : TANGENT;
	float4 uv           : TEXCOORD0;
	float4 uvLM         : TEXCOORD1;
};


struct VaryingsSceneObject
{
	float4 positionCS               	: SV_POSITION;
	float4 uvAndUvLM                	: TEXCOORD0;
	float4 positionWSAndFogFactor   	: TEXCOORD1; 
	half3  normalWS                 	: TEXCOORD2;
	float3 uvRootAndHeight				: TEXCOORD4;
	half4 fogColor						: TEXCOORD5;
	half4 windNormalWSAndStrength	    : TEXCOORD6;
	DECLARE_LIGHTMAP_OR_SH(lightmapUV, vertexSH, 7);
#ifdef _MAIN_LIGHT_SHADOWS
	float4 shadowCoord					: TEXCOORD8; 
#endif
    half3 Wind	                        : TEXCOORD9;
};


	
inline void InitializeStandardLitSurfaceData(VaryingsSceneObject input, out SurfaceData outSurfaceData)
{
	half4 main_color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uvAndUvLM.xy)*0.8+0.2;
    
    outSurfaceData.alpha = SAMPLE_TEXTURE2D(_AlphaTex, sampler_AlphaTex, input.uvAndUvLM.xy).r;

    half3 albedo  = main_color.rgb * _Color;

    outSurfaceData.albedo = albedo.rgb;
    outSurfaceData.albedo = AlphaModulate(outSurfaceData.albedo, outSurfaceData.alpha);

    outSurfaceData.metallic =  0;
    outSurfaceData.specular =  0.5;

    outSurfaceData.smoothness = 1-_Smoothness;

    outSurfaceData.normalTS   = SAMPLE_TEXTURE2D(_NormalTex, sampler_NormalTex, input.uvAndUvLM.xy);

    outSurfaceData.occlusion = saturate(input.uvAndUvLM.y / _AOCorrect);
    outSurfaceData.emission  = 0;

    outSurfaceData.clearCoatMask       = half(0.0);
    outSurfaceData.clearCoatSmoothness = half(0.0);
}


void InitializeInputData(VaryingsSceneObject input, half3 normalTS, out InputData inputData)
{
    inputData = (InputData)0;
    
    inputData.positionWS = input.positionWSAndFogFactor.xyz;
    inputData.positionCS = input.positionCS;
    
    half3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWSAndFogFactor.xyz);

    inputData.tangentToWorld = 0;
    inputData.normalWS = input.normalWS;
    inputData.viewDirectionWS = viewDirWS;

#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
    inputData.shadowCoord = input.shadowCoord;
#elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
    inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);
#else
    inputData.shadowCoord = float4(0, 0, 0, 0);
#endif


    inputData.fogCoord = InitializeInputDataFog(float4(input.positionWSAndFogFactor.xyz, 1.0), input.positionWSAndFogFactor.z);
    inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.vertexSH, inputData.normalWS);
    
    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
    inputData.shadowMask = SAMPLE_SHADOWMASK(input.staticLightmapUV);

    #if defined(DEBUG_DISPLAY)
    #if defined(LIGHTMAP_ON)
    inputData.staticLightmapUV = input.staticLightmapUV;
    #else
    inputData.vertexSH = input.vertexSH;
    #endif
    #endif
}


float3 GetWindGrassWorldPos(float3 posWS,float y)
{
    float3 cameraTransformRightWS = UNITY_MATRIX_V[0].xyz;
    //UNITY_MATRIX_V[2].xyz == -1 * world space camera Forward unit vector
    float wind = 0;
    wind += (sin(_Time.y * _WindAFrequency + posWS.x * _WindATiling.x + posWS.z * _WindATiling.y) *
        _WindAWrap.x + _WindAWrap.y) * _WindAIntensity; //windA
    wind += (sin(_Time.y * _WindBFrequency + posWS.x * _WindBTiling.x + posWS.z * _WindBTiling.y) *
        _WindBWrap.x + _WindBWrap.y) * _WindBIntensity; //windB
    wind += (sin(_Time.y * _WindCFrequency + posWS.x * _WindCTiling.x + posWS.z * _WindCTiling.y) *
        _WindCWrap.x + _WindCWrap.y) * _WindCIntensity; //windC
    //wind *= posWS.y; //wind only affect top region, don't affect root region
    wind *= y;
    float3 windOffset = cameraTransformRightWS * wind; //s
    posWS.xyz += windOffset;

    return posWS;
}

VaryingsSceneObject SceneObjectVertex(AttributesSceneObject input, uint instanceID : SV_InstanceID)
{
	VaryingsSceneObject output = (VaryingsSceneObject)0;
	
	VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz, instanceID);
	
	float3 posWS = GetWindGrassWorldPos(vertexInput.positionWS,input.uv.y);
	half3 normalWS = TransformObjectToWorldNormal(input.normalOS, instanceID);
	
	output.uvAndUvLM.xy = TRANSFORM_TEX(input.uv, _MainTex);
	output.uvAndUvLM.zw = input.uvLM.xy * unity_LightmapST.xy + unity_LightmapST.zw;
	
	output.positionCS = TransformWorldToHClip(posWS);
	output.positionWSAndFogFactor = float4(posWS, 1);
	output.normalWS = normalWS;
    output.Wind = posWS-vertexInput.positionWS.xyz;

#ifdef _MAIN_LIGHT_SHADOWS
	output.shadowCoord = GetShadowCoord(vertexInput);
#endif
	return output;
}

void SceneObjectFragment(VaryingsSceneObject input, half facing : VFACE, out half4 outColor : SV_Target0)
{
	SurfaceData surfaceData;
	InitializeStandardLitSurfaceData(input, surfaceData);
	InputData inputData;
	InitializeInputData(input, surfaceData.normalTS, inputData);
    inputData.normalWS = lerp(inputData.normalWS*facing,half3(0,1,0),saturate(_NormalLetp+input.uvAndUvLM.y*0.2));

    #if defined(DEBUG_DISPLAY)
        SetupDebugDataTexture(inputData, input.uvAndUvLM.xy, _BaseMap_TexelSize, _BaseMap_MipInfo, GetMipCount(TEXTURE2D_ARGS(_BaseMap, smp)));
    #endif
    
    BRDFData brdfData;
    InitializeBRDFData(surfaceData, brdfData);

    half4 color = UniversalFragmentPBR(inputData, surfaceData);
    half3 ColorRGB = MixFog(color.rgb, inputData.fogCoord);
    half  ColorAlpha = OutputAlpha(color.a, IsSurfaceTypeTransparent(_Surface));
    clip( surfaceData.alpha - 0.02 );

    float2 NoiseUV = TRANSFORM_TEX(inputData.positionWS.xz, _NoiseTex);
    NoiseUV += _NoiseTex_ST.zw * _Time.x;
    half Mask = SAMPLE_TEXTURE2D(_NoiseTex, sampler_NoiseTex, NoiseUV).r;
    Mask = Mask * saturate((input.uvAndUvLM.y - _GlassRange)*(1 / (1 -_GlassRange)) ) ;
    half3 GlassColor = _GlassColor * saturate(Mask*Mask +input.Wind.b) * _GlassPower;

    ColorRGB += GlassColor;

	outColor = half4(ColorRGB,ColorAlpha);
}

#endif
