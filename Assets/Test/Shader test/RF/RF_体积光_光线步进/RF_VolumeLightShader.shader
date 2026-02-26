Shader "MyShader/RF/RF_VolumeLightShader" 
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Intensity ("Intensity", Range(0, 1)) = 0.5             // 体积光强度
        _StepTime ("StepTime", Range(0, 24))  = 8               // 步进次数
        _StepSize ("StepSize", Range(0, 1))  = 0.02             // 随机采样偏移
        _BlurOffset("BlurOffset", Range(0, 10))  = 0.01         // 模糊偏移值
        _VolumeColor ("Volume Color", Color) = (1,1,1,1)

    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        LOD 100
        ZWrite Off 
        Cull Off

        // Pass 0: 计算纯体积光
        Pass
        {
            Name "RFVolumetricLightPass_Calculation" 
            HLSLPROGRAM
            #pragma vertex Vert      
            #pragma fragment frag_m
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS                 // 定义阴影采样
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE         // 主光源是否启用了级联阴影

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"  //阴影计算库
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            
            #define random(seed) sin(seed * 641.5467987313875 + 1.943856175)            // 随机值
            #define MAX_SHADER_BOXES 16    // 包围盒最大数量

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST; 
                half _Intensity;
                half _StepTime;
                half _StepSize;
                half4 _VolumeColor;

                // 包围盒数据 ---
                half4 _VolumeBoxMinArray[MAX_SHADER_BOXES];     // 存储min点 (xyz)
                half4 _VolumeBoxMaxArray[MAX_SHADER_BOXES];     // 存储max点 (xyz)
                int _VolumeBoxCount;                            // 激活的包围盒数量
            CBUFFER_END

            TEXTURE2D(_MainTex);                SAMPLER(sampler_MainTex);

            half4 frag_m(Varyings IN) : SV_Target
            {
                float2 uv =  IN.texcoord;
                half4 MainTex =  SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);
                float3 ColorRGB = MainTex.rgb ;
                float ColorAlpha = MainTex.a ;

                // 1. 深度信息构建世界位置
                float depth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, uv).r;
                float3 WorldPosition = ComputeWorldSpacePosition(uv, depth, UNITY_MATRIX_I_VP);
                // 2. 获取该世界坐标对应的主光源阴影坐标
                float4 ShadowCoord = TransformWorldToShadowCoord(WorldPosition);
                // 3. 采样阴影图以获取阴影衰减值
                half shadowAttenuation = MainLightShadow(ShadowCoord,WorldPosition, 1, 1);

                float3 ViewPos = _WorldSpaceCameraPos;                      //摄像机上的世界坐标
                float3 ViewDir = normalize(WorldPosition - ViewPos);        //视线方向
                float RayLength = length(WorldPosition - ViewPos);          //视线长度
                RayLength = min(RayLength, 20);                             //限制最大步进长度
                float3 FinalPos = ViewPos + ViewDir * RayLength;            //定义步进结束点
                
                half _RandomNumber = 8;  
                float seed = random((_ScreenParams.y * uv.y + uv.x) * _ScreenParams.x + _RandomNumber + ViewPos.x + ViewPos.y);  //抖动采样
                half  intensity_sum  = 0;                 // 累计光强

                for(float i = 0; i < _StepTime; i += 1)  // 光线步进
                {
                    seed = random(seed);
                    float3 CurrentPos = lerp(ViewPos, FinalPos, i/_StepTime + seed * _StepSize);     //当前世界坐标

                    // 包围盒检测 ---
                    bool isInAnyBox = false;
                    if (_VolumeBoxCount > 0) // 只有当有包围盒时才检测
                    {
                        for (int boxIdx = 0; boxIdx < _VolumeBoxCount; ++boxIdx)
                        {
                            // AABB check
                            if (all(CurrentPos >= _VolumeBoxMinArray[boxIdx].xyz) && 
                                all(CurrentPos <= _VolumeBoxMaxArray[boxIdx].xyz))
                            {
                                isInAnyBox = true;
                                break;              // 只要在一个包围盒内就够了
                            }
                        }
                    }
                    // 如果没有定义包围盒，则认为全局有效（或者你可以设计成默认无效）
                    else
                    {
                        isInAnyBox = false;      
                    }
                
                    if (isInAnyBox)
                    {
                        ShadowCoord = TransformWorldToShadowCoord(CurrentPos);
                        // MainLightShadow(ShadowCoord, CurrentPos, true, false);
                        shadowAttenuation = MainLightRealtimeShadow(ShadowCoord);
                        intensity_sum += shadowAttenuation;
                    }
                }
                intensity_sum  = intensity_sum / _StepTime * _Intensity;
                ColorRGB = intensity_sum  * _VolumeColor.rgb;

                return float4( ColorRGB , ColorAlpha );
            }
            ENDHLSL
        }


        // Pass 1: 体积光 Kawase模糊
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
            
            TEXTURE2D(_VolumeLightTex);

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

                return VolumeColor*0.2; 
            }
            ENDHLSL
        }


        // Pass 2: 混合原始场景和体积光
        Pass
        {
            Name "RFVolumetricLightPass_Blend"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag_blend

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl" 

            TEXTURE2D(_VolumeLightTex);

            float4 frag_blend(Varyings IN) : SV_Target
            {
                float4 sceneColor = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, IN.texcoord);

                float2 uv = IN.texcoord;
                half4 VolumeColor =SAMPLE_TEXTURE2D(_VolumeLightTex, sampler_LinearClamp, uv );
                float3 finalColor = sceneColor.rgb + VolumeColor.rgb;

                return float4(finalColor, sceneColor.a); 
            }
            ENDHLSL
        }
    }
}