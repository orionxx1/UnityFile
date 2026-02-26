using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class RFNiuQu : ScriptableRendererFeature
{
    //自定义的PASS————————————
    class CustomRenderPass : ScriptableRenderPass
    {
        // 定义一个不可修改的字符串常量，作为性能分析标记的名称
        const string ProfilerTag = "时间结界";      
        ProfilingSampler m_ProfilerSampler = new(ProfilerTag);  // 创建高性能的性能分析采样器

        public Material m_Material;
        RTHandle _cameraColorTgt;           // 相机渲染的图像  之后会将值存入，现在只是定义
        RTHandle _tempRT;                   // 第一次处理的图片缓冲
        public TimeFieldVolume m_Volume;


        // 获取一个临时的渲染目标,动态分配或复用临时渲染目标（_tempRT），检查其格式/尺寸与当前相机目标匹配，并自动匹配
        public void GetTempRT(in RenderingData data)
        {   
            RenderingUtils.ReAllocateIfNeeded(ref _tempRT, data.cameraData.cameraTargetDescriptor);
        }

        public void SetUP(RTHandle cameraColor)
        {
            _cameraColorTgt = cameraColor;
        }

        public override void OnCameraSetup( CommandBuffer cmd, ref RenderingData renderingData)
        {
            ConfigureInput( ScriptableRenderPassInput.Color );
            ConfigureTarget( _cameraColorTgt );
        }


        // Pass 实际逻辑
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(ProfilerTag);
            Vector4 v4 = new(){
                x = m_Volume.screenPos.value.x,
                y = m_Volume.screenPos.value.y,
                z = m_Volume.intensity.value,
                w = m_Volume.scatter.value
            };
            m_Material.SetVector(CenterPosStrScatter, v4);

            using ( new ProfilingScope(cmd, m_ProfilerSampler))
            {
                CoreUtils.SetRenderTarget(cmd, _tempRT);
                Blitter.BlitTexture(cmd, _cameraColorTgt, new Vector4(1, 1, 0, 0), m_Material, 0);
                CoreUtils.SetRenderTarget(cmd, _cameraColorTgt);
                Blitter.BlitTexture(cmd, _cameraColorTgt, _cameraColorTgt, m_Material, 0);
            }
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            cmd.Dispose();
        }
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            _tempRT?.Release();
        }
    }


    //变量和配置参数————————————————————
    CustomRenderPass m_ScriptablePass;
    public RenderPassEvent m_RenderPassEvent = RenderPassEvent.AfterRenderingOpaques;
    public Material m_Material;
    TimeFieldVolume m_volume;
    static readonly int CenterPosStrScatter = Shader.PropertyToID("_CenterPos_Str_Scatter");

    //在初始化的时候调用————————————————————
    public override void Create()
    {
        if (m_Material == null) return;
        m_volume = VolumeManager.instance.stack.GetComponent<TimeFieldVolume>();
        m_ScriptablePass = new CustomRenderPass(){ m_Material = m_Material,  m_Volume = m_volume};
        m_ScriptablePass.renderPassEvent = m_RenderPassEvent;
    }

    //每帧调用,将PASS添加进流程————————————————————
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    { //添加进pass
        if (!ShouldRender(in renderingData)) return;
        renderer.EnqueuePass(m_ScriptablePass);
        m_ScriptablePass.GetTempRT(in renderingData);
    }


    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        if (!ShouldRender(in renderingData)) return;
        m_ScriptablePass.SetUP(renderer.cameraColorTargetHandle);  // 当前渲染图传给_cameraColorTgt
    }


    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        #if UNITY_EDITOR
                //如有需要,在此处销毁生成的资源,如Material等
                if (EditorApplication.isPlaying)
                {
                    // Destroy(null_Material);
                }
                else
                {
                    // DestroyImmediate(null_Material);
                }
        #else
                   //   Destroy(material);
        #endif
    }

    // 检查当前是否执行
    bool ShouldRender(in RenderingData data)
    {
        if (!data.cameraData.postProcessEnabled || data.cameraData.cameraType != CameraType.Game)
        {
            return false;
        }
        if (m_ScriptablePass == null)
        {
            Debug.LogError("RenderPass = null!");
            return false;
        }
        return true;
    }
}