#ifndef HASH_LIB
#define HASH_LIB

// Hash库

// 伪随机数生成（基于哈希的随机偏移）
float2 Random2(float2 p) 
{
    float D1 = dot(p, float2(127.1, 311.7));
    float D2 = dot(p, float2(269.5, 183.3));
    return frac( sin(float2(D1,D2)) * 43758.5453 );
}


float Random1DTo1D(float value,float a,float b)
{
	//make value more random by making it bigger
	float random = frac(sin(value+b)*a);
        return random;
}

float Random2DTo1D(float2 value,float a ,float2 b)
{			
	//avaoid artifacts
	float2 smallValue = sin(value);
	//get scalar value from 2d vector	
	float  random = dot(smallValue,b);
	random = frac(sin(random) * a);
	return random;
}


float2 Random2DTo2D(float2 value)
{
	return float2(
		Random2DTo1D(value,14375.5964, float2(15.637, 76.243)),
		Random2DTo1D(value,14684.6034,float2(45.366, 23.168))
	);
}

float hash11(float p)
{
    p = frac(p * .1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

float hash2to1(float2 p)
{
    float3 p3  = frac(float3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

float hash3to1(float3 p3)
{
    p3  = frac(p3 * .1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return frac((p3.x + p3.y) * p3.z);
}

float2 hash1to2(float p)
{
    float3 p3 = frac(float3(p,p,p) * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx+p3.yz)*p3.zy);
}

float2 hash22(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx+33.33);
    return frac((p3.xx+p3.yz)*p3.zy);
}

float2 hash2d2(float2 uv)
{
    const float2 k = float2( 0.3183099, 0.3678794 );
    uv = uv * k + k.yx;
    return -1.0 + 2.0 * frac( 16.0 * k * frac( uv.x * uv.y*(uv.x+uv.y)));
}

float2 hash3to2(float3 p3)
{
    p3 = frac(p3 * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx+p3.yz)*p3.zy);
}

float3 hash1to3(float p)
{
    float3 p3 = frac(float3(p,p,p) * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx+33.33);
    return frac((p3.xxy+p3.yzz)*p3.zyx); 
}

float3 hash2to3(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yxz+33.33);
    return frac((p3.xxy+p3.yzz)*p3.zyx);
}

float3 hash33(float3 p3)
{
    p3 = frac(p3 * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yxz+33.33);
    return frac((p3.xxy + p3.yxx)*p3.zyx);
}

float4 hash1to4(float p)
{
    float4 p4 = frac(float4(p,p,p,p) * float4(.1031, .1030, .0973, .1099));
    p4 += dot(p4, p4.wzxy+33.33);
    return frac((p4.xxyz+p4.yzzw)*p4.zywx);
}

float4 hash2to4(float2 p)
{
    float4 p4 = frac(float4(p.xyxy) * float4(.1031, .1030, .0973, .1099));
    p4 += dot(p4, p4.wzxy+33.33);
    return frac((p4.xxyz+p4.yzzw)*p4.zywx);
}

float4 hash3to4(float3 p)
{
    float4 p4 = frac(float4(p.xyzx)  * float4(.1031, .1030, .0973, .1099));
    p4 += dot(p4, p4.wzxy+33.33);
    return frac((p4.xxyz+p4.yzzw)*p4.zywx);
}

float4 hash44(float4 p4)
{
    p4 = frac(p4  * float4(.1031, .1030, .0973, .1099));
    p4 += dot(p4, p4.wzxy+33.33);
    return frac((p4.xxyz+p4.yzzw)*p4.zywx);
}


// HSV转RGB（可直接使用）
float3 hsv2rgb(float3 hsv) 
{
    float4 k = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(frac(hsv.x + k.xyz) * 6.0 - k.www);
    return hsv.z * lerp(k.xxx, saturate(p - k.xxx), hsv.y);
}


#endif