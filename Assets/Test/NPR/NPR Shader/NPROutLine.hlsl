#ifndef UNIVERSAL_FORWARD_NPROUTLINE
#define UNIVERSAL_FORWARD_NPROUTLINE

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

struct Attributes
{
    float4 positionOS   : POSITION;
    float3 normalOS     : NORMAL;
    float4 tangentOS    : TANGENT;
    float4 VertexColor  : COLOR;
    float2 uv           : TEXCOORD0;
};


struct Varyings
{
    float4 positionCS   : SV_POSITION;
    float2 uv           : TEXCOORD0;
    float4 VertexColor  : TEXCOORD1;
    float3 normalWS     : TEXCOORD2;
    float3 positionWS   : TEXCOORD3;
};

CBUFFER_START(UnityPerMaterial)
float4 _BaseMap_ST;

float4 _OutLineColor;
half _OutlineColorBLend;
half _OutlineWidth;
half _ZOffset;

half _AlphaFactor;

CBUFFER_END

TEXTURE2D(_BaseMap);            SAMPLER(sampler_BaseMap);
TEXTURE2D(_OtherMap);           SAMPLER(sampler_OtherMap);


Varyings vert(Attributes IN)
{
    Varyings OUT;
    UNITY_SETUP_INSTANCE_ID(IN);
    UNITY_TRANSFER_INSTANCE_ID(IN, OUT);

    OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
    OUT.VertexColor = IN.VertexColor;

    //用原始法线构建TBN矩阵
    VertexNormalInputs normalInput = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);
    real sign = IN.tangentOS.w * GetOddNegativeScale();
    half4 tangentWS = half4(normalInput.tangentWS.xyz, sign);
    half3 normalWS = normalInput.normalWS;
    half3 bitangentWS = normalInput.bitangentWS;
    half3x3 TBN = half3x3(tangentWS.xyz, bitangentWS.xyz, normalWS.xyz);

    //从顶点色获取切线空间下的平滑法线，转为世界空间法线
    float3 normalTS = OUT.VertexColor.rgb;
    float3 NewNormalWS = mul(normalTS*2-1, TBN) ;
    
    OUT.normalWS = NewNormalWS;

    float3 postionWS = TransformObjectToWorld(IN.positionOS.xyz) ;
    float3 ViewDirPos = normalize(postionWS-_WorldSpaceCameraPos);      //相机方向  针对每个顶点
    float3 ViewDir = mul(UNITY_MATRIX_V, float3(0, 0, -1));             //相机方向  统一
    float  ViewZDepth = length(postionWS-_WorldSpaceCameraPos);
    
    float DepthWidth = max( min( ViewZDepth * 0.5 , 1 ) , 0.4 );

    _OutlineWidth *= step(0.01,length(OUT.VertexColor));  //排除顶点色黑色部分
    postionWS += OUT.normalWS * OUT.VertexColor.a * _OutlineWidth * DepthWidth * 0.01 ;                 //法线外扩
    postionWS += ViewDirPos * _ZOffset * 0.01;                             // 视线空间Z轴偏移  

    float4 positionCS = TransformWorldToHClip(postionWS);
    OUT.positionWS = postionWS;
    OUT.positionCS = positionCS;
    
    return OUT;
}

void frag(Varyings input, out half4 outColor : SV_Target) 
{
    float4 Tex = SAMPLE_TEXTURE2D( _BaseMap , sampler_BaseMap ,input.uv);
    float3 Color = lerp( Tex.rgb , _OutLineColor.rgb, _OutlineColorBLend );
    
    float  Alpha = _OutLineColor.a;
    Alpha = lerp (1,Alpha,_AlphaFactor);

    outColor = float4(Color,Alpha);
}

#endif
