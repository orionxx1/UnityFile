Shader "MyShader/RF/RF_SunShaft_Shader" 
{
    Properties
    {
        _StepSum ("步进次数", Range(0, 24)) = 1
        _StepLength ("步进长度", Range(0, 1)) = 0.5
        _SeedIntensity ("抖动采样强度", Range(0, 1)) = 0.01
        _LightIntensity ("强度", Range(0, 10)) = 0.5
        _LightColor ("颜色", Color) = (1,1,1,1)
        _BlurOffset ("模糊强度", Range(0, 10)) = 0.5
        _MinL("阈值", Range(0, 0.999)) = 0.5
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        LOD 100
        ZWrite Off 
        Cull Off

        Pass
        {
            Name "RF_SunShaft_Shader_Pass0"
            HLSLPROGRAM
            #pragma vertex Vert      
            #pragma fragment frag_m

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            
            TEXTURE2D(_CameraDepthTexture);     SAMPLER(sampler_CameraDepthTexture);
            TEXTURE2D(_CloudTexTex); 

            half _MinL;

            // 重映射  开端
            float remapOld(float v, float low, float high) 
            {
                return (v-low)/(high-low);
            }

            half4 frag_m(Varyings IN) : SV_Target
            {
                float2 uv = IN.texcoord;
                half4 MainTex =  SAMPLE_TEXTURE2D(_CloudTexTex, sampler_LinearClamp, uv);
                float3 ColorRGB = MainTex.rgb ;
                float ColorAlpha = MainTex.a ;

                // 灰度值
                half region = Luminance(ColorRGB);
                region = remapOld(region, _MinL, 1);
                region = saturate(region) * step(_MinL,region);

                // 深度
                float depth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, uv).r;
                ColorRGB = ColorRGB * region ;
                return float4( ColorRGB , ColorAlpha );
            }
            ENDHLSL
        }



        Pass
        {
            Name "RF_SunShaft_Shader_Pass1"
            HLSLPROGRAM
            #pragma vertex Vert      
            #pragma fragment frag_m

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Filtering.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            
            #define random(seed) sin(seed * 641.5467987313875 + 1.943856175)            // 随机值

            CBUFFER_START(UnityPerMaterial)
                int _StepSum;
                half _StepLength;
                half _SeedIntensity;
                half _LightIntensity;
                half4 _LightColor;
                half _Factor;
            CBUFFER_END
            TEXTURE2D(_CameraDepthTexture);     SAMPLER(sampler_CameraDepthTexture);
            TEXTURE2D(_VolumeLightTex);


            half4 frag_m(Varyings IN) : SV_Target
            {
                float2 uv = IN.texcoord;

                // 屏幕空间 主光位置
                Light mainLight = GetMainLight(); 
                float3 sunDirWS = -mainLight.direction;
                float3 sunDirVS = mul((float3x3)GetWorldToViewMatrix(), sunDirWS);
                float3 ViewPosWS = _WorldSpaceCameraPos.xyz;
                float3 sunPosWS = ViewPosWS - sunDirWS;
                float3 sunPosVS = mul(GetWorldToViewMatrix(), float4(sunPosWS, 1.0));
                sunPosVS = sunPosVS*0.5+0.5;

                // 角度影响强度
                half angle = 1-dot(sunPosVS,half3(0,0,1));
                angle = saturate(angle*2-1);

                _StepSum = ceil(min( _StepSum, 12));          // 限制步进次数
                float2 blurVector = ( sunPosVS.xy - uv ) * (_StepLength/_StepSum) ;      // 步进方向
                half3 color = 0;                        // 颜色累加
                float JJJ = _StepSum;
                float seed = random((_ScreenParams.y * uv.y + uv.x) * _ScreenParams.x + ViewPosWS.x + ViewPosWS.y);  //抖动采样

                for (int j = 0; j < _StepSum; j++)
		        {
                    seed = random(seed);
		        	half3 tmpColor = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;
                    tmpColor = tmpColor * sqrt(JJJ/_StepSum);
                    tmpColor = saturate(tmpColor) * _LightIntensity;
		        	color = max( tmpColor  , color) ;
		        	uv += blurVector * (1 + seed * _SeedIntensity);
                    JJJ -= 1;
		        }

                color = saturate(color) * angle  * _LightColor.rgb;

                return float4( color , 1 );
            }

            ENDHLSL
        }


        // 体积光 Kawase模糊
        Pass
        {
            Name "RFVolumetricLightPass_Blur"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag_blur

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl" 
            
            CBUFFER_START(UnityPerMaterial)
                float4 _BlitTexture_TexelSize; // Blitter 会自动填充这个，包含 1/width, 1/height, width, height
                float _BlurOffset;
            CBUFFER_END
            
            float4 frag_blur(Varyings IN) : SV_Target
            {
                float2 uv = IN.texcoord;
                float2 offset = _BlurOffset * _BlitTexture_TexelSize.xy;

                half4 VolumeColor = 0;
                VolumeColor += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2( offset.x,  offset.y));
                VolumeColor += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-offset.x,  offset.y));
                VolumeColor += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2( offset.x, -offset.y));
                VolumeColor += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-offset.x, -offset.y));
                VolumeColor += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);
                VolumeColor *= 0.2;

                return VolumeColor; 
            }

            ENDHLSL
        }


        // 体积光 Kawase模糊
        Pass
        {
            Name "RFVolumetricLightPass_Blend"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag_blur

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl" 
            
            CBUFFER_START(UnityPerMaterial)
                float4 _BlitTexture_TexelSize; // Blitter 会自动填充这个，包含 1/width, 1/height, width, height
                float _BlurOffset;
            CBUFFER_END
            TEXTURE2D(_CloudTexTex); 
            TEXTURE2D(_VolumeLightTex);

            half4 frag_blur(Varyings IN) : SV_Target
            {
                float2 uv = IN.texcoord;
                half4 MainTex =  SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);
                half3 ColorRGB = MainTex.rgb ;
                half ColorAlpha = MainTex.a ;
                half region = Luminance(ColorRGB);

                half3 VolumeLightColor = SAMPLE_TEXTURE2D(_VolumeLightTex, sampler_LinearClamp, uv ).rgb;
                half4 VolumeColor = SAMPLE_TEXTURE2D(_CloudTexTex, sampler_LinearClamp, uv );

                ColorRGB = ColorRGB * VolumeColor.a +  VolumeColor.rgb + VolumeLightColor * (1-sqrt(region));
                MainTex =  half4( ColorRGB, ColorAlpha );

                return  MainTex ; 
            }

            ENDHLSL
        }



    }
}



