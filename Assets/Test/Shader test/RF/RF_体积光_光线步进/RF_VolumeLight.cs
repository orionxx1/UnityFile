using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class RF_VolumeLight: ScriptableRendererFeature
{
    private RF_VolumeLightPass m_VolumeLightPass;
    public Material Material;
    public RenderPassEvent m_RenderPassEvent = RenderPassEvent.AfterRenderingTransparents; 

    public override void Create(){
        if ( Material == null){     // 即使材质为空，也创建Pass，但在Execute时检查
            Debug.LogWarning("RFMuBan: Material is not assigned. Feature will not run.");
        }

        // 配置Pass的渲染事件点
        m_VolumeLightPass = new RF_VolumeLightPass(Material);
        m_VolumeLightPass.renderPassEvent = m_RenderPassEvent;
    }

    // 每帧调用,将PASS添加进流程 ————————
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData){
        if (!ShouldRender(renderingData)) return;
        renderer.EnqueuePass(m_VolumeLightPass);            // 注入管线
    }

    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData){
        if (!ShouldRender(in renderingData)) return;
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
        m_VolumeLightPass?.Dispose();
        m_VolumeLightPass = null;
    }   
}


// Pass 类定义 ————————————————————
public class RF_VolumeLightPass : ScriptableRenderPass
{
    // 创建分析器 
    private const string PROFILER_TAG = "RF_VolumeLightPass";
    private ProfilingSampler m_ProfilingSampler = new ProfilingSampler(PROFILER_TAG);

    // RT
    private RTHandle m_CameraColorRT;                   // 源和最终目标
    private RTHandle m_TempRT;                          // 用于混合时作为临时缓冲的RT
    private RTHandle m_VolumeLightRT;                   // 用于存储纯体积光计算结果的RT
    private RTHandle m_BlurBuffer1;                     // 新增：用于Kawase模糊的乒乓操作的RT
    private RTHandle m_BlurBuffer2;
    private RenderTextureDescriptor rtdesc;

    // 材质变量
    private RF_VolumeLight_Volume volume;           // 体积
    public Material m_Material;          
    private float _Intensity;
    private int _StepTime;
    private float _StepSize;
    private float _BlurOffset;
    private Color _VolumeColor;
    private int _IntensityID;
    private int _StepTimeID;
    private int _StepSizeID;
    private int _BlurOffsetID;
    private int _VolumeColorID;

    // 用于在Shader中引用体积光纹理的ID
    private static readonly int _VolumeLightTexID = Shader.PropertyToID("_VolumeLightTex");

    // 包围盒
    private Vector4[] _activeBoxMinPoints;  // 用于存储所有激活包围盒的最小点
    private Vector4[] _activeBoxMaxPoints;  // 用于存储所有激活包围盒的最大点
    private int _activeBoxCount = 0;
    private static readonly int _VolumeBoxMinArrayID = Shader.PropertyToID("_VolumeBoxMinArray");
    private static readonly int _VolumeBoxMaxArrayID = Shader.PropertyToID("_VolumeBoxMaxArray");
    private static readonly int _VolumeBoxCountID    = Shader.PropertyToID("_VolumeBoxCount");

    // 预分配一个最大包围盒数量，避免每帧GC
    private const int MAX_SUPPORTED_BOXES = 8; 

