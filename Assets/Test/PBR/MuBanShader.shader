Shader "MyShader/MuBanShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Color ("Color", Color) = (1,1,1,1)
        _Factor("Factor", Range(0.0, 2.0)) = 1     
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            //————————
            CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST;
            float4 _Color;
            float  _Factor;
            CBUFFER_END

            TEXTURE2D(_MainTex);            SAMPLER(sampler_MainTex);

            //————————
            struct Vertexdata
            {
                float4 positionOS       : POSITION;
                float3 normalOS         : NORMAL;
                float4 tangentOS        : TANGENT;
                float4 VertexColor      : COLOR;
                float2 uv               : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };


            //————————
            struct FragmentData
            {
                float4 positionHCS      : SV_POSITION;
                float2 uv               : TEXCOORD0;
                float3 positionWS       : TEXCOORD1;        // 世界空间位置
                float3 normalWS         : TEXCOORD2;        // 世界空间法线    
                half4 tangentWS         : TEXCOORD3;        // 世界空间切线  
                float3 VertexColor      : TEXCOORD4;        // 顶点颜色

                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            
            //————————
            FragmentData vert(Vertexdata v)
            {
                FragmentData output;
                output.uv = TRANSFORM_TEX(v.uv, _MainTex);
                output.VertexColor = v.VertexColor;

                // positionOS >  positionWS  positionVS positionCS positionNDC
                VertexPositionInputs VertexPosition = GetVertexPositionInputs(v.positionOS.xyz);
                //  normalOS  tangentOS  >  normalWS   tangentWS   bitangentWS
                VertexNormalInputs VertexNormal = GetVertexNormalInputs( v.normalOS, v.tangentOS);

                output.positionWS =  VertexPosition.positionWS;
                output.positionHCS = VertexPosition.positionCS;

                real sign = v.tangentOS.w * GetOddNegativeScale();
                half4 tangentWS = half4(VertexNormal.tangentWS.xyz, sign);
                output.normalWS = VertexNormal.normalWS;
                output.tangentWS = tangentWS;

                return output;
            }

            
            //————————
            void frag(FragmentData f , out float4 outColor : SV_Target) 
            {
                float4 TextureColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, f.uv);
                float3 Color = TextureColor.rgb * _Color.rgb * _Factor;
                float  Alpha = TextureColor.a * _Color.a;

                outColor = float4(Color,Alpha);
            }
            ENDHLSL
        }

    }
}