Shader "MyShader/ShenDu&MuBan_Test"
{
    Properties
    {
        _Color("Tint",Color) = (1,1,1,1)
        _StencilID("Stencil ID",Int)=1
        [Enum(UnityEngine.Rendering.CompareFunction)] _StencilComp ("Stencil Comp", Float) = 0
        [Enum(UnityEngine.Rendering.StencilOp)] _Stencilpass ("Stencil pass", Int) = 0
        [Enum(UnityEngine.Rendering.StencilOp)] _StencilFail ("Stencil Fail", Int) = 0
        [Enum(UnityEngine.Rendering.StencilOp)] _ZTestFail ("ZTest Fail", Int) = 0

        [Enum(UnityEngine.Rendering.CullMode)]_CullMode ("CullMode", float) = 2
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZComp("ZTest Comp", Float) = 4
        [Toggle(Preset)] _ZWrite ("ZWrite ", Float) = 1

        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend ("SrcBlend", Float) = 1
		[Enum(UnityEngine.Rendering.BlendMode)] _DstBlend ("DstBlend", Float) = 0

        _QueueOffset("Queue offset", Float) = 0.0    //渲染队列



    }
    SubShader
    {
        Pass
        {
           Tags {  "RenderType"="Opaque"    "Queue" = "Geometry"      "QueueOffset" = "_QueueOffset"     }
           //ColorMask              // 不写入颜色
           ZTest  [_ZComp]          // 定义深度测试的比较方式
           ZWrite [_ZWrite]         //深度写入模式
           Cull   [_CullMode]
           Blend[_SrcBlend][_DstBlend]

           Stencil{
                    Ref   [_StencilID]         //写入模板
                    Comp  [_StencilComp]       //默认aLways
                    pass  [_Stencilpass]  
                    Fail  [_StencilFail]  
                    ZFail [_ZTestFail]  
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
