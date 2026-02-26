Shader "MyShader/RF/SeSan" 
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Scale ("Scale", Range(0, 0.01)) = 0.01
        // 可以添加更多你希望从C#代码中读取或设置的属性
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
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float _Scale;
            CBUFFER_END

            TEXTURE2D(_MainTex);  SAMPLER(sampler_MainTex);

            half4 frag_m(Varyings IN) : SV_Target
            {
                half2 UV    = (IN.texcoord-0.5)*half2(1,0.6);
                float Mask  = smoothstep(0,1,length(UV));
                float3 Col  = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, IN.texcoord);

                half2 UVRed  = lerp(IN.texcoord,IN.texcoord - half2(_Scale,0),Mask);
                half2 UVBlue = lerp(IN.texcoord,IN.texcoord + half2(_Scale,0),Mask);
                float Red   = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, UVRed ).r;
                float Green = Col.g;
                float Blue  = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, UVBlue).b;
                
                float3 Color = float3(Red,Green,Blue);

                return float4(Color,1);
            }

            ENDHLSL
        }
    }
}