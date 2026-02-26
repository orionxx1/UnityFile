#ifndef UNIVERSAL_LIT_INPUT_INCLUDED
#define UNIVERSAL_LIT_INPUT_INCLUDED

#include "Core.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
//#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
//#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ParallaxMapping.hlsl"
#include "DBuffer.hlsl"

#if defined(_DETAIL_MULX2) || defined(_DETAIL_SCALED)
    #define _DETAIL
#endif

// NOTE: Do not ifdef the properties here as SRP batcher can not handle different layouts.
CBUFFER_START(UnityPerMaterial)
    float4 _BaseMap_ST;
    half4  _BaseColor;
    half4 _SpecularColor;
    half4 _EmissionColor;

    half _SmoothnessDef;
    half _Smoothness;
    half _MetallicDef;
    half _Metallic;
    half _NormalScale;
    half _OcclusionScale;
    half _EmissionScale;

    half4 _FinierColor;
    half  _FinierPow;
    half  _RampScale;
    half4  _FrontColor;
    half4 _ShadowColor;
    half  _ShadowSmooth;

    half4 _MatCapColor;
    half  _ScaleOfMult;
    half  _MatCapMode;
    half  _MatCapIntensity;
    half  _MatCapScale;

    // 头发、嘴唇、眼睛  高光亮度
    half  _SpeculerScale;     
    // 眼睛高光颜色 眼睛置换
    half4 _EyeSpeCol;
    half  _EyeHeightScale; 
    // 头发高光范围
    half  _HairSpeRange;   
    // 面部数据
    float3 _FaceForward;
    float3 _FaceRight;
    half _FaceShadowSmooth;
    half3 _ShallowFadeCor;
    half3 _SSSCor;
    half3 _ForntCor;
    half3 _ForwardCor;
    half3 _CheekCor;

    half _RimOffset;        // 边缘高光偏移
    half _RimScale;         // 强度
    half _DepthShadowScale;  // 深度阴影强度

    half _AlphaFactor;
    half _Cutoff;
    half _Surface;

    half _Factor;
CBUFFER_END

TEXTURE2D(_BaseMap);            SAMPLER(sampler_BaseMap);
float4 _BaseMap_TexelSize;      float4 _BaseMap_MipInfo;
TEXTURE2D(_MaskMap);            SAMPLER(sampler_MaskMap);
TEXTURE2D(_NormalMap);          SAMPLER(sampler_NormalMap);
TEXTURE2D(_EmissionMap);        SAMPLER(sampler_EmissionMap);
TEXTURE2D(_RampMap);            SAMPLER(sampler_RampMap);
TEXTURE2D(_MatCap);             SAMPLER(sampler_MatCap);
TEXTURE2D(_OtherMap);           SAMPLER(sampler_OtherMap);

TEXTURE2D(_CameraDepthTexture);     SAMPLER(sampler_CameraDepthTexture);


// 透明度设置
half AlphaTest(half Alpha, half4 color, half cutoff , half2 uv)
{

    half alpha = Alpha * color.a;
    
    #if defined(_ISHAIR)
        alpha *= SAMPLE_TEXTURE2D(_OtherMap, sampler_OtherMap,uv).r;
    #endif

    #if defined(_CUTOFFON)
        clip( alpha - cutoff );
    #endif  

    alpha = lerp (1,alpha,_AlphaFactor);

    return alpha;
}


//钳制最大亮度
float3 ClampColorBrightness(float3 color)
{
    float m =   max(max(max(color.r,color.g),color.b),0.001);
    color =  lerp(color, color*(1/m),saturate( sign(m-1)));
    return color;
}


// 伽马调整
float3 GammaRectify (float3 diffuse, half NdotL0, half NdotL)
{
    half step1 =  saturate( saturate(1-(NdotL0-NdotL)*3) *2);
    step1 = min(step1 * sqrt(step1), 1)* saturate((NdotL*0.5+0.5));
    step1 = lerp(step1,saturate( NdotL),0.5);
    half step2 = (diffuse.r*0.299 + diffuse.g*0.587 + diffuse.b*0.114)*0.2875+1.4375;
    step2 = lerp (step2,1,step1);
    float3 diffuse2 =  pow( ClampColorBrightness(diffuse),step2) ;
    diffuse =  lerp( diffuse , diffuse2, (saturate(NdotL0)*0.8+0.2));

    return diffuse;
}





// 叠加   A<=128 则 C=(A×B)/255 A>128 则 C=255-(A反相×B反相)/128
float3 overlay(real3 Src, real3 Dst)
{
    real3 color = 1;
    color.r = (Dst.r < 0.5) ? 2.0 * Src.r * Dst.r : 1.0 - 2.0 * (1.0 - Src.r) * (1.0 - Dst.r);
    color.g = (Dst.g < 0.5) ? 2.0 * Src.g * Dst.g : 1.0 - 2.0 * (1.0 - Src.g) * (1.0 - Dst.g);
    color.b = (Dst.b < 0.5) ? 2.0 * Src.b * Dst.b : 1.0 - 2.0 * (1.0 - Src.b) * (1.0 - Dst.b);
    return color;
}