    public RF_VolumeLightPass(Material material){
        m_Material = material;
        _IntensityID = Shader.PropertyToID("_Intensity");
        _StepTimeID = Shader.PropertyToID("_StepTime");
        _StepSizeID = Shader.PropertyToID("_StepSize");
        _BlurOffsetID = Shader.PropertyToID("_BlurOffset");
        _VolumeColorID = Shader.PropertyToID("_VolumeColor");

        _activeBoxMinPoints = new Vector4[MAX_SUPPORTED_BOXES];
        _activeBoxMaxPoints = new Vector4[MAX_SUPPORTED_BOXES];
    }

    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData){
        
        volume = VolumeManager.instance.stack.GetComponent<RF_VolumeLight_Volume>();

        if (volume != null && volume.IsActive()){
            if (m_Material != null){
                // 材质变量
                _Intensity = volume.Intensity.value;
                    m_Material.SetFloat(_IntensityID, _Intensity);
                _StepTime = volume.StepTime.value;
                    m_Material.SetFloat(_StepTimeID, _StepTime);
                _StepSize = volume.StepSize.value;
                    m_Material.SetFloat(_StepSizeID, _StepSize);
                _BlurOffset = volume.BlurOffset.value;
                    m_Material.SetFloat(_BlurOffsetID, _BlurOffset);
                _VolumeColor = volume.VolumeColor.value;
                    m_Material.SetColor(_VolumeColorID, _VolumeColor);

                ConfigureInput(ScriptableRenderPassInput.Color | ScriptableRenderPassInput.Depth);
            }
        }


        // 准备包围盒数据 ---
        _activeBoxCount = 0;
        if (VolumeLightBoundBoxAABB.ActiveBoxes != null){
            int count = 0;
            foreach (var box in VolumeLightBoundBoxAABB.ActiveBoxes){
                if (box != null && box.enabled && box.gameObject.activeInHierarchy && count < MAX_SUPPORTED_BOXES){
                    // 可选：在这里进行相机视锥体剔除，只传递可见的包围盒
                    // if (GeometryUtility.TestPlanesAABB(GeometryUtility.CalculateFrustumPlanes(renderingData.cameraData.camera), box.WorldBounds))
                    // {
                    _activeBoxMinPoints[count] = box.WorldBounds.min; // Bounds.min 是 Vector3，隐式转换为 Vector4 (w=0)
                    _activeBoxMaxPoints[count] = box.WorldBounds.max;
                    count++;
                    // }
                }
            }
            _activeBoxCount = count;
        }


        // 临时RT参数
        rtdesc = renderingData.cameraData.cameraTargetDescriptor;
        rtdesc.depthBufferBits = 0;           // 无深度
        rtdesc.msaaSamples = 1;               // 禁用MSAA
        // 获取一个临时的渲染目标,动态分配或复用临时渲染目标（_tempRT），检查其格式/尺寸与当前相机目标匹配，并自动匹配
        RenderingUtils.ReAllocateIfNeeded(ref m_TempRT, rtdesc, name: "RF_VolumeLight_TempRT");
        
        //rtdesc.height /=2;
        //rtdesc.width /=2;
        RenderingUtils.ReAllocateIfNeeded(ref m_VolumeLightRT, rtdesc, name: "RF_VolumeLight_VolumeRT");

        rtdesc.height /= 2;
        rtdesc.width /= 2;
        RenderingUtils.ReAllocateIfNeeded(ref m_BlurBuffer1, rtdesc, name: "RF_VolumeLight_BlurBuffer1");
        RenderingUtils.ReAllocateIfNeeded(ref m_BlurBuffer2, rtdesc, name: "RF_VolumeLight_BlurBuffer2");

        m_CameraColorRT = renderingData.cameraData.renderer.cameraColorTargetHandle;
    }

    // 具体执行操作 ————————
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData){
        if (volume == null || !volume.IsActive()) return; // 检查volume

        if (m_Material == null){   
            Debug.LogError("RFMuBan: Material not assigned!");              // 是否有材质
            return;}
        
        if (m_CameraColorRT == null || m_TempRT == null){   
            Debug.LogError("RFMuBan: RTHandles not properly setup!");       // RT没有设置
            return;}

        CommandBuffer cmd = CommandBufferPool.Get(PROFILER_TAG);

        using (new ProfilingScope(cmd, m_ProfilingSampler)){


            // 传递包围盒数据给Shader ---
            if (_activeBoxCount > 0){
                // 注意：Material.SetVectorArray 在CommandBuffer中不能直接使用，
                // 需要通过 cmd.SetGlobalVectorArray 或者在 OnCameraSetup 中设置到 m_Material (如果Pass是per-camera instance)
                // 为了简单起见，我们这里用 SetGlobal。如果材质属性需要 per-draw，则需要更复杂的处理。
                cmd.SetGlobalVectorArray(_VolumeBoxMinArrayID, _activeBoxMinPoints); // 只传递有效的部分，或者传递整个数组让Shader根据count判断
                cmd.SetGlobalVectorArray(_VolumeBoxMaxArrayID, _activeBoxMaxPoints);
            }
            cmd.SetGlobalInteger(_VolumeBoxCountID, _activeBoxCount); // 传递激活的包围盒数量


            // 1. 体积光光线步进
            Blitter.BlitCameraTexture(cmd, m_CameraColorRT, m_VolumeLightRT, m_Material, 0);
            // 2、体积光设置为全局纹理
            cmd.SetGlobalTexture(_VolumeLightTexID, m_VolumeLightRT);

            // 3、 体积光 Kawase模糊   ping-pong操作
            Blitter.BlitTexture(cmd, m_VolumeLightRT, m_BlurBuffer1, m_Material, 1);
            cmd.SetGlobalTexture(_VolumeLightTexID, m_BlurBuffer1);
            Blitter.BlitTexture(cmd, m_BlurBuffer1, m_BlurBuffer2, m_Material, 1);
            cmd.SetGlobalTexture(_VolumeLightTexID, m_BlurBuffer2);

            // 4、混合 _BlitTexture (原始场景) 和 _VolumeLightTex(体积光)
            Blitter.BlitTexture(cmd, m_CameraColorRT, m_TempRT, m_Material, 2);
            
            // 5、将混合结果拷回相机目标
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
        m_VolumeLightRT?.Release();
        m_VolumeLightRT = null;

        m_BlurBuffer1?.Release();
        m_BlurBuffer1 = null;
        m_BlurBuffer2?.Release();
        m_BlurBuffer2 = null;

        m_TempRT?.Release();
        m_TempRT = null;
    }
}


