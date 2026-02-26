Shader "MyShader/Early_Z"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" { }
    }
    SubShader
    {
     
        Pass
        {
            Name "EarlyZ"

            ZWrite On   	//开启深度测试
            ZTest LEqual    //小于等于
            ColorMask 0     // 关闭颜色输出
        }


        // 主渲染Pass (利用Early-Z结果)
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            ZWrite Off		//关闭深度写入
            ZTest Equal		//深度相等为通过
            Cull Back       // 背面剔除

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST;
            CBUFFER_END

            TEXTURE2D(_MainTex);            SAMPLER(sampler_MainTex);

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


            v2f vert(appdata v)
            {
                v2f o;
                float3 vertex_WS = TransformObjectToWorld(v.vertex_OS);
                o.vertex_CS = TransformWorldToHClip(vertex_WS);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            };

            float4 frag(v2f i) : SV_Target
            {
                float4 col = SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex ,i.uv);
                return col;
            };

            ENDHLSL
        }

    }

}