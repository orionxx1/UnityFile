Shader "MyShader/NPREYE "
{
    Properties
    {   
        //模板测试
        [Main(stencil, _, on, off)] _StencilSet ("模板测试", float) = 0
        [Sub(stencil)] _StencilID("Stencil ID",Int)=1
        [SubEnum(stencil,UnityEngine.Rendering.CompareFunction)]_StencilComp ("_StencilComp", Float) = 0
        [SubEnum(stencil,UnityEngine.Rendering.StencilOp)] _StencilOp ("Stencil Operation", Int) = 0
        [SubEnum(stencil,UnityEngine.Rendering.StencilOp)] _StencilFail ("Stencil Fail Op", Int) = 0
        [Sub(stencil)] _QueueOffset("Queue offset", Float) = 0.0    //渲染队列


        _Factor("通用检查系数", Range(0.0, 1.0)) = 0

        // 基础信息
        [Main(MainT, _, on, off)] _MainT ("基础贴图信息", float) = 0
        [SubToggle(MainT,_ISFACE)] _IsFace("IsFace", Float) = 0             // hong
        [SubToggle(MainT, _ISHAIR)] _IsHair("IsHair", Float) = 0             // hong
        [SubToggle(MainT, _ISEYE)] _IsEye("IsEye", Float) = 0                // hong
        [Sub(MainT)] _BaseMap("Albedo", 2D) = "white" {}
        [Sub(MainT)] _BaseColor("Color", Color) = (1,1,1,0)
        [Sub(MainT)] _SpecularColor("SpecularColor", Color) = (1,1,1,0)
        [Sub(MainT)] _EmissionColor("EmissionColor", Color) = (1,1,1,0)
        
        // 金属度、粗糙度、AO 法线等信息
        [Main(Group1, _, on, off)] _Group1 ("BRDF贴图信息", float) = 0
        [Tex(Group1)]_MaskMap("MaskMap", 2D) = "white" {}        // ILM贴图 R=金属度     G=未知     B=AO    Alpha=光泽度 
        [Tex(Group1)]_NormalMap("Normal Map", 2D) = "bump" {}    // 法线贴图
        [Tex(Group1)]_EmissionMap("Emission", 2D) = "black" {}   // 自发光贴图

        [Sub(Group1)] _SmoothnessDef("SmoothnessDef", Range(0.0, 1.0)) = 0.5     // 默认光滑度
        [Sub(Group1)] _Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5
        [Sub(Group1)] _MetallicDef("MetallicDef", Range(0.0, 1.0)) = 0.0         // 默认金属度
        [Sub(Group1)] _Metallic("Metallic", Range(0.0, 1.0)) = 0.0
        [Sub(Group1)] _OcclusionScale("OcclusioScale",Range(0.0,2.0)) = 0.5   // AO系数
        [Sub(Group1)] _NormalScale("NormalScale", Range(0.0, 2.0)) = 1.0      // 法线强度
        [Sub(Group1)] _EmissionScale("EmissionScale",Range(0.0,2.0)) = 0.5    // 自发光强度
        
        // 颜色调整
        [Main(Group2, _, on, off)] _Group2 ("颜色调整", float) = 0
        [Sub(Group2)] _FinierColor ("FinierColor", Color) = (1,1,1,0)
        [Sub(Group2)] _FinierPow("FinierPow", Range(1, 5)) = 2
        [Sub(Group2)] _FrontColor("FrontColor", Color) = (1,1,1,1)            // 自定义亮面颜色
        [Sub(Group2)] _ShadowColor("ShadowColor", Color) = (1,1,1,0)          // 自定义阴影颜色
        [Sub(Group2)] _ShadowSmooth("ShadowSmooth", Range(0.0, 4.0)) = 0      // 阴影平滑系数

        [Title(Ramp)]
        [Tex(Group2)] _RampMap("RampMap", 2D) = "white" {}                    // Ramp贴图
        [Sub(Group2)] _RampScale("RampScale", Range(0.0, 1.0)) = 0.5          // Ramp影响强度
        
        [Title(MatCap)]
        [Tex(Group2)] _MatCap("MatCap", 2D) = "white" {}                         // MatCap贴图
        [Sub(Group2)] _MatCapColor("MatCapColor", Color) = (1,1,1,0)             // MatCap染色
        [Sub(Group2)] _ScaleOfMult("ScaleOfMult", Range(0.0, 1.0)) = 0.0         // 金属度影响系数
        [Title(Blend_Add_Mulit_Overlay )]
        [Sub(Group2)] _MatCapMode ("MatCapMode", Range(0.0, 3.0)) = 0            // MatCap混合模式  0=混合 1=相加 2=相乘 3=叠加
        [Sub(Group2)] _MatCapIntensity("MatCapIntensity", Range(0.0, 5.0)) = 0   // MatCap强度
        [Sub(Group2)] _MatCapScale("MatCapScale", Range(0.0, 1.0)) = 0.0         // MatCap系数

        // NPR设置
        [Main(Group3, _, on, off)] Group3 ("NPR调整", float) = 0
        
        [Title(FaceSDF_EYEMask)]
        [Tex(Group3)] _OtherMap("OtherMap", 2D) = "white" {}  
        [Sub(Group3)] _SpeculerScale("SpeculerScale", Range(0, 5))= 0.0              // 头发高光亮度
        
        [Title(Eye)]
        [Sub(Group3)] _EyeSpeCol("EyeSpeCol", Color) = (1,1,1,0)
        [Sub(Group3)] _EyeHeightScale("EyeHeightScale", Range( -0.1, 0.1))= 1

        [Title(Hair)]
        [Sub(Group3)] _HairSpeRange("HairSpeRange", Range(1, 10))= 0.0     // 头发高光 范围
        
        [Title(Face)]
        // FcaeMask  R=嘴唇高光   G=NPR PBR混合系数    B=描边遮罩
        [Sub(Group3)] _FaceShadowSmooth("FaceShadowSmooth", Range(0.0, 0.5)) = 0 
        [Sub(Group3)] _ShallowFadeCor("ShallowFadeCor", Color) = (0.6,0.6,0.6,0)
        [Sub(Group3)] _SSSCor("SSSCor", Color) = (1,0.88,0.8,0)
        [Sub(Group3)] _ForntCor("ForntCor", Color) = (1,0.9,0.85,0)
        [Sub(Group3)] _ForwardCor("ForwardCor", Color) = (1,1,1,0)
        [Sub(Group3)] _CheekCor("CheekCor", Color) = (1,1,1,0)      //脸颊

        // 描边
        [Main(M, _, on, off)] _M ("描边设置", float) = 1
        [SubToggle(M,_OUTLINE_ON)] _OutlineOn ("Outline On", Float) = 1
        [Sub(M)] _OutLineColor("OutLineColor", Color) = (0.5,0.5,0.5,1)
        [Sub(M)] _OutlineColorBLend("OutlineColorBLend", Range(0, 1))= 0.5            // 和基础色混合   
        [Sub(M)] _OutlineWidth("OutlineWidth", Range(0, 1))= 0.5           
        [Sub(M)] _ZOffset("ZOffset", Range(0, 1))= 0.5 
        

        // 混合设置
        [Main(Preset, _, on, off)] _PresetGroup ("混合设置", float) = 1
        [SubEnum(Preset, UnityEngine.Rendering.CullMode)]_CullMode ("CullMode", float) = 2          // 剔除模式
        [Preset(Preset, LWGUI_Preset_BlendMode)] _BlendMode ("Blend Mode Preset", float) = 0        // 不透明 透明 切换
        
        [Sub(Preset)] _AlphaFactor("AlphaFactor", Range(0, 1))= 1                                   // 透明程度
        [SubToggle(Preset,_CUTOFFON)] _AlphaClip("AlphaClip", Float) = 0.0                          // 开启透明度裁切
        [Sub(Preset)]_Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5                                  // 透明度裁切阈值

        [SubEnum(Preset, UnityEngine.Rendering.BlendMode)] _SrcBlend ("SrcBlend", Float) = 1
		[SubEnum(Preset, UnityEngine.Rendering.BlendMode)] _DstBlend ("DstBlend", Float) = 0
        [SubToggle(Preset)] _ZWrite ("ZWrite ", Float) = 1


        // 其他设置
        
        [ToggleOff] _EnvironmentReflections("Environment Reflections", Float) = 1.0     //环境光开关
        [ToggleUI] _ReceiveShadows("Receive Shadows", Float) = 1.0                      //阴影接收开关

    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "IgnoreProjector" = "True"
            "QueueOffset" = "_QueueOffset" 
        }
        LOD 300
        
        Pass
        {
            Name "NPRForward"
            Tags
            {   "LightMode" = "UniversalForward"    }

            // -------------------------------------
            Blend [_SrcBlend][_DstBlend]
            ZWrite [_ZWrite]
            ZTest Always
            Cull [_CullMode]
            

            Stencil
            {
                Ref  [_StencilID]
                Comp [_StencilComp]
                Pass [_StencilOp]
                Fail [_StencilFail]
            }   

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex LitPassVertex
            #pragma fragment LitPassFragment
        
            // -------------------------------------
            // 材质关键字   必须大写
            #pragma shader_feature_local _ISFACE  
            #pragma shader_feature_local _ISHAIR 
            #pragma shader_feature_local _ISEYE 
            #pragma shader_feature_local _CUTOFFON

            #pragma shader_feature_local _RECEIVE_SHADOWS_OFF                                   // 是否禁用阴影接收    Shadows.hlsl文件中
            #pragma shader_feature_local_fragment _SURFACE_TYPE_TRANSPARENT                     //表面l类型 不透明 半透明
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature_local_fragment _ENVIRONMENTREFLECTIONS_OFF   //关闭环境反射
        
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ EVALUATE_SH_MIXED EVALUATE_SH_VERTEX
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS                  //附加光源投射阴影
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING                 //混合多个反射探针
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION           //立方体投影修正  避免反射扭曲
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH        //启用软阴影
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION        //SSAO 增强场景深度感
            #pragma multi_compile_fragment _ _DBUFFER_MRT1 _DBUFFER_MRT2 _DBUFFER_MRT3
            #pragma multi_compile _ _LIGHT_LAYERS               //按层级控制光源影响  如仅特定光源影响角色
            #pragma multi_compile _ _FORWARD_PLUS       
        
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
        
            #include "NPRInput.hlsl"
            #include "NPRForwardPass.hlsl"
        
            ENDHLSL
        }

    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
    CustomEditor "LWGUI.LWGUI"
}
