using UnityEngine;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering;


// 悶持 窃協吶 ！！！！！！！！！！！！！！！！！！！！
public class RF_CloudText_Volume : VolumeComponent, IPostProcessComponent
{
    public BoolParameter IsEnabled = new BoolParameter(true);

    public FloatParameter FloatParameter = new ClampedFloatParameter(1f, 0f, 2f);
    public IntParameter IntParameter = new ClampedIntParameter(1, 1, 8);
    public ColorParameter ColorParameter = new ColorParameter(Color.white);

    public bool IsActive()
    {
        return active && IsEnabled.value;
    }

    public bool IsTileCompatible()
    {
        return false;
    }
}