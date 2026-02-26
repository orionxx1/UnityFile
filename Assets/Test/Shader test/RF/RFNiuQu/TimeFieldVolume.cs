using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering;


[VolumeComponentMenu("RF测试扭曲")]
public class TimeFieldVolume : VolumeComponent, IPostProcessComponent
{
    public Vector2Parameter screenPos = new(new(0.5f, 0.5f));    // 屏幕中心位置
    public MinFloatParameter intensity = new(10, 0);             // 
    public ClampedFloatParameter scatter = new(0, 0, 1.5f);


    public bool IsActive()
    {
        return true;
    }
    public bool IsTileCompatible()
    {
        return false;
    }
}