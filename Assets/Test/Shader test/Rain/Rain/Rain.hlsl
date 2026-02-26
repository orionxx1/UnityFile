#ifndef UNIVERSAL_RainOnWall_INCLUDED
#define UNIVERSAL_RainOnWall_INCLUDED

#include "Assets/ORIONXXRenderer/Shaders/HLSLInclude/NoiseLib.hlsl"

float snap1D(float value, float increment)
{
    if (increment == 0.0)
    return value;
    
    return floor(value / increment ) * increment;
}


float ValueRamp(float x ,float a, float b)
{
    return saturate((x-a)/(b-a));
}


// 小雨滴的形状 和 生命周期
half4 SplatsEngineF( half2 uv ,half2 Noise ,half time , half FXSize , half SplatsNoise, half offest)
{
    uv -= Noise.rg * SplatsNoise ;
    uv.x = uv.x - 0;    // x Off
    uv.y = uv.y - 0;    // y Off.

    half step1 = snap1D(uv.y, FXSize );    
    half step2 = saturate(uv.y - step1);  
    half step3 = uv.x + step1 * 0.5 ; 
    half step4 = snap1D(step3 , FXSize); 
    half step5 = saturate(step3 - step4); 

    half2 NewUV = half2(step4 ,step1);
    half ID = VoronoiID( NewUV*100,1).r;
    half life = time + ID*20.1 ;

    half step6 = (life - frac(life))*0.001 + step4; 
    half2 NewUV2 = half2(step6 ,step1);

    half2 ID2 = VoronoiID( NewUV2*100,1).rg;
    half outID  = ID2.x;                                 // 输出ID
    ID2 = ID2 * 2 - 1;
    ID2 = ID2 * FXSize * offest;
    half Radius = sqrt(ID2.x*ID2 +ID2.y*ID2.y);          // 偏移量  

    half step7 = step5 - ID2.x - FXSize*0.5; 
    half step8 = step2 - ID2.y - FXSize*0.5; 
    half step9 = (step7*step7 + step8*step8);
    step9 = sqrt(step9);
    half step10 =  saturate(0.5-step9/FXSize)*2;
    step10 = saturate(step10 - Radius/FXSize*2)/(1- (Radius/FXSize*2)) ;

    return half4(step10, frac(life), outID ,Radius);
}   


half2 SplatsMaskF( half3 CellData, half Intensity, half Scale)
{
    half2 Mask = 0;
    half Cell = CellData.r * (step(CellData.b, Intensity));
    half life = sqrt(1-CellData.g);
    
    half step1 = saturate(1-life + Scale*0.5);    
    half step2 = saturate(1-life + Scale);  
    half step3 = saturate( (Cell-step1)/(1-step1) * life );
    half step4 = saturate( (Cell-step2)/(1-step2) );
    life = saturate(life-0.5) * saturate(life-0.5);
    step4 = saturate( sin(sqrt(step4) * 1.5708) * life );

    Mask.r = step3 + step4*10;  //粗糙度
    Mask.g = step4;          //高度

    return Mask;
}


// 水波纹
half RippleMaskF( half4 CellData, half Intensity, half Size, half RingFrequency)
{
    half Cell = CellData.r * (step(CellData.b, Intensity));
    half CellID = CellData.b*2 + 0.5;
    half life = CellData.g;
    half Radius = CellData.w;
    // RingFrequency  频率

    half step1 = (Radius*2)/Size;
    half step2 = (Cell-step1)/saturate(1-step1);
    half step3 = saturate( (step2+life-1) );
    half step4 = saturate(0.5-step3/life)*2*(1-life);
    half step5 = sin(step3 * RingFrequency * CellID) * step4*step4*step4;

    return step5;
}

// 雨滴滑落
void DropletEngineF( out half DropletID, out half2 DropletUV, out half2 DropletSizeData, out half DropletLife ,
                     half2 uv, half Size,half time, half MaxLength, half MinLength )
{
    DropletID = hash11(snap1D(uv.r, Size*0.5));
    DropletID = DropletID*16 + time*3;
    half2 DropletIDColor = hash1to2( snap1D(DropletID,1)*0.01);
    half step1 = lerp(MaxLength, MinLength, DropletIDColor.g);
    DropletUV = half2( frac(uv.x/Size*2) ,  frac( (uv.y+DropletIDColor.r)/step1 )   );
    DropletSizeData =half2( Size*0.5 , Size*0.5/step1);
    half step2 = snap1D(uv.x, Size*0.5);
    half step3 = snap1D(uv.y + DropletIDColor.r,step1);
    DropletLife = frac( DropletID);
    DropletID = hash2to1( half2 (step2,step3));
}



half3 DropletMaskF( half Noise , half2 uv, half2 SizeData, half ID , 
                    half Life, half DropletsIntensity, half DropletsNoise )
{
    half3 Mask = 0;
    Noise = Noise * DropletsNoise;
    half Intensity = step(ID,DropletsIntensity);

    half MaskX = (uv.x - Noise)-0.5;
    MaskX = MaskX*MaskX;
    half step1 = 1-Life*Life;
    half step2 = step1*(1-SizeData.g) + SizeData.g*0.5;
    half step3 = ValueRamp( uv.y, step2, 1) + ValueRamp( uv.y, step1*(1-SizeData.g), step2);
    step3 = (step3*0.5-0.5);
    half step4 = sqrt( MaskX + (step3 * step3) );
    half step5 = uv.g*0.2;
    Mask.r= saturate( step(step4, step5) );

    half step6 =  sin((saturate(step5-step4)/step5) * 1.5708) ;
    Mask.g = saturate( step6 *  step5 * SizeData.x * step1 );               // 高度

    half step7 = (1-SizeData.g) * step1 ;
    half step8 = ValueRamp( uv.y, step7, step2) + ValueRamp( uv.y, 1-SizeData.g*0.5, 1);
    step8 = (step8*0.5-0.5);
    step8 = step8* step8;
    half step9 = uv.x -Noise -0.5;
    step9 = step9*step9;
    step9 = sqrt( step8+step9);
    half step10 = (lerp(2,0.5,Life*Life) - uv.y)*lerp(0.1,0.22,uv.y);
    Mask.b = saturate( (step10-step9)*10 );

    Mask = Mask *Intensity;

    return Mask;
} 

float2 RainParallax (float2 uv, half HeightMask, half WaterDepth, half Noise, half RippleMask, float3 ViewDir)
{
    half2 uvOffest = HeightMask*(RippleMask + Noise);
    uv = uv - uvOffest;
    
    half Depth = HeightMask* WaterDepth *-1;
    uvOffest.x = uvOffest.x-(Depth/ViewDir.y)*ViewDir.x;
    uvOffest.y = uvOffest.y-(Depth/ViewDir.y)*ViewDir.z;
    
    uv = uv- uvOffest;

    return uv;
}




float3 height2BumpWS(
    float3 worldPos,     //世界位置
    float3 normal,       // 原始法线
    float height,        // 高度
    float strength,      // 强度
    float distance,      // 距离 这将缩放ddx/ddy(高度)的效果
    float filterWidth,   // 过滤宽度
    float invert_sign )  // 反转符号
{
    float dist_eff = distance * invert_sign;

    // 计算世界位置的屏幕空间导数
    float3 dPdx = ddx(worldPos);
    float3 dPdy = ddy(worldPos);

    // 从法线获取曲面切线
    float3 Rx = normalize( cross(dPdy, normal) );
    float3 Ry = normalize( cross(normal, dPdx) );
    float det = dot(dPdx, Rx);

    // 计算程序高度值的屏幕空间导数
    float dh_dscreen_x = ddx(height); // X轴上每个屏幕像素的高度变化
    float dh_dscreen_y = ddy(height); 

    // 这个dh_dscreen_x是在屏幕x上移动一个像素时的高度变化
    // height _ xy’是沿着dPdx/dPdy投影在一个“屏幕像素步长”处取得的样本
    float2 dHd;
    dHd.x = dh_dscreen_x;
    dHd.y = dh_dscreen_y;

    float3 surfgrad = dHd.x * Rx + dHd.y * Ry;
    strength = max(strength, 0.0f);

    float3 perturbed_N_intermediate = (filterWidth * abs(det) * normal - dist_eff * sign(det) * surfgrad);
    perturbed_N_intermediate = normalize(perturbed_N_intermediate);

    float3 final_N = normalize(lerp(normal, perturbed_N_intermediate, saturate(strength)));

    return final_N;
}






#endif 