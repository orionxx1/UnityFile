Shader "MyShader/RF/RF_CloudText_Shader" 
{
    Properties
    {
        // 步进设置 ————
        [Main(_Step, _, on, off)] _Step ("步进设置", float) = 0
        [Sub(_Step)] _StepCount("最大步进次数", Range(0, 64)) = 12
        [Sub(_Step)] _SeedNoiseMap("步进噪声图", 2D) = "white" {}
        [Sub(_Step)] _SeedScale("步进随机值强度", Range(0, 1)) = 0          

        // 光线散射参数 ————
        [Main(Light, _, on, off)] Light ("光线散射参数", float) = 0
        [Sub(Light)] _CloudColor ("_CloudColor", Color) = (1,1,1,1)
        [Sub(Light)] _CloudSigma("CloudSigma", Vector) = (1,1,1,1)
        [Sub(Light)] _Absorption("介质吸收系数", Range(0.0001, 1)) = 0.03    
        [Sub(Light)] _LightAbsorption("散射吸收系数", Range(0.0001, 1)) = 0.1           
        [Sub(Light)] _LightPower("光照强度", Range(0, 2)) = 0.5 
        [Sub(Light)] _LightAbsorptionTowardSun("向着太阳的光吸收", Range(0.0001,2)) = 0.3
        [Sub(Light)] _DarknessThreshold("黑暗阈值", Range(0.0001,5)) = 0.1

        // 散射参数 ————
        [Main(Hg, _, on, off)] Hg ("Hg散射参数", float) = 0
        [Sub(Hg)] _HgPhaseG0("Hg散射参数0", Range(-0.99,0.99)) = 0.8
        [Sub(Hg)] _HgPhaseG1("Hg散射参数1", Range(-0.99,0.99)) = 0.2
        [Sub(Hg)] _phaseBase("Hg散射基础值", Range(0.0001,1)) = 0.15
        [Sub(Hg)] _phaseMultiply("Hg散射影响系数", Range(0,1)) = 0.1

        // 密度影响参数 ————
        [Main(D, _, on, off)] D ("密度影响参数", float) = 0
        [Sub(D)] _DensityMult("总密度", Range(0, 2)) = 1  

        [Sub(D)] _ShapeNoise_Tex ("基础噪声", 3D) = "white" {}
        [Sub(D)] _ShapeNoise_Scale ("基础噪声_尺寸", Vector) = (1, 1, 1, 1)
        [Sub(D)] _ShapeNoise_Offset ("基础噪声_偏移", Vector) = (0, 0, 0, 0)
        [Sub(D)] _ShapeNoise_Time("运动速度", Range(-1, 1)) = 0   
        [Sub(D)] _ShapeNoise_Density("基础密度贡献", Range(0.001, 50)) = 1     
        [Sub(D)] _ShapeNoiseDensityOffset("密度偏移", Range(-1, 1)) = 0   
        

        [Sub(D)] _DetailNoise_Tex ("细节噪声", 3D) = "white" {}
        [Sub(D)] _DetailNoise_Scale ("细节噪声_尺寸", Vector) = (1, 1, 1, 1)
        [Sub(D)] _DetailNoise_Offset ("细节噪声_偏移", Vector) = (0, 0, 0, 0)
        [Sub(D)] _DetailNoise_Time("运动速度", Range(-1, 1)) = 0   
        [Sub(D)] _DetailNoise_Density("细节侵蚀强度", Range(0, 50)) = 0.1  
        [Sub(D)] _DetailNoise_Weight("细节侵蚀过度", Range(0.01, 10)) = 0.1  


        [Sub(D)] _BoxEdgeSoft("范围盒边缘衰减",Vector) = (1, 1, 1, 1)

        // 天气，类型设置 ————
        [Main(Weather, _, on, off)] Weather ("天气，类型设置", float) = 0
        [Sub(Weather)] _Cloud_WeatherMap("云天气图", 2D) = "white" {}
        [Sub(Weather)] _Cloud_TepMap("云类型图", 2D) = "white" {}
        [Sub(Weather)] _WeatherFactor("天气", Range(0,2)) = 1
        [Sub(Weather)] _CloudFactor("类型", Range(0,2)) = 1

        // 模糊设置 ————
        [Main(Blur, _, on, off)] Blur ("模糊设置", float) = 0
        [Sub(Blur)] _BlurRadius("模糊半径", Range(0.0001,1)) = 0.1
        [Sub(Blur)] _SpatialWeight("空间权重", Range(0.001,100)) = 10
        [Sub(Blur)] _TonalWeight("总权重", Range(0.001,1)) = 0.1
    }

    SubShader
    {   
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        LOD 100
        ZWrite Off 
        Cull Off

        // 云计算
        Pass
        {
            Name "RF_CloudText_Cloud"
            HLSLPROGRAM
            #pragma vertex Vert      
            #pragma fragment frag_m

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #define random(seed) sin(seed * 641.5467987313875 + 1.943856175)            // 随机值

            CBUFFER_START(UnityPerMaterial)
                int  _StepCount;             // 步进次数
                half _SeedScale;             // 步进随机值强度

                half4  _CloudColor;
                half4 _CloudSigma;
                half  _Absorption;           // 介质吸收系数
                half _LightAbsorption;       // 散射吸收系数 
                half _LightPower;            // 光照强度
                half _LightAbsorptionTowardSun;  // 向着太阳的光吸收
                half _DarknessThreshold;         // 向着太阳的光吸收

                half _HgPhaseG0;            // 散射常量 
                half _HgPhaseG1;            // 散射常量 
                half _phaseBase;            // 散射基础值
                half _phaseMultiply;        // 散射影响系数

                half  _DensityMult;         // 总密度
                // 基础形状噪波
                half4 _ShapeNoise_Scale;
                half4 _ShapeNoise_Offset;
                half  _ShapeNoise_Time;
                half  _ShapeNoise_Density;       
                half  _ShapeNoiseDensityOffset;
                // 细节控制噪声
                half3 _DetailNoise_Scale;
                half3 _DetailNoise_Offset;
                half  _DetailNoise_Time;
                half  _DetailNoise_Density;
                half  _DetailNoise_Weight;

                half  _WeatherFactor;
                half  _CloudFactor;

                // 包围盒数据 ---
                half4 _VolumeBoxMin;     
                half4 _VolumeBoxMax;     
                half  _IsVolumeBoxActive; 
                half3 _BoxEdgeSoft;         // 包围盒边缘过度数值

            CBUFFER_END

            TEXTURE2D(_SeedNoiseMap); 
            TEXTURE2D(_Cloud_WeatherMap);  
            TEXTURE2D(_Cloud_TepMap);  

            sampler3D _ShapeNoise_Tex;
            sampler3D _DetailNoise_Tex;

            #include "Assets/Test/Cloud Text/Cloud_Faction.hlsl"

            //片元计算
            half4 frag_m(Varyings IN) : SV_Target
            {
                half2 uv = IN.texcoord;
                half4 MainTex =  SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);

                half depth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, uv).r;      
                half linearDepth = LinearEyeDepth(depth, _ZBufferParams);           
                half3 WorldPosition = ComputeWorldSpacePosition(uv, depth, UNITY_MATRIX_I_VP);    // 世界位置
                
                half3 ViewPos =  _WorldSpaceCameraPos;                         //摄像机的世界坐标
                half3 ViewDir = normalize( WorldPosition - ViewPos );          //视线方向
                
                half2 RayBoxInfo = RayBoxDst(ViewPos, ViewDir, _VolumeBoxMin.xyz, _VolumeBoxMax.xyz );
                half  DstToBox = RayBoxInfo.x;                                  // 入射距离
                half  DstInsideBox = RayBoxInfo.y;                              // 体积内射线长度
                half  DstToOpaque = length(WorldPosition - ViewPos);            //到不透明物体距离  用于深度剔除
                half  DstLimit = min(DstToOpaque - DstToBox, DstInsideBox);     // 需要步进的长度

                _StepCount = min(_StepCount,64);                        // 限制步进次数
                half StepSizeBase = DstInsideBox/_StepCount;            // 基础步进距离
                const int _LightStepsSum = 2;                                // 光路计算步进次数
                half3 CurrentPoint = ViewPos + ViewDir * DstToBox;      // 当前采样点位置
                half  DstTravelled = 0;					                // 已经走过的距离，与DstLimit所比较可以中断当前的采样

                half3 lightIntensity = 0;                               // 光照强度积分
                half  Transmittance = 1.0;                              // 透光度

                if (DstInsideBox > 0.0)
                {
                    half seed = SAMPLE_TEXTURE2D_LOD(_SeedNoiseMap, sampler_LinearRepeat, SquareUV(uv * 10), 0).r ;
                    seed = (seed * 2 - 1) * _SeedScale;
                
                    half cos_angle = dot(ViewDir, _MainLightPosition.xyz);
                    half phaseVal = lerp(HgPhaseFunction( cos_angle, _HgPhaseG0), HgPhaseFunction( cos_angle, _HgPhaseG1), 0.5);
                    phaseVal = _phaseBase + phaseVal * _phaseMultiply;
                
                    for (int ii = 0; ii < _StepCount; ++ii )
                    {
                        if (DstTravelled >= DstLimit || Transmittance < 0.01){
                            break; 
                        }
                
                        // 采样距离场，找到到云表面的距离 (mCloudDistance)
                        half cloud_distance = GetCloudDistance(CurrentPoint, _VolumeBoxMin.xyz, _VolumeBoxMax.xyz);
                        half StepSize = max(cloud_distance, StepSizeBase );

                        // 检查是否进入云内并进行计算
                        if (cloud_distance <= 0.0)
                        {
                            half Dx = SampleDensity(CurrentPoint, _VolumeBoxMin.xyz, _VolumeBoxMax.xyz) * StepSize;
                            
                            // 只有当密度大于一个极小值时才进行计算
                            if (Dx > 0.001)
                            {   
                                half lightPathDensity = LightPathDensity(CurrentPoint, _LightStepsSum, _VolumeBoxMin.xyz, _VolumeBoxMax.xyz);
                                half3 Energy = BeerPowder(lightPathDensity * _LightAbsorption * _CloudSigma.xyz, 6) * Dx * _CloudSigma.xyz * phaseVal;
                
                                //half3 sigma = _CloudSigma.xyz * _LightAbsorption;
                                //Energy = (Energy - Energy * BeerPowder(lightPathDensity * sigma, 6)) / sigma;
                
                                lightIntensity += Energy * Transmittance;
                                Transmittance *= exp(-Dx * _Absorption);
                                
                                StepSize = StepSizeBase * 0.8;  // 采样到密度时  步进距离缩小
                            }
                        }

                        CurrentPoint += ViewDir * StepSize * (1 + seed);
                        DstTravelled += StepSize;

                        StepSize = StepSizeBase * 1.2;       // 采样到密度时  步进距离扩大
                    }
                }
                half3 CloudColor = lightIntensity * _MainLightColor.xyz * _CloudColor.xyz * _LightPower;
                
                return half4( CloudColor , Transmittance );
            }

            ENDHLSL
        }


         // 双边模糊
        Pass
        {
            Name "RF_CloudText_BilateralBlur"
            HLSLPROGRAM
            #pragma vertex Vert      
            #pragma fragment frag_m

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #define TAU (PI * 2.0)

            CBUFFER_START(UnityPerMaterial)
                half _BlurRadius;
                half _SpatialWeight;
                half _TonalWeight;
            CBUFFER_END

            half GaussianWeight(half d, half sigma) 
            {
                return 1.0 / (sigma * sqrt(TAU)) * exp(-(d * d) / (2.0 * sigma * sigma));
            }

            half4 GaussianWeight(half4 d, half sigma)
            {
                return 1.0 / (sigma * sqrt(TAU)) * exp(-(d * d) / (2.0 * sigma * sigma));
            }

            half4 BilateralWeight(half2 currentUV, half2 centerUV, half4 currentColor, half4 centerColor) 
            {
                half spacialDifference = length(centerUV - currentUV);
                half4 tonalDifference = centerColor - currentColor;
                return GaussianWeight(spacialDifference, _SpatialWeight) * GaussianWeight(tonalDifference, _TonalWeight);
            }

            half4 frag_m(Varyings IN) : SV_Target
            {
                half2 uv = IN.texcoord;

                half4 numerator  = 0;
                half4 denominator = 0;

                half4 centerColor = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);

                for (int iii = -1; iii <= 1; iii++) 
                {
                    for (int jjj = -1; jjj <= 1; jjj++) 
                    {
                        half2 offset = half2(iii, jjj) * _BlurRadius * 0.01;

                        half2 currentUV = uv + offset ;
                        half4 currentColor = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, currentUV);

                        half4 weight = BilateralWeight(currentUV, uv, currentColor, centerColor);
                        numerator += currentColor * weight;
                        denominator += weight;
                    }
                }

                return numerator/denominator;
            }
            ENDHLSL
        }


        // 混合
        Pass
        {
            Name "RF_CloudText_Blend"
            HLSLPROGRAM
            #pragma vertex Vert      
            #pragma fragment frag_m

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D(_CloudTexTex);   

            half4 frag_m(Varyings IN) : SV_Target
            {
                float2 uv = IN.texcoord;
                half4 MainTex =  SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);
                half3 ColorRGB = MainTex.rgb ;
                half ColorAlpha = MainTex.a ;

                half4 VolumeColor =SAMPLE_TEXTURE2D(_CloudTexTex, sampler_LinearClamp, uv );
               
                ColorRGB = ColorRGB * VolumeColor.a + VolumeColor.rgb;

                return half4( ColorRGB , 1 );
            }
            ENDHLSL
        
        }


    }
    CustomEditor "LWGUI.LWGUI"
}