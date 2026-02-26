using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class RF_CloudText : ScriptableRendererFeature
{
    private RF_CloudText_Pass RF_CloudText_Pass;
    public Material Material;
    public RenderPassEvent m_RenderPassEvent = RenderPassEvent.AfterRenderingTransparents;

    public override void Create(){
        if ( Material == null){
            Debug.LogError("RFMuBan: 材质未分配");
            return;
        }

        // 配置Pass的渲染事件点
        RF_CloudText_Pass = new RF_CloudText_Pass(Material);
        RF_CloudText_Pass.renderPassEvent = m_RenderPassEvent;
    }

    // 每帧调用,将PASS添加进流程 ————————
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData){
        if (!ShouldRender(renderingData))  return;
        renderer.EnqueuePass(RF_CloudText_Pass);
    }


    // 检查是否应该执行此Feature的条件
    private bool ShouldRender(in RenderingData renderingData){     
        if ( Material == null){
            return false;
        }
        return true;
    }

    // 清理Pass创建的资源（如果Pass内部没有完全管理的话）   
    protected override void Dispose(bool disposing){
        base.Dispose(disposing);
        RF_CloudText_Pass?.Dispose();
        RF_CloudText_Pass = null;
    }   
}

// Pass 类定义 ————————————————————
public class RF_CloudText_Pass : ScriptableRenderPass
{
    // 创建分析器 
    private const string PROFILER_TAG = "RF_CloudText_Pass";
    private ProfilingSampler m_ProfilingSampler = new ProfilingSampler(PROFILER_TAG);

    public Material m_Material;               // 材质
    private RTHandle m_CameraColorRT;         // 源和最终目标
    private RTHandle m_TempRT;                // 临时RT
    private RTHandle m_TempRT2;               // 临时RT
    private RTHandle m_TempRT3;               // 临时RT
    private RenderTextureDescriptor rtdesc;
    private RF_CloudText_Volume volume;          // 体积

    // 用于在Shader中引用体积光纹理的ID
    private static readonly int _CloudTexID = Shader.PropertyToID("_CloudTexTex");

    // 单个包围盒数据
    private Vector4 _activeBoxMinPoint;
    private Vector4 _activeBoxMaxPoint;
    private bool _isBoxActiveAndVisibleThisFrame; // 标记包围盒是否在本帧激活且可见

    // Shader中引用的包围盒属性ID (不再是Array)
    private static readonly int _VolumeBoxMinID      = Shader.PropertyToID("_VolumeBoxMin");
    private static readonly int _VolumeBoxMaxID      = Shader.PropertyToID("_VolumeBoxMax");
    private static readonly int _IsVolumeBoxActiveID = Shader.PropertyToID("_IsVolumeBoxActive"); // float: 0.0 or 1.0


    public RF_CloudText_Pass(Material material){
        m_Material = material;
        if (m_Material == null){
            Debug.LogError("RF_CloudText_Pass: 构造时传入的材质为 null!");
            return;
        }
    }



    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData){
        volume = VolumeManager.instance.stack.GetComponent<RF_CloudText_Volume>();
        if (volume == null || !volume.IsActive()){
            Debug.LogError("RF_CloudText_Pass: OnCameraSetup 执行时材质或体积有错误");
            return;
        }

        // 准备单个包围盒数据
        _isBoxActiveAndVisibleThisFrame = false;
        RF_CloudTex_BoxAABB currentBox = RF_CloudTex_BoxAABB.ActiveBoxInstance;
        if (currentBox != null && currentBox.enabled && currentBox.gameObject.activeInHierarchy)
        {
            Camera camera = renderingData.cameraData.camera;
            Plane[] frustumPlanes = GeometryUtility.CalculateFrustumPlanes(camera);

            if (GeometryUtility.TestPlanesAABB(frustumPlanes, currentBox.WorldBounds))
            {
                _activeBoxMinPoint = currentBox.WorldBounds.min; // Bounds.min 是 Vector3，隐式转换为 Vector4 (w=0)
                _activeBoxMaxPoint = currentBox.WorldBounds.max;
                _isBoxActiveAndVisibleThisFrame = true;
            }
        }

        ConfigureInput(ScriptableRenderPassInput.Color | ScriptableRenderPassInput.Depth);

        rtdesc = renderingData.cameraData.cameraTargetDescriptor;
        rtdesc.depthBufferBits = 0;           // 无深度
        rtdesc.msaaSamples = 1;               // 禁用MSAA
       
        rtdesc.graphicsFormat = UnityEngine.Experimental.Rendering.GraphicsFormat.R8G8B8A8_UNorm; // 明确要求 RGBA 格式
        RenderingUtils.ReAllocateIfNeeded(ref m_TempRT3, rtdesc, name: "RF_CloudText_TempRT2");
        rtdesc.height /= 2;
        rtdesc.width /= 2;
        RenderingUtils.ReAllocateIfNeeded(ref m_TempRT, rtdesc, name: "RF_CloudText_TempRT");
        RenderingUtils.ReAllocateIfNeeded(ref m_TempRT2, rtdesc, name: "RF_CloudText_TempRT2");
        m_CameraColorRT = renderingData.cameraData.renderer.cameraColorTargetHandle;
    }



    // 具体执行操作 ————————
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData){
        if (volume == null || !volume.IsActive() || m_Material == null) return; // 再次检查，因为

        if (m_Material == null){   
            Debug.LogError("RFMuBan: Pass 执行时材质未分配!");
            return;
        }
        
        if (m_CameraColorRT == null || m_TempRT == null){   
            Debug.LogError("RFMuBan: Pass 执行时 RTHandles 未正确设置!");
            return;
        }

        CommandBuffer cmd = CommandBufferPool.Get(PROFILER_TAG);

        using (new ProfilingScope(cmd, m_ProfilingSampler)){

            // 传递包围盒数据给Shader
            if (_isBoxActiveAndVisibleThisFrame){
                cmd.SetGlobalVector(_VolumeBoxMinID, _activeBoxMinPoint);
                cmd.SetGlobalVector(_VolumeBoxMaxID, _activeBoxMaxPoint);
                cmd.SetGlobalFloat(_IsVolumeBoxActiveID, 1.0f);
            }
            else{
                cmd.SetGlobalVector(_VolumeBoxMinID, Vector4.zero);
                cmd.SetGlobalVector(_VolumeBoxMaxID, Vector4.zero);
                cmd.SetGlobalFloat(_IsVolumeBoxActiveID, 0.0f);         // 当包围盒不激活时，传递一些默认值，以防shader未处理这种情况
            }

            Blitter.BlitCameraTexture(cmd, m_CameraColorRT, m_TempRT, m_Material, 0);
            Blitter.BlitCameraTexture(cmd, m_TempRT, m_TempRT2, m_Material, 1);
            cmd.SetGlobalTexture(_CloudTexID, m_TempRT2);
            //Blitter.BlitCameraTexture(cmd, m_CameraColorRT, m_TempRT3, m_Material, 2);
            //Blitter.BlitCameraTexture(cmd, m_TempRT3, m_CameraColorRT);
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
        m_TempRT2?.Release();
        m_TempRT2 = null;
        m_TempRT3?.Release();
        m_TempRT3 = null;
    }

}

