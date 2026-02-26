Shader "MyShader/RianOnaFloor"
{
    Properties
    {

        [MainTexture] _BaseMap("Albedo", 2D) = "white" {}
        [MainColor] _BaseColor("Color", Color) = (1,1,1,1)
        _SpecularColor("SpecularColor", Color) = (1,1,1,1)
        
        _MaskMap("MaskMap", 2D) = "white" {}
        _BumpMap("Normal Map", 2D) = "bump" {}
        _EmissionMap("Emission", 2D) = "black" {}

        _RoughnessDef("RoughnessDef", Range(0.0, 1.0)) = 0.5     // 默认光滑度
        _Roughness("Roughness", Range(0.0, 1.0)) = 0.5
        _MetallicDef("MetallicDef", Range(0.0, 1.0)) = 0.0         // 默认金属度
        _Metallic("Metallic", Range(0.0, 1.0)) = 0.0
        _OcclusionScale("OcclusioScale",Range(0.0,2.0)) = 0.5   //AO系数

        _NormalScale("NormalScale", Range(0.0, 2.0)) = 1.0
        _HeightScale("HeightScale", Range(0.0, 0.2)) = 0.005

        
        _NoiseMap("Noise Map", 2D) = "bump" {}
        _NoiseNormal("NoiseNormal", 2D) = "bump" {}
        _WaterHeight("水位高度", Range(0.0001, 1)) = 0.1               
        _WaterDepth("水底深度", Range(0.0, 0.1)) = 0.01 
        _WaterEdge("水面边缘过度", Range(0.0, 1)) = 0.5 
        _WaterColor("水底染色", Color) = (1,1,1,1)

        _Wetness ("湿度", Range(0.0, 1.0)) = 1    
        
        _SplatsSize("水滴整体尺寸", Range(0.0, 1.0)) = 0.1      
        _SplatsIntensity ("水滴密度", Range(0.0, 1.0)) = 1     
        _SplatsScale("水滴尺寸", Range(0.0, 1.0)) = 1       
        _SplatsNoise ("水滴扭曲", Range(0.0, 0.1)) = 0.01              
        _SplatsSpeed ("水滴速度", Range(0.0, 10)) =  2    
        _SplatsHeight("水滴凹凸", Range(0.0, 1)) = 0.01 

        _RippleSize("水波纹整体尺寸", Range(0.0, 1.0)) = 0.1  
        _RippleIntensity ("水波纹密度密度", Range(0.0, 1.0)) = 1  
        _RippleScale("水波纹尺寸", Range(0.0, 1.0)) = 0.2    
        _RippleNoise ("水波纹扭曲", Range(0.0, 0.1)) = 0.001      
        _RingFrequency ("水波纹频率", Range(0.0, 50)) = 5         
        _RippleSpeed("水波纹速度", Range(0.0, 50)) = 2            
        _RippleHeight("水波纹凹凸", Range(0.0, 0.2)) = 0.05        

        _WaveScale("紊流尺寸", Range(0.0, 5.0)) = 1   
        _WaveSpeed("紊流速度", Range(0.0, 2)) = 0.5  
        _WaveNoise("紊流凹凸", Range(0.0, 2)) = 0.5                   

        [ToggleOff] _SpecularHighlights("Specular Highlights", Float) = 1.0             //高光开关
        [ToggleOff] _EnvironmentReflections("Environment Reflections", Float) = 1.0     //环境光开关

        [Enum(UnityEngine.Rendering.CullMode)]_CullMode ("CullMode", float) = 2    // 剔除模式
        _Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5

        _Surface("__surface", Float) = 0.0
        _Blend("__blend", Float) = 0.0
        [ToggleUI] _AlphaClip("__clip", Float) = 0.0
        [HideInInspector] _SrcBlend("__src", Float) = 1.0
        [HideInInspector] _DstBlend("__dst", Float) = 0.0
        [HideInInspector] _SrcBlendAlpha("__srcA", Float) = 1.0
        [HideInInspector] _DstBlendAlpha("__dstA", Float) = 0.0
        [HideInInspector] _ZWrite("__zw", Float) = 1.0
        [HideInInspector] _BlendModePreserveSpecular("_BlendModePreserveSpecular", Float) = 1.0
        [HideInInspector] _AlphaToMask("__alphaToMask", Float) = 0.0

        [ToggleUI] _ReceiveShadows("Receive Shadows", Float) = 1.0      //阴影接收开关
        _QueueOffset("Queue offset", Float) = 0.0
       
    }

    SubShader
    {

        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "UniversalMaterialType" = "Lit"
            "IgnoreProjector" = "True"
        }
        LOD 300

        // ------------------------------------------------------------------
        Pass
        {
            Name "ForwardLit"
            Tags{
                "LightMode" = "UniversalForward"}

            // -------------------------------------
            Blend[_SrcBlend][_DstBlend], [_SrcBlendAlpha][_DstBlendAlpha]
            ZWrite[_ZWrite]
            Cull[_CullMode]
            AlphaToMask[_AlphaToMask]

            HLSLPROGRAM
            #pragma target 2.0

            // -------------------------------------
            // Shader Stages
            #pragma vertex Vertex
            #pragma fragment Fragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local _RECEIVE_SHADOWS_OFF                                   // 是否禁用阴影接收    Shadows.hlsl文件中
            #pragma shader_feature_local_fragment _SURFACE_TYPE_TRANSPARENT                     //表面l类型 不透明 半透明
            #pragma shader_feature_local_fragment _ALPHATEST_ON                                 //Alpha裁切（如树叶）
            #pragma shader_feature_local_fragment _ _ALPHAPREMULTIPLY_ON _ALPHAMODULATE_ON      //预乘Alpha（半透明）
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature_local_fragment _SPECULARHIGHLIGHTS_OFF       //关闭镜面高光
            #pragma shader_feature_local_fragment _ENVIRONMENTREFLECTIONS_OFF   //关闭环境反射
            #pragma shader_feature_local_fragment _SPECULAR_SETUP

            // -------------------------------------
            // Universal Pipeline keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            //_：无阴影   _SHADOWS：启用主光源阴影（标准阴影贴图）  _SHADOWS_CASCADE：启用级联阴影（CSM，适合大场景）  _SHADOWS_SCREEN：屏幕空间阴影（如URP的Screen Space Shadows）
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            //_：无光照 _LIGHTS_VERTEX：顶点光照（性能好，精度低）  _LIGHTS：逐像素光照（精确，开销大）
            //控制场景中点光源/聚光灯的渲染方式（如角色受多个光源影响时用_ADDITIONAL_LIGHTS）
            #pragma multi_compile _ EVALUATE_SH_MIXED EVALUATE_SH_VERTEX
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS                  //附加光源投射阴影
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING                 //混合多个反射探针
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION           //立方体投影修正  避免反射扭曲
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH        //启用软阴影
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION        //SSAO 增强场景深度感
            #pragma multi_compile_fragment _ _DBUFFER_MRT1 _DBUFFER_MRT2 _DBUFFER_MRT3
            //_DBUFFER_MRT*_DBUFFER_MRT*：多渲染目标（MRT）延迟渲染路径，用于贴花（Decals）系统
            //MRT1：漫反射 + 法线   MRT2：漫反射 + 法线 + 金属/光滑度  MRT3：完整PBR数据,含自发光
            #pragma multi_compile_fragment _ _LIGHT_COOKIES     //模拟复杂光源形状
            #pragma multi_compile _ _LIGHT_LAYERS               //按层级控制光源影响  如仅特定光源影响角色
            #pragma multi_compile _ _FORWARD_PLUS       
            #include_with_pragmas "Packages/com.unity.render-pipelines.core/ShaderLibrary/FoveatedRenderingKeywords.hlsl"
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RenderingLayers.hlsl"


            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING    //光照贴图阴影混合;控制烘焙阴影Baked Shadows和实时阴影Realtime Shadows的混合方式
            #pragma multi_compile _ SHADOWS_SHADOWMASK        //阴影遮罩模式;Shadowmask Mode：静态物烘焙yy，动态物实时yy;Distance Shadowmask：近处实时yy，远处烘焙yy;适合大场景
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED      //启用定向光照贴图（Directional Lightmaps）;存储光照方向信息;配合LIGHTMAP_ON使用
            #pragma multi_compile _ LIGHTMAP_ON     //启用静态光照贴图（Baked Lightmaps）;静态物体（标记为Lightmap Static）使用烘焙光照
            #pragma multi_compile _ DYNAMICLIGHTMAP_ON        //启用动态全局光照（如Enlighten或DOTS GI）;动态物体（如可移动的箱子）也能接收间接光照
            #pragma multi_compile_fragment _ LOD_FADE_CROSSFADE
            #pragma multi_compile_fog
            #pragma multi_compile_fragment _ DEBUG_DISPLAY    //启用Shader的调试信息（如法线、UV、光照贴图等）
            
            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing                  //启用GPU Instancing;允许Unity在单次Draw Call中渲染多个相同网格的实例
            #pragma instancing_options renderinglayer         //启用**渲染层（Rendering Layers）**支持，允许通过实例化数据控制物体的渲染层级
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            #include "Assets/Test/Shader test/Rain/Rain/Input_RianOnFloor.hlsl"
            #include "Assets/Test/Shader test/Rain/Rain/ForwardPass_RainOnFloor.hlsl"

            ENDHLSL
        }

         
        Pass
        {
            Name "ShadowCaster"
            Tags
            {
                "LightMode" = "ShadowCaster"
            }

            // -------------------------------------
            // Render State Commands
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull[_Cull]

            HLSLPROGRAM
            #pragma target 2.0

            // -------------------------------------
            // Shader Stages
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            // -------------------------------------
            // Universal Pipeline keywords

            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile_fragment _ LOD_FADE_CROSSFADE

            // This is used during shadow map generation to differentiate between directional and punctual light shadows, as they use different formulas to apply Normal Bias
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            // -------------------------------------
            // Includes
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }

    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
    //CustomEditor "UnityEditor.Rendering.Universal.ShaderGUI.LitShader"
}
