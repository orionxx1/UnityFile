#ifndef FA_SHADOW_CASTER_PASS_INCLUDED
    #define FA_SHADOW_CASTER_PASS_INCLUDED

    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
    #include "SeaGrassSpaceTransforms.hlsl"

    float3 _LightDirection;
    float _GlobalShaderNormalBiasMultiplier;
    
    struct Attributes
    {
        float4 positionOS   : POSITION;
        half3 normalOS     : NORMAL;
        float2 texcoord     : TEXCOORD0;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct Varyings
    {
        float2 uv           : TEXCOORD0;
        float4 positionCS   : SV_POSITION;
    };


    float3 GetWindGrassWorldPos(float3 posWS,float y)
    {
        float3 cameraTransformRightWS = UNITY_MATRIX_V[0].xyz;
        //UNITY_MATRIX_V[2].xyz == -1 * world space camera Forward unit vector
        float wind = 0;
        wind += (sin(_Time.y * _WindAFrequency + posWS.x * _WindATiling.x + posWS.z * _WindATiling.y) *
            _WindAWrap.x + _WindAWrap.y) * _WindAIntensity; //windA
        wind += (sin(_Time.y * _WindBFrequency + posWS.x * _WindBTiling.x + posWS.z * _WindBTiling.y) *
            _WindBWrap.x + _WindBWrap.y) * _WindBIntensity; //windB
        wind += (sin(_Time.y * _WindCFrequency + posWS.x * _WindCTiling.x + posWS.z * _WindCTiling.y) *
            _WindCWrap.x + _WindCWrap.y) * _WindCIntensity; //windC
        //wind *= posWS.y; //wind only affect top region, don't affect root region
        wind *= y;
        float3 windOffset = cameraTransformRightWS * wind; //s
       posWS.xyz += windOffset;
        return posWS;
    }
    half4 GetShadowPositionHClip(Attributes input, uint instanceID)
    {
        float3 positionWS = TransformObjectToWorld(input.positionOS.xyz, instanceID);
        positionWS = GetWindGrassWorldPos(positionWS,input.texcoord.g);
        half3 normalWS = TransformObjectToWorldNormal(input.normalOS, instanceID);

        float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));

        #if UNITY_REVERSED_Z
        positionCS.z = min(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
        #else
        positionCS.z = max(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
        #endif

        return positionCS;
    }

    Varyings ShadowPassVertex(Attributes input, uint instanceID : SV_InstanceID)
    {
        Varyings output;
        UNITY_SETUP_INSTANCE_ID(input);

        output.uv = TRANSFORM_TEX(input.texcoord, _MainTex);
        output.positionCS = GetShadowPositionHClip(input, instanceID);
        
        
        return output;
    }

    half4 ShadowPassFragment(Varyings input) : SV_TARGET
    {
        #if defined(_ALPHATEST_ON)
            Alpha(SampleAlbedoAlpha(input.uv, TEXTURE2D_ARGS(_MainTex, sampler_MainTex)).a, _Color, _Cutoff);
        #else
            Alpha(SampleAlbedoAlpha(input.uv, TEXTURE2D_ARGS(_MainTex, sampler_MainTex)).a, _Color, 0);
        #endif
        return 0;
    }
#endif
