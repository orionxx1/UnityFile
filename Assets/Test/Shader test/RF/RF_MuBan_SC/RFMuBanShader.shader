Shader "MyShader/RF/RFMuBanShader" 
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _ExampleFloat ("Example Float", Range(0, 1)) = 0.5
        _ExampleColor ("Example Color", Color) = (1,1,1,1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        LOD 100
        ZWrite Off 
        Cull Off

        Pass
        {
            Name "RFMuBanPass"
            HLSLPROGRAM
            #pragma vertex Vert      
            #pragma fragment frag_m

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float _ExampleFloat;
                half4 _ExampleColor;
            CBUFFER_END

            TEXTURE2D(_MainTex);                SAMPLER(sampler_MainTex);
            TEXTURE2D(_CameraDepthTexture);     SAMPLER(sampler_CameraDepthTexture);


            half4 frag_m(Varyings IN) : SV_Target
            {
                float2 uv = IN.texcoord;
                half4 MainTex =  SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);
                float3 ColorRGB = MainTex.rgb * _ExampleColor.rgb * _ExampleFloat;
                float ColorAlpha = MainTex.a * _ExampleColor.a;

                float depth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, uv).r;
                float linedepth = LinearEyeDepth(depth, _ZBufferParams);           

                // 深度信息构建世界位置
                // 把NDC坐标计算得到x,y值，把深度depth作为z值，然后乘以一个vp逆矩阵
                // 最后进行透视除法hpositionWS.xyz / hpositionWS.w就得到了世界坐标
                //float4 positionCS  = ComputeClipSpacePosition(uv, depth);
                //float4 hpositionWS = mul(UNITY_MATRIX_I_VP, positionCS);
                //float3 WorldPosition = hpositionWS.xyz / hpositionWS.w;
                float3 WorldPosition = ComputeWorldSpacePosition(uv, depth, UNITY_MATRIX_I_VP);
                

                return float4( ColorRGB , ColorAlpha );
            }

            ENDHLSL
        }
    }
}