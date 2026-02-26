Shader "Custom/ImageSunShafts"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _LightScreenPos ("Light Screen Pos (XY)", Vector) = (0.5, 0.5, 0, 0) // XY: 0-1 screen/texture space
        _Density ("Density", Range(0.0, 1.0)) = 0.85         // 控制采样点的密集程度，或说光束的“扩散”程度
        _Decay ("Decay", Range(0.0, 1.0)) = 0.95             // 每次采样光照的衰减率
        _Weight ("Weight", Range(0.0, 2.0)) = 0.5            // 光束的整体强度/权重
        _Exposure ("Exposure", Range(0.0, 5.0)) = 1.0        // 最终光束的曝光度
        _Samples ("Samples", Int) = 64                       // 采样次数，越高效果越好但越耗性能
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Transparent" } // 通常用于后处理或UI
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            float4 _LightScreenPos; 
            float _Density;
            float _Decay;
            float _Weight;
            float _Exposure;
            int _Samples; 

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float2 UV = i.uv;

                // 从当前像素指向光源的向量（未归一化）
                float2 deltaToLight = _LightScreenPos.xy - UV;

                float2 stepVector = deltaToLight * _Density / _Samples;

                // 初始化累积的光照颜色和衰减因子
                float4 accumulatedLight = float4(0,0,0,0);
                float currentDecay = 1.0;

                // 开始采样
                float2 sampleUV = UV;
                for (int s = 0; s < (int)_Samples; s++)
                {
                    // 将采样UV向光源方向移动一步
                    sampleUV += stepVector;

                    // 超出0-1范围的UV采样通常会根据纹理的Wrap Mode处理 (Clamp, Repeat)
                    // Clamp模式在这里比较合适，避免从图片另一边采样
                    float4 sampleColor = tex2D(_MainTex, sampleUV);
                    sampleColor = Luminance(sampleColor)*sampleColor;

                    // 将采样颜色乘以当前衰减和权重，并累加
                    accumulatedLight += sampleColor * currentDecay * _Weight;

                    // 更新衰减因子
                    currentDecay *= _Decay;
                }
                fixed4 originalColor = tex2D(_MainTex, i.uv);

                fixed4 finalColor = originalColor + accumulatedLight * _Exposure;
                

                return finalColor;
            }
            ENDCG
        }
    }
    Fallback "Diffuse"
}