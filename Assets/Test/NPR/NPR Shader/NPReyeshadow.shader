Shader "MyShader/NPReyeshadow"
{
    Properties
    {
        [Enum(UnityEngine.Rendering.BlendOp)] _BlendOp ("BlendOp", Float) = 0
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend ("SrcBlend", Float) = 1
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend ("DstBlend", Float) = 0
        [Enum(Off, 0, On, 1)]_ZWriteMode ("ZWriteMode", float) = 1
        _Color ("Color", Color) = (1,1,1,0)
        _Factor ("Factor", Range(0,1)) = 0.5
        [Enum(UnityEngine.Rendering.CullMode)]_CullMode ("CullMode", float) = 2  
    }
    
    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent" }
        ZWrite [_ZWriteMode]
        Blend [_SrcBlend] [_DstBlend]       // 混合参数
        BlendOp [_BlendOp]                  // 混合模式
        Cull [_CullMode]
        
        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            CBUFFER_START(UnityPerMaterial)
            half4 _Color;
            float  _Factor;
            CBUFFER_END

            struct appdata
            {
                float4 vertex_OS    : POSITION;
                float2 texcoord     : TEXCOORD0;
            };

            struct v2f
            {
                float4 vertex_CS    : SV_POSITION;
                float2 uv           : TEXCOORD0;    // UV
            };

            

            v2f vert(appdata v)
            {
                v2f o;
                float3 vertex_WS = TransformObjectToWorld(v.vertex_OS);
                o.vertex_CS = TransformWorldToHClip(vertex_WS);
                o.uv = v.texcoord;
                
                return o;
            }


            float4 frag(v2f i) : SV_Target
            {
                float2 uv = i.uv;
                float3 col = _Color;
                float alpby = _Factor * smoothstep(0.001,0.5,uv.g);
                

                return float4( col , alpby );
            }
            ENDHLSL
        }
    }
}