#ifndef UT_SPACE_TRANSFORMS_INCLUDED
#define UT_SPACE_TRANSFORMS_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"
#include "Assets/Test/GPUDrivenRenderer/Shader/Ut-IndirectInput.hlsl"

#define UT_MATRIX_M GetUTMatrixM(instanceID)

#ifdef _UT_INSTANCING_ON
float4x4 GetUTMatrixM(uint instanceID)
{
	float2 uv;
	float4 row1, row2, row3;
#if defined(SHADER_API_METAL) || defined(SHADER_API_VULKAN)	
	uint index = instanceID;
#else
	uv.x = (_DrawCallIndex % _InstanceIDOffsetMapRes) / _InstanceIDOffsetMapRes;
	uv.y = (_DrawCallIndex / _InstanceIDOffsetMapRes) / _InstanceIDOffsetMapRes;
	uint index = instanceID + DecodeIntRGBAFloat(SAMPLE_TEXTURE2D_LOD(_InstanceIDOffsetMap, sampler_InstanceIDOffsetMap, uv, 0).r);
#endif

	uv.x = (index * 3 % _VegDataMapRes) / _VegDataMapRes;
	uv.y = (index * 3 / _VegDataMapRes) / _VegDataMapRes;
	row1 = DecodeFloatRGBAFloat(SAMPLE_TEXTURE2D_LOD(_VegDataMap, sampler_VegDataMap, uv, 0));
		
	uv.x = ((index * 3 + 1) % _VegDataMapRes) / _VegDataMapRes;
	uv.y = ((index * 3 + 1) / _VegDataMapRes) / _VegDataMapRes;
	row2 = DecodeFloatRGBAFloat(SAMPLE_TEXTURE2D_LOD(_VegDataMap, sampler_VegDataMap, uv, 0));
		
	uv.x = ((index * 3 + 2) % _VegDataMapRes) / _VegDataMapRes;
	uv.y = ((index * 3 + 2) / _VegDataMapRes) / _VegDataMapRes;
	row3 = DecodeFloatRGBAFloat(SAMPLE_TEXTURE2D_LOD(_VegDataMap, sampler_VegDataMap, uv, 0));
		
	float4x4 objToWorldMatrix = float4x4(row1, row2, row3, float4(0,0,0,1));
	return objToWorldMatrix;
}
#endif

float4x4 GetObjectToWorldMatrix(uint instanceID)
{
#ifdef _UT_INSTANCING_ON
	return UT_MATRIX_M;
#else
	return UNITY_MATRIX_M;
#endif
}

float3 TransformObjectToWorld(float3 positionOS, uint instanceID)
{
#ifdef _UT_INSTANCING_ON
	return mul(GetObjectToWorldMatrix(instanceID), float4(positionOS, 1.0)).xyz;;
#else
	return mul(GetObjectToWorldMatrix(), float4(positionOS, 1.0)).xyz;;
#endif
}

float4 TransformObjectToHClip(float3 positionOS, uint instanceID)
{
#ifdef _UT_INSTANCING_ON
	return mul(GetWorldToHClipMatrix(), mul(GetObjectToWorldMatrix(instanceID), float4(positionOS, 1.0)));
#else
	return mul(GetWorldToHClipMatrix(), mul(GetObjectToWorldMatrix(), float4(positionOS, 1.0)));
#endif
}

float3 TransformObjectToWorldDir(float3 dirOS, uint instanceID, bool doNormalize = true)
{
#ifdef _UT_INSTANCING_ON
	float3 dirWS = mul((float3x3)GetObjectToWorldMatrix(instanceID), dirOS);
#else
	float3 dirWS = mul((float3x3)GetObjectToWorldMatrix(), dirOS);
#endif
	if (doNormalize)
		return SafeNormalize(dirWS);

	return dirWS;
}

float3 TransformObjectToWorldNormal(float3 normalOS, uint instanceID, bool doNormalize = true)
{
#ifdef _UT_INSTANCING_ON
	return TransformObjectToWorldDir(normalOS, instanceID, doNormalize);
#else
	return TransformObjectToWorldDir(normalOS, doNormalize);
#endif
}

VertexPositionInputs GetVertexPositionInputs(float3 positionOS, uint instanceID)
{
	VertexPositionInputs input;
	input.positionWS = TransformObjectToWorld(positionOS, instanceID);
	input.positionVS = TransformWorldToView(input.positionWS);
	input.positionCS = TransformWorldToHClip(input.positionWS);

	float4 ndc = input.positionCS * 0.5f;
	input.positionNDC.xy = float2(ndc.x, ndc.y * _ProjectionParams.x) + ndc.w;
	input.positionNDC.zw = input.positionCS.zw;

	return input;
}

VertexNormalInputs GetVertexNormalInputs(float3 normalOS, float4 tangentOS, uint instanceID)
{
	VertexNormalInputs tbn;

	// mikkts space compliant. only normalize when extracting normal at frag.
	real sign = real(tangentOS.w) * GetOddNegativeScale();
	tbn.normalWS = TransformObjectToWorldNormal(normalOS, instanceID);
	tbn.tangentWS = real3(TransformObjectToWorldDir(tangentOS.xyz, instanceID));
	tbn.bitangentWS = real3(cross(tbn.normalWS, float3(tbn.tangentWS))) * sign;
	return tbn;
}

#endif
