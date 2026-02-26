Shader "MyShader/SceneSeaGrass"
{
	Properties
	{
		[Main(GroupSurfaceOptions, _, on, off)] _EnableGroupSurfaceOptions("基础设置(Surface Options)", Float) = 1
		[Preset(GroupSurfaceOptions, Grass_YuShe)] _Surface("表面类型(Surface Type)", Float) = 0.0
		[ShowIf(_Surface, Equal, 1.0)]
		[Sub(GroupSurfaceOptions)]_Cutoff("Cutoff (Default: 0.5)", Range(0.0, 0.99)) = 0.5
		[SubEnum(GroupSurfaceOptions, CullMode)]_Cull("Cull Mode", Int) = 0
		[SubEnum(GroupSurfaceOptions, UnityEngine.Rendering.CompareFunction)]_ZTest("ZTest (Default: LessEqual)", Float) = 4
		[SubEnum(GroupSurfaceOptions, UnityEngine.Rendering.CompareFunction)]_Comp("Comp",Float) = 8
		[SubEnum(GroupSurfaceOptions, UnityEngine.Rendering.StencilOp)]_Pass("Pass",Float) = 2
		[Sub(GroupSurfaceOptions)] _StenilRef("Stenil Ref", Float) = 0

		[Space]
		[Main(GroupBaseOptions, _, on, off)] _EnableGroupBaseOptions("基础设置", Float) = 1
		[Sub(GroupBaseOptions)][MainTexture]_MainTex("Main Texture", 2D) = "white" {}
		[Sub(GroupBaseOptions)]_AlphaTex("Alpha Texture", 2D) = "white" {}
		[Sub(GroupBaseOptions)]_NormalTex("Alpha Texture", 2D) = "white" {}
		[Sub(GroupBaseOptions)]_NoiseTex("Noise Texture", 2D) = "white" {}
		[Sub(GroupBaseOptions)][MainColor]_Color("主颜色(Main Color)", Color) = (1,1,1,1)
		[Sub(GroupBaseOptions)]_NormalLetp("法线矫正(NormalLetp)", Range(0,1)) = 0.5
		[Sub(GroupBaseOptions)]_AOCorrect("AO矫正(AOCorrect)", Range(0.01,2)) = 1
		[Sub(GroupBaseOptions)]_Smoothness("粗糙度", Range(0.01,1)) = 0.4
		[Sub(GroupBaseOptions)]_GlassRange("高光范围", Range(0.001,1)) = 0.4
		[Sub(GroupBaseOptions)]_GlassPower("高光强度", Range(0,5)) = 0.4
		[Sub(GroupBaseOptions)]_GlassColor("高光颜色", Color) = (1,1,1,1)

		[Space]
		[Main(WindSet, _, on, off)] _WindSet("WindSet设置", Float) = 1
        [Sub(WindSet)]_WindAIntensity("_WindAIntensity", Float) = 1.77
        [Sub(WindSet)]_WindAFrequency("_WindAFrequency", Float) = 4
        [Sub(WindSet)]_WindATiling("_WindATiling", Vector) = (0.1,0.1,0)
        [Sub(WindSet)]_WindAWrap("_WindAWrap", Vector) = (0.5,0.5,0)
		
		[Space]
        [Sub(WindSet)]_WindBIntensity("_WindBIntensity", Float) = 0.25
        [Sub(WindSet)]_WindBFrequency("_WindBFrequency", Float) = 7.7
        [Sub(WindSet)]_WindBTiling("_WindBTiling", Vector) = (.37,3,0)
        [Sub(WindSet)]_WindBWrap("_WindBWrap", Vector) = (0.5,0.5,0)
		
		[Space]
        [Sub(WindSet)]_WindCIntensity("_WindCIntensity", Float) = 0.125
        [Sub(WindSet)]_WindCFrequency("_WindCFrequency", Float) = 11.7
        [Sub(WindSet)]_WindCTiling("_WindCTiling", Vector) = (0.77,3,0)
        [Sub(WindSet)]_WindCWrap("_WindCWrap", Vector) = (0.5,0.5,0)
		
		[Header(Alpha Clip)]
		
		[HideInInspector]_Mode("__mode", Float) = 0.0
		[HideInInspector]_SrcBlend("__src", Float) = 1.0
		[HideInInspector]_DstBlend("__dst", Float) = 0.0
		[HideInInspector]_ZWrite("__zw", Float) = 1.0
	}


	SubShader
	{
		Tags {
			"RenderType" = "TransparentCutout"
			"RenderPipeline" = "UniversalPipeline"
			"Queue" = "AlphaTest"
		}
		LOD 300
		AlphaToMask On


		Pass
		{
			Name "StandardLit"

			Cull [_Cull]
			Blend [_SrcBlend] [_DstBlend]
			ZWrite [_ZWrite]
			ZTest [_ZTest]
			Stencil
			{
				Ref [_StenilRef]
				Comp [_Comp]
				Pass [_Pass]
			}

			HLSLPROGRAM

			#pragma prefer_hlslcc gles
			#pragma exclude_renderers d3d11_9x
			#pragma target 2.0
            
			#pragma multi_compile_local _ _ALPHATEST_ON

			#pragma shader_feature _ _FORWARD_PLUS_Z_BINING
            #pragma multi_compile_fog
			
			#pragma multi_compile_local _ _UT_INSTANCING_ON
            #pragma shader_feature _ DEBUG_DISPLAY
            //#pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            //#pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _SHADOWS_SOFT 
			
			#pragma vertex SceneObjectVertex
			#pragma fragment SceneObjectFragment


			#define NO_TPA
			#define TERRAINSIZE 200

			#include "SceneSeaGrass-Input.hlsl"
			#include "SceneSeaGrass-Lib.hlsl"
			ENDHLSL
		}





		Pass
		{
			Name "ShadowCaster"
			Tags{"LightMode" = "ShadowCaster"}

			Cull [_Cull]
			ZWrite On
			ZTest LEqual
			ColorMask 0

			HLSLPROGRAM
			#pragma prefer_hlslcc gles
			#pragma exclude_renderers d3d11_9x
			#pragma target 2.0

			//--------------------------------------
			// GPU Instancing
			//#pragma multi_compile_instancing

			// -------------------------------------
			// Material Keywords
			#pragma multi_compile_local _ _UT_INSTANCING_ON
			#pragma shader_feature_local_fragment _ALPHATEST_ON
			//#pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

			#pragma vertex ShadowPassVertex
			#pragma fragment ShadowPassFragment
			#define NO_TPA

			#include "SceneSeaGrass-Input.hlsl"
			#include "SeaGrassShadowCasterPass.hlsl"
			ENDHLSL 
		}

	}

	CustomEditor "LWGUI.LWGUI"
}
