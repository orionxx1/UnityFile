#ifndef SCENESEAGRASS_INPUT
#define SCENESEAGRASS_INPUT

	#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
	#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
	
	CBUFFER_START(UnityPerMaterial)
		float4 _MainTex_ST;
		float4 _NoiseTex_ST;

		float4 _MainTex_TexelSize;
		float _MainTex_MipInfo;
		#define smp _Linear_Repeat
		SAMPLER(smp);
		float _Surface;

		half4 _GlobalColTex_ST;

		half4 _Color;
		half _Cutoff;
		half _AOCorrect;
		half _Smoothness;
		half _GlassRange;
		half _GlassPower;
		half4 _GlassColor;

		//Grass Area
		half _NormalLetp;
		float _WindAIntensity;
		float _WindAFrequency;
		float2 _WindATiling;
		float2 _WindAWrap;
		half _HeightOffset_BaseColor2;
		float _WindBIntensity;
		float _WindBFrequency;
		float2 _WindBTiling;
		float2 _WindBWrap;
		float _WindCIntensity;
		float _WindCFrequency;
		float2 _WindCTiling;
		float2 _WindCWrap;
	CBUFFER_END

	TEXTURE2D(_MainTex);				SAMPLER(sampler_MainTex);
	TEXTURE2D(_AlphaTex);				SAMPLER(sampler_AlphaTex);
	TEXTURE2D(_NormalTex);				SAMPLER(sampler_NormalTex);
	TEXTURE2D(_NoiseTex);				SAMPLER(sampler_NoiseTex);

#endif