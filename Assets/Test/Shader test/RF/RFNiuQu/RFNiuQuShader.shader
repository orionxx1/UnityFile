Shader "MyShader/RF/RFNiuQuShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _CenterPos_Str_Scatter("CenterPos_Str_Scatter", Vector) = (0.5,0.5,1,0)
        _Concentration("Concentration",float) = 100
    }
   
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        
        Pass
        {
            ZTest Off
            ZWrite Off

            HLSLPROGRAM
            #pragma vertex Vert      
            #pragma fragment frag_m
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            //顶点数据结构、片元数据结构、顶点着色器在Blit.hlsl中定义


            float4 _CenterPos_Str_Scatter;
            float  _Concentration;

            real3 HSVToRGB(real3 c) 
            {
                real4 K = real4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
                real3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
                return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
            }

            real3 RGBToHSV(real3 c) 
            {
                real4 K = real4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
                real4 p = lerp(real4(c.bg, K.wz), real4(c.gb, K.xy), step(c.b, c.g));
                real4 q = lerp(real4(p.xyw, c.r), real4(c.r, p.yzx), step(p.x, c.r));
                real d = q.x - min(q.w, q.y);
                real e = 1.0e-10;
                return real3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
            }

            half4 frag_m(Varyings i):SV_TARGET 
            {
                # if !UNITY_REVERSED_Z
                      _CenterPos_Str_Scatter.y = 1- _CenterPos_Str_Scatter.y;
                #endif

                half4 col = half4(1, 1, 1, 1);
                half2 vec = i.texcoord - _CenterPos_Str_Scatter.xy;
                vec.x = vec.x * _ScreenParams.x / _ScreenParams.y;
                half distSQUARE = dot(vec, vec); //与中心点的距离的平方
                half aaa = (_CenterPos_Str_Scatter.w * _CenterPos_Str_Scatter.w - distSQUARE); //与圆环的距离的平方
                half colorInt = saturate(aaa); //ColorTint 的浓度,其余为黑,实心
                colorInt = 1 - pow(1 - colorInt, 10);
                half tortInt = 1 - saturate(aaa * aaa); //扭曲强度
                //控制圆环的宽度
                tortInt = pow(tortInt, _Concentration) * _CenterPos_Str_Scatter.z;

                i.texcoord += tortInt * aaa * half2(0.1, 0.1);  //采样Blit图的UV
                col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord); //采样的Blit图

                half3 hsv_col = RGBToHSV(col.xyz);
                hsv_col.y = saturate(hsv_col.y - colorInt);
                col.xyz = HSVToRGB(hsv_col);
                return col;
            }
            ENDHLSL
        }
    }
}