// MatCap颜色混合
float3 MatCapBlendColor (float3 diffuse, float3 MatCap, half metallic, half HNdotL)
{
    // 金属度影响系数
    half mask = lerp(1,metallic, _ScaleOfMult);  

    MatCap = MatCap * _MatCapColor ;                  // MatCa染色
    half3 MatCapMult = MatCap * _MatCapIntensity;     // 强度

    // 叠加混合
    half3 ColorOverlay = (MatCap - 0.5) * _MatCapIntensity + MatCap;
    ColorOverlay = lerp( 0.5, ColorOverlay, mask);
    ColorOverlay = overlay(diffuse,ColorOverlay);

    half MatCapMode = round( _MatCapMode);                     // 模式
    float3 Color = MatCapMult;                            // 混合模式
    Color = lerp( MatCapMult, MatCapMult + diffuse, saturate(MatCapMode)); // 相加模式
    Color = lerp( Color, MatCapMult * diffuse, saturate(MatCapMode-1));    // 相乘模式
    Color = lerp( Color, ColorOverlay, saturate(MatCapMode-2));            // 叠加模式

    Color = lerp( diffuse , Color, mask); 

    return lerp(diffuse, Color, _MatCapScale);
}



// 眼睛视差
float2 POM(float2 uv, real3 ViewDirTS)
{
    float Layers = 10;                //层数
    half currentLayerHeight =0;       // 当前累积高度   后高度值    
    half HeightStep =1/Layers;        // 每层高度步长 

    float2 currentUV = uv ;           // 当前UV坐标
    float2 offsetUVSum = ViewDirTS.xy/-ViewDirTS.z * _EyeHeightScale;  // UV偏移总量
    float2 offsetUV = 0;              // 当前UV偏移量
    half currentHeight = 0;           // 初始高度采样

    for(int j=0; j < Layers; j++)
    {
        currentHeight =  SAMPLE_TEXTURE2D(_MaskMap, sampler_MaskMap, currentUV + offsetUV).b;     // 循环中第一次采样为初始高度值
        
        if (currentLayerHeight  > currentHeight) break;
        
        currentLayerHeight += HeightStep;
        offsetUV = offsetUVSum * currentLayerHeight;
    }
    
    half PrestepDepth = currentLayerHeight - HeightStep;
    half AC =  PrestepDepth - currentHeight;
    half DB= currentHeight - currentLayerHeight;
    half T = AC/(DB+AC);
    //插值计算出交点的深度值
    half height = lerp ( PrestepDepth , currentLayerHeight ,T);//重新计算offset
    offsetUV = offsetUVSum * height ;

    return offsetUV;  // 所有层未命中则返回最大偏移
}



// 矢量投影
float3 VectorProjection(float3 A,float3 B)
{
    float dotAB = dot(A, B);    
    float dotBB = dot(B, B);     
    return (dotAB / dotBB) * B;   
}


// 重映射函数
float Remap( float value, float from_min, float from_max, float to_min, float to_max, int curve_type = 0 )  // 0=线性, 1=其他曲线类型
{
    value = clamp(value, from_min, from_max);       // 限制输入范围
    
    float normalized = (value - from_min) / (from_max - from_min);   // 归一化到[0,1]范围
    
    if(curve_type != 0)         // 应用曲线插值
    {
        normalized = smoothstep(0.0, 1.0, normalized);
    }
    
    return to_min + normalized * (to_max - to_min); // 映射到新范围
}




// 面部颜色
float3 FaceSDF( float3 Color, float3 ViewDir , float3 lightDir ,float3 FaceRight , float3 FaceForward , float cheek ,float2 uv )
{
    float3 FaceUp = normalize(cross( FaceForward, FaceRight));   // 面部向上向量
    float3 NewFaceForward = normalize( FaceForward - normalize(ViewDir * half3(-1,0,-1))*0.5 );  // 正面朝向 + 视线方向的影响  

    float3 LLproFU = normalize( lightDir - VectorProjection( lightDir , FaceUp));     // 主光向量-主光向量在FaceUp上的投影向量

    float  FaceNL = dot(LLproFU, FaceRight);
    float2 FaceUV = float2(step(FaceNL,0.0)*(1-uv.x)+step(0.0,FaceNL)*uv.x,uv.y);
    float3 Mask    = SAMPLE_TEXTURE2D(_MaskMap, sampler_MaskMap,FaceUV);
    float SDF = Mask.g*0.5 + Mask.r*0.5;        // SDF
    float TriangleHightlight = saturate( Mask.r - step(0.35,Mask.b));       // 面部三角区 + 嘴唇高光
    
    float Atan =  atan2( FaceNL , dot( NewFaceForward * -1 , LLproFU))/PI;
    float SDFangle = saturate( 1 - abs(Atan));      // 角度阈值                   

    // 分层计算
    float A = lerp( _FaceShadowSmooth , 0.025 , saturate(TriangleHightlight*2.5) );
    float B = (SDF*1.2-0.6)/(A*4+1) +0.6 - SDFangle;
    float C = B/A;
    float D = B*8-A*16;

    float ShallowFade = saturate(1 - C);
    float SSS = min( saturate(C) , saturate(2-C));
    float Fornt =min( saturate(C-1) , saturate(1-D) );
    float Forward = saturate(D);
    
    Color *= ((ShallowFade*_ShallowFadeCor) + (SSS*_SSSCor) + (Fornt * _ForntCor)+ (Forward*_ForwardCor));

    //脸颊
    cheek = pow(cheek-0.5,3) * 8 ;
    half VdotFF = saturate( -dot(ViewDir,FaceForward));  // 视线和正面朝向的角度
    cheek = pow(VdotFF,5) * cheek ;

    Color = Color * lerp(1,_CheekCor,cheek);

    return Color ;
}






#endif // UNIVERSAL_INPUT_SURFACE_PBR_INCLUDED
