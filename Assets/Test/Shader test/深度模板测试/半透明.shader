Shader "MyShader/ShenDu&MuBan_Test03"
{
    Properties
    {
        _Color("Tint",Color) = (1,1,1,1)
        _ID("Mask ID",Int)=1
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZComp("ZTest Comp", Float) = 4       //深度写入模式  Unity自带的枚举类型
    }
    SubShader
    {
        Pass
        {
           Tags {   "Queue" = "Geometry+1"  }
           ZTest  [_ZComp]         // 定义深度测试的比较方式
           Blend SrcAlpha OneMinusSrcAlpha
           
           Stencil{
                    Ref[_ID]            // 模板参考值（0-255）
                    Comp  equal         // 比较函数  默认aLways
                    pass  keep          // 测试通过时的操作   默认keep
                    Fail  keep          // 测试失败时的操作   默认keep
                    ZFail  keep         // 深度测试失败时的操作   默认keep
                    }

            HLSLPROGRAM
            #pragma vertex LitPassVertex              //编译指令，用于告诉 Unity 哪个函数是顶点着色器，
            #pragma fragment LitPassFragment          //哪个是片段着色器（像素着色器）

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST;
            float4 _Color;
            CBUFFER_END


            struct a2v
            {
                float4 positionOS    : POSITION;
                float2 uv            : TEXCOORD0;
            };

            struct v2f
            {
                float4 positionCS       : SV_POSITION;
                float3 positionWS       : TEXCOORD0;
                float2 uv               : TEXCOORD1;
            };

            v2f LitPassVertex (a2v v)
            {
                v2f o;
                o.positionWS = TransformObjectToWorld(v.positionOS);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            float4 LitPassFragment (v2f i) : SV_Target
            {
                return _Color;


            }
            ENDHLSL

        }

    }

} 
