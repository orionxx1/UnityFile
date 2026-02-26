Shader "MyShader/BlendMode"
{
    Properties
    {
        [Enum(UnityEngine.Rendering.BlendOp)] _BlendOp ("BlendOp", Float) = 0
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend ("SrcBlend", Float) = 1
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend ("DstBlend", Float) = 0
        [Enum(Off, 0, On, 1)]_ZWriteMode ("ZWriteMode", float) = 1
        _MainTex ("Texture", 2D) = "white" { }
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
            float4 _MainTex_ST;
            float  _Factor;
            CBUFFER_END

            struct appdata
            {
                float4 vertex_OS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex_CS : SV_POSITION;
            };

            TEXTURE2D(_MainTex);            SAMPLER(sampler_MainTex);
            

            v2f vert(appdata v)
            {
                v2f o;
                float3 vertex_WS = TransformObjectToWorld(v.vertex_OS);
                o.vertex_CS = TransformWorldToHClip(vertex_WS);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                float4 col = SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex ,i.uv) * (1,1,1,_Factor);
                return col;
            }
            ENDHLSL
        }
    }
}