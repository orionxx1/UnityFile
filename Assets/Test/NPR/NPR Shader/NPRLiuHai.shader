Shader "MyShader/NPRLiuHai"
{
    Properties
    {
        _Color("Tint",Color) = (1,1,1,1)
        _ScreenOffsetScaleX("ScreenOffsetScaleX", Range(0.0, 1.0)) = 0.5
        _ScreenOffsetScaleY("ScreenOffsetScaleY", Range(0.0, 1.0)) = 0.5

        [Enum(UnityEngine.Rendering.BlendOp)] _BlendOp ("BlendOp", Float) = 0
        _ID("Stencil ID",Int)=1
        [Enum(UnityEngine.Rendering.CompareFunction)]_StencilComp ("_StencilComp", Float) = 0
        [Enum(UnityEngine.Rendering.StencilOp)] _StencilOp ("Stencil Operation", Int) = 0
        [Enum(UnityEngine.Rendering.StencilOp)] _StencilFail ("Stencil Fail Op", Int) = 0
        _QueueOffset("Queue offset", Float) = 0.0    //渲染队列
    }

    SubShader
    {

        Pass
        {
            Tags {  "RenderType"="Translucency"  "Queue" = "Geometry"    "QueueOffset" = "_QueueOffset"}
            ZWrite off    //深度写入模式
            Blend  SrcAlpha OneMinusSrcAlpha
            BlendOp [_BlendOp] 
            Cull   Back

            Stencil{
                    Ref   [_ID]         //写入模板
                    Comp  [_StencilComp]        //默认aLways
                    Pass [_StencilOp]
                    Fail [_StencilFail]
                    }


            HLSLPROGRAM
            #pragma vertex LitPassVertex              //编译指令，用于告诉 Unity 哪个函数是顶点着色器，
            #pragma fragment LitPassFragment          //哪个是片段着色器（像素着色器）

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            CBUFFER_START(UnityPerMaterial)
            float4 _Color;
            half  _ScreenOffsetScaleX;
            half  _ScreenOffsetScaleY;
            CBUFFER_END


            struct a2v
            {
                float4 positionOS    : POSITION;
            };

            struct v2f
            {
                float4 positionCS       : SV_POSITION;
                float3 positionWS       : TEXCOORD0;
            };

            v2f LitPassVertex (a2v v)
            {
                v2f o;
                Light mainLight = GetMainLight();
                float3 lightDirWS = normalize(mainLight.direction);
                float3 lightDirVS = normalize(TransformWorldToViewDir(lightDirWS));
                // 相机向上:让影子靠近脸部.
                float3 positionVS = TransformWorldToView(TransformObjectToWorld(v.positionOS));

                o.positionWS = TransformObjectToWorld(v.positionOS);
                positionVS.x -= 0.004 * lightDirVS.x * _ScreenOffsetScaleX;
                positionVS.y -= 0.007 * lightDirVS.y * _ScreenOffsetScaleY ;
                o.positionCS = TransformWViewToHClip(positionVS);
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
