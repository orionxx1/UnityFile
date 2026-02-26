using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;


// 悶持 窃協吶 ！！！！！！！！！！！！！！！！！！！！
public class RF_VolumeLight_Volume : VolumeComponent, IPostProcessComponent
{
    public BoolParameter IsEnabled = new BoolParameter(false);

    public FloatParameter Intensity = new ClampedFloatParameter(1f, 0f, 2f);
    public IntParameter StepTime = new ClampedIntParameter(8, 1, 24);
    public FloatParameter StepSize = new ClampedFloatParameter(0, 0, 1);
    public FloatParameter BlurOffset = new ClampedFloatParameter(1, 0, 10);
    public ColorParameter VolumeColor = new ColorParameter(Color.white);

    public bool IsActive()
    {
        return active && IsEnabled.value;
    }

    public bool IsTileCompatible()
    {
        return false;
    }
}