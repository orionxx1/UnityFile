#ifndef UNIVERSAL_PARALLAX_INCLUDED
#define UNIVERSAL_PARALLAX_INCLUDED



//视差映射
float2 ParallaxMapping(float2 uv, real3 ViewDirTS ,float height ,float HeightScale)
{
    float2 offsetUV = ViewDirTS.xy / -ViewDirTS.z * height * HeightScale;
    return offsetUV;
}



//陡峭视差映射
float2 SteepParallaxMapping(float2 uv, real3 ViewDirTS , float HeightScale)
{
    float Layers = 20;                //层数
    half currentLayerHeight =0;       // 当前累积高度   后高度值    
    half HeightStep =1/Layers;        // 每层高度步长 

    float2 currentUV = uv ;           // 当前UV坐标
    float2 offsetUVSum = ViewDirTS.xy/-ViewDirTS.z * HeightScale;  // UV偏移总量
    float2 offsetUV = 0;              // 当前UV偏移量
    half currentHeight = 0;           // 初始高度采样

    for(int j=0; j < Layers; j++)
    {
        //对uv进行偏移，并且采样深度图 
        currentHeight =  1 - SAMPLE_TEXTURE2D(_MaskMap, sampler_MaskMap, currentUV + offsetUV).b;     // 循环中第一次采样为初始高度值
        
        //如果当前采样的高度值 > 迭代累计的高度值，则退出循环    
        if (currentLayerHeight  > currentHeight) break;
        
        currentLayerHeight += HeightStep;
        offsetUV = offsetUVSum * currentLayerHeight;
    }
    return offsetUV;  // 所有层未命中则返回最大偏移
}



//浮雕贴图
float2 ReliefMapping(float2 uv, real3 ViewDirTS , float HeightScale)
{
    float Layers = 20;                //层数
    half currentLayerHeight =0;       // 当前累积高度   后高度值    
    half HeightStep =1/Layers;        // 每层高度步长 

    float2 currentUV = uv ;           // 当前UV坐标
    float2 offsetUVSum = ViewDirTS.xy/-ViewDirTS.z * HeightScale;  // UV偏移总量
    float2 offsetUV = 0;              // 当前UV偏移量
    half currentHeight = 0;           // 初始高度采样

    for(int j=0; j < Layers; j++)
    {
        //对uv进行偏移，并且采样深度图 
        currentHeight =  1 - SAMPLE_TEXTURE2D(_MaskMap, sampler_MaskMap, currentUV + offsetUV).b;     // 循环中第一次采样为初始高度值
        
        //如果当前采样的高度值 > 迭代累计的高度值，则退出循环    
        if (currentLayerHeight  > currentHeight) break;
        
        currentLayerHeight += HeightStep;
        offsetUV = offsetUVSum * currentLayerHeight;
    }
    
    //———— 前面和陡峭视差映射一样

    for(int j=0; j < 3; j++)
    {
        //二分查找所以把step除以二
        HeightStep/=2;

        //如果当前迭代的深度值大于或者小于深度图;都进行二分查找if(currentDepth >parallaxDpeth)
        if(currentLayerHeight > currentHeight)
        {
            currentLayerHeight -= HeightStep;    //加上一半对应step的值 
        }
        else
        {
            currentLayerHeight += HeightStep;     //减去一半对应step的值
        }

        offsetUV = currentLayerHeight * offsetUVSum;  //计算偏移值
        currentHeight = SAMPLE_TEXTURE2D(_MaskMap, sampler_MaskMap, currentUV + offsetUV).b;  
    
    }
    return offsetUV;
}




// 视差遮蔽映射  Parallax Occlusion Mapping, POM
float2 POM(float2 uv, real3 ViewDirTS , float HeightScale)
{
    float Layers = 20;                //层数
    half currentLayerHeight =0;       // 当前累积高度   后高度值    
    half HeightStep =1/Layers;        // 每层高度步长 

    float2 currentUV = uv ;           // 当前UV坐标
    float2 offsetUVSum = ViewDirTS.xy/-ViewDirTS.z * HeightScale;  // UV偏移总量
    float2 offsetUV = 0;              // 当前UV偏移量
    half currentHeight = 0;           // 初始高度采样

    for(int j=0; j < Layers; j++)
    {
        //对uv进行偏移，并且采样深度图 
        currentHeight =  1 - SAMPLE_TEXTURE2D(_MaskMap, sampler_MaskMap, currentUV + offsetUV).b;     // 循环中第一次采样为初始高度值
        
        //如果当前采样的高度值 > 迭代累计的高度值，则退出循环    
        if (currentLayerHeight  > currentHeight) break;
        
        currentLayerHeight += HeightStep;
        offsetUV = offsetUVSum * currentLayerHeight;
    }
    
    //t = A-C/(D-B)+(A-C)
    //上一次step的深度 -对应的深度图采样
    half PrestepDepth = currentLayerHeight - HeightStep;
    half AC =  PrestepDepth - currentHeight;
    //此次step对应的采样深度图值-此次step的深度
    half DB= currentHeight - currentLayerHeight;
    half T = AC/(DB+AC);
    //插值计算出交点的深度值
    half height = lerp ( PrestepDepth , currentLayerHeight ,T);//重新计算offset
    offsetUV = offsetUVSum * height ;

    return offsetUV;  // 所有层未命中则返回最大偏移
}

#endif // UNIVERSAL_PARALLAX_MAPPING_INCLUDED
