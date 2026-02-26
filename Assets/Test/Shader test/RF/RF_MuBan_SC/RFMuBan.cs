using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class RF_MuBan : ScriptableRendererFeature
{
    private RF_MuBan_Pass m_RFMuBanPass;
    public Material Material;
    public RenderPassEvent m_RenderPassEvent = RenderPassEvent.AfterRenderingTransparents;

    public override void Create(){
        if ( Material == null){    
            Debug.LogWarning("RFMuBan: 材质未分配");
        }

        // 配置Pass的渲染事件点
        m_RFMuBanPass = new RF_MuBan_Pass(Material);
        m_RFMuBanPass.renderPassEvent = m_RenderPassEvent;
    }


    // 每帧调用,将PASS添加进流程 ————————
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData){
        if (!ShouldRender(renderingData))  return;
        renderer.EnqueuePass(m_RFMuBanPass);

    }


    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData){
        if (!ShouldRender(in renderingData)) return;
    }


    // 检查是否应该执行此Feature的条件
    private bool ShouldRender(in RenderingData renderingData){     
        if ( Material == null){
            return false;
        }

        //if (renderingData.cameraData.cameraType != CameraType.Game || !renderingData.cameraData.postProcessEnabled){
        if (!renderingData.cameraData.postProcessEnabled){
           return false;
        }

        return true;
    }


    // 清理Pass创建的资源（如果Pass内部没有完全管理的话）   
    protected override void Dispose(bool disposing){
        base.Dispose(disposing);
        m_RFMuBanPass?.Dispose();
        m_RFMuBanPass = null;
    }   
}


// Pass 类定义 ————————————————————
public class RF_MuBan_Pass : ScriptableRenderPass
{
    // 创建分析器 
    private const string PROFILER_TAG = "RFMuBan_Pass";
    private ProfilingSampler m_ProfilingSampler = new ProfilingSampler(PROFILER_TAG);

    public Material m_Material;              // 材质
    private RTHandle m_CameraColorRT;        // 源和最终目标
    private RTHandle m_TempRT;               // 临时RT
    private RenderTextureDescriptor rtdesc;
    private RF_MuBan_Volume volume;          // 体积

    private float _ExampleFloat;
    private Color _ExampleColor;
    private int _ExampleFloatID;
    private int _ExampleColorID;


    public RF_MuBan_Pass(Material material){
        m_Material = material;
        _ExampleFloatID = Shader.PropertyToID("_ExampleFloat");
        _ExampleColorID = Shader.PropertyToID("_ExampleColor");
    }


    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData){
        volume = VolumeManager.instance.stack.GetComponent<RF_MuBan_Volume>();
        if (volume == null || !volume.IsActive())
            return;

        _ExampleFloat = volume.FloatParameter.value;
        _ExampleColor = volume.ColorParameter.value;
        m_Material.SetFloat(_ExampleFloatID, _ExampleFloat);
        m_Material.SetColor(_ExampleColorID, _ExampleColor);

        // 告诉 URP 需要颜色、深度图
        ConfigureInput(ScriptableRenderPassInput.Color | ScriptableRenderPassInput.Depth);

        rtdesc = renderingData.cameraData.cameraTargetDescriptor;
        rtdesc.depthBufferBits = 0;           // 无深度
        rtdesc.msaaSamples = 1;               // 禁用MSAA

        // 获取一个临时的渲染目标,动态分配或复用临时渲染目标（_tempRT），检查其格式/尺寸与当前相机目标匹配，并自动匹配
        RenderingUtils.ReAllocateIfNeeded(ref m_TempRT, rtdesc, name: "_RFMuBan_TempRT");
    }


    // 具体执行操作 ————————
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData){
        if (!volume.IsActive()) return;

        m_CameraColorRT = renderingData.cameraData.renderer.cameraColorTargetHandle;
        CommandBuffer cmd = CommandBufferPool.Get(PROFILER_TAG);

        if (m_Material == null){   
            Debug.LogError("RFMuBan: Pass 执行时材质未分配!");
            CommandBufferPool.Release(cmd); // 返回前释放
            return;
        }
        
        if (m_CameraColorRT == null || m_TempRT == null){   
            Debug.LogError("RFMuBan: Pass 执行时 RTHandles 未正确设置!");
            CommandBufferPool.Release(cmd); // 返回前释放
            return;
        }

        using (new ProfilingScope(cmd, m_ProfilingSampler)){
            Blitter.BlitCameraTexture(cmd, m_CameraColorRT, m_TempRT, m_Material, 0);
            Blitter.BlitCameraTexture(cmd, m_TempRT, m_CameraColorRT);
        }

        context.ExecuteCommandBuffer(cmd);
        cmd.Clear();
        CommandBufferPool.Release(cmd);
    }


    public override void OnCameraCleanup(CommandBuffer cmd){
        m_CameraColorRT = null;
    }


    public void Dispose(){
        m_TempRT?.Release();
        m_TempRT = null;
    }
}




// 体积 类定义 ————————————————————
public class RF_MuBan_Volume : VolumeComponent, IPostProcessComponent
{
    public BoolParameter IsEnabled = new BoolParameter(true);
    
    public FloatParameter FloatParameter = new ClampedFloatParameter(1f, 0f, 2f);
    public IntParameter IntParameter = new ClampedIntParameter(1, 1, 8);
    public ColorParameter ColorParameter = new ColorParameter(Color.white);

    public bool IsActive(){
        return active && IsEnabled.value;
    }

    public bool IsTileCompatible(){
        return false;
    }
}