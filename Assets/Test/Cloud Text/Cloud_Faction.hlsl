#ifndef UNIVERSAL_CLOUD_FACTION
#define UNIVERSAL_CLOUD_FACTION

// 重映射  完整
float remap(float v, float minOld, float maxOld, float minNew, float maxNew) 
{
    return minNew + (v-minOld) * (maxNew - minNew) / (maxOld-minOld);
}

// 重映射  开端
float remapOld(float v, float low, float high) 
{
    return (v-low)/(high-low);
}

// 重映射  尾端
float remapNew(float v, float low, float high) 
{
    return v * (high-low) + low ;
}



// 屏幕uv变换
float2 SquareUV(float2 uv) 
{
    float x = uv.x * _ScreenParams .x;
    float y = uv.y * _ScreenParams.y;
    return float2 ( x, y)/1000;
}



// 射线与AABB求交函数 (slab method)
half2 RayBoxDst(float3 rayOrigin, float3 rayDir, float3 boundsMin, float3 boundsMax )
{
    half3 t0 = (boundsMin - rayOrigin) / rayDir;
    half3 t1 = (boundsMax - rayOrigin) / rayDir;
    half3 tmin = min(t0, t1);
    half3 tmax = max(t0, t1);
    
    half dstA = max(max(tmin.x, tmin.y), tmin.z);
    half dstB = min(tmax.x, min(tmax.y, tmax.z));
    
    half dstToBox = max(0, dstA);
    half dstInsideBox = max(0, dstB - dstToBox);
    return half2(dstToBox, dstInsideBox);
}





//  亨利·格林斯坦相位函数，也就是HG相位函数 
half HgPhaseFunction(half cos_angle, half eccentricity)
{
    // cos_angle 是入射光和视角方向的夹角
    // eccentricity 是描述体积云/雾的性质的常量参数
    // 为0时,云向四面八方进行散射，所有方向散射结果一致，呈现各向同性
    half g2 = eccentricity * eccentricity;
    return (1 - g2)/( pow(1 + g2 - 2 * eccentricity * cos_angle, 1.5) * 12.56637 );
    // 4 * Pi = 12.56637
}

// 施利克相位函数，对亨利·格林斯坦函数做近似 
half SchlickPhaseFunction(half a, half g)
{
    half k = 1.55 *g - 0.55 * g * g * g;
    return (1.0 - k * k) / (12.56637 * pow(1 - k * a, 2));
}

// 两次HG做的光轴偏移，这个计算不物理，但效果比较好，且美术可控
float GetDirectScatterProbability(float cos_angle, float eccentricity)
{   
    half u_SilverIntensity = 0.5;
    half u_SilverSpread = 0.5;
    return max( HgPhaseFunction(cos_angle, eccentricity), u_SilverIntensity * HgPhaseFunction(cos_angle, 0.99 - u_SilverSpread));
}






// Beer定律
float BeerLambert(float sampleDensity, float precipitation)
{
    return exp(sampleDensity * precipitation);
}

// SIG 2015中的“糖粉效果”
float PowderEffect(float sampleDensity, float cos_angle)
{
    float powd = 1.0 - exp(-sampleDensity * 2.0);
    return lerp(1.0, powd, saturate((-cos_angle * 0.5) + 0.5)); // [-1,1]->[0,1]
}

// Beer's Powder函数
half3 BeerPowder(half3 d, half a)
{
    return exp(-d * a) * (1 - exp(-d* 2 * a));
}







// 密度计算
half SampleDensity(half3 RayPos, half3 boundsMin, half3 boundsMax ) 
{
     half3 boundSize = boundsMax-boundsMin;
     half ShapeTime  = _Time.x * _ShapeNoise_Time;
     half DetailTime = _Time.x * _DetailNoise_Time;

     // 体积云边缘过度 ————
     half edgeToX = min(_BoxEdgeSoft.x, min(RayPos.x - boundsMin.x, boundsMax.x - RayPos.x));
     half edgeToZ = min(_BoxEdgeSoft.x, min(RayPos.z - boundsMin.z, boundsMax.z - RayPos.z));
     half edgeToY = min(_BoxEdgeSoft.y, min(RayPos.y - boundsMin.y, boundsMax.y - RayPos.y));
     half edgeWeight = edgeToX/ _BoxEdgeSoft.x * edgeToZ / _BoxEdgeSoft.x * edgeToY / _BoxEdgeSoft.y;
     edgeWeight *= edgeWeight;

     // 采样天气图(云分布图) ————
     half3 WeatherUVW = (RayPos - boundsMin) / abs( boundsMax - boundsMin) ;
     half3 WeatherTyp = SAMPLE_TEXTURE2D(_Cloud_WeatherMap, sampler_LinearClamp, WeatherUVW.xz);  
     half  Weather = lerp(WeatherTyp.r, WeatherTyp.g, saturate(_WeatherFactor) );
     Weather = lerp(Weather, WeatherTyp.b, saturate(_WeatherFactor-1) );

     // 从云类型图计算高度梯度 ————
     half  heightPercent = (RayPos.y - boundsMin.y) / boundSize.y;
     half2 HeightUV = half2(0.5,heightPercent);
     half3 HeightTyp = SAMPLE_TEXTURE2D(_Cloud_TepMap, sampler_LinearClamp, HeightUV);
     half  Height = lerp(HeightTyp.r, HeightTyp.g, saturate(_CloudFactor) );
     Height = lerp(Height, HeightTyp.b, saturate(_CloudFactor-1) );

     half density =  saturate( edgeWeight * Weather * Height );

     // 云基础形状雕刻 ————
     half3 ShapeNoiseUVW = RayPos * 0.1/_ShapeNoise_Scale.xyz + _ShapeNoise_Offset.xyz * ShapeTime;
     half3 ShapeNoise = tex3D(_ShapeNoise_Tex, ShapeNoiseUVW);
     half3 _shapeNoiseWeights = half3(0.5, 0.25, 0.125);
     half3 normalizedShapeWeights = _shapeNoiseWeights / dot( _shapeNoiseWeights, 1);
     half  ShapeFBM = dot(ShapeNoise, normalizedShapeWeights) ;
     half  baseShapeDensity = saturate( ShapeFBM + _ShapeNoiseDensityOffset ) ;

     density = density * baseShapeDensity * _ShapeNoise_Density ;
     
     if (density>0.001) 
     { 
        half3 DetailNoiseUVW = RayPos * 0.1/_DetailNoise_Scale.xyz + _DetailNoise_Offset.xyz * DetailTime;
        half  DetailNoise = tex3D(_DetailNoise_Tex, DetailNoiseUVW).r;
        DetailNoise = pow(DetailNoise, _DetailNoise_Weight);

        half DetailWeight = saturate(1- density);
        DetailWeight = DetailWeight * DetailWeight * DetailWeight;
        density = density - saturate(DetailNoise * DetailWeight) * _DetailNoise_Density ;
        density = saturate(density);
     }
     return density * _DensityMult ;   
}







// 估算当前点到云层表面的距离 (近似SDF)
half GetCloudDistance(float3 pos, float3 boundsMin, float3 boundsMax)
{
    half density = SampleDensity(pos, boundsMin, boundsMax);
    // 简单地通过采样一次密度来判断是否在云内
    // 这是一个经验公式，用于将密度转化为一个“距离” 参考《地平线》中 GetVoxelCloudDistance
    // 当密度很低时，返回一个较大的正数，> 0: 在云外，数值表示到云表面的大概距离
    // 当密度很高时，返回一个负数，<=0: 在云内
    // CloudSurfaceThickness 是一个可调节的系数，可以控制“表面”的厚度

    half CloudSurfaceThickness = 2;
    return (0.1 - density) * CloudSurfaceThickness;
}



// 光照计算
half LightPathDensity(float3 PositionWS, int stepCount, float3 boundsMin, float3 boundsMax )
{
    half3 dirToLight = _MainLightPosition.xyz;
    half dstInsideBox = RayBoxDst(PositionWS, dirToLight*10 , boundsMin, boundsMax ).y;
                         
    half stepSize = dstInsideBox / stepCount;
    half totalDensity = 0;
    half3 stepVec = dirToLight * stepSize;

    for(int step = 0; step < stepCount; step ++)
    {
        PositionWS += stepVec;
        totalDensity += max(0, SampleDensity( PositionWS , boundsMin ,boundsMax ) * stepSize);
    }


    half transmittance = exp( -totalDensity * _LightAbsorptionTowardSun );
    transmittance = _DarknessThreshold + transmittance * ( 1 - _DarknessThreshold);

    return transmittance;
}


#endif 


