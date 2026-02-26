// 这个类是整个GPU Driven渲染管线的核心控制器，负责管理所有GPU资源、
// 执行剔除、排序、数据压缩等计算，并最终提交渲染指令。

using System.Collections.Generic;
using UnityEngine;
using System.Runtime.InteropServices;
using UnityEngine.Rendering;
using static InstanceDropController;

public class InstanceDropRuntime
{
    #region 成员变量声明 (Member Variables)

    // --- 分块数据 ---
    private C_ChunkedTerrainVegetation vegChunkedData;    // 烘焙好的、包含所有分块和实例数据的ScriptableObject资产引用
    private ComputeBuffer m_ChunkInfoBuffer;              // GPU端Buffer，存储每个区块的元数据（起始实例索引, 实例数量）
    private ComputeBuffer m_VisibleChunkFlagsBuffer;      // GPU端Buffer，存储每个区块的可见性标志（1=可见, 0=不可见），由区块剔除
    private ComputeBuffer m_InstancePrefabTypeIDsBuffer;  // GPU端Buffer，存储每个实例对应的原型（Prefab）ID
    private int _NumChunks;                               // 缓存的区块总数

    // --- 分块剔除相关的GPU资源 ---
    private ComputeBuffer m_ChunkBoundsBuffer;            // 存储所有区块包围盒的Buffer
    private int m_cullChunksKernelID;                     // 新Kernel的ID
    private int m_cullChunksGroupX;                       // 新Kernel的线程组数
    private Vector4[] m_frustumPlanes = new Vector4[6];   // 用于存储视锥平面的CPU数组
    private static readonly int _FrustumPlanes = Shader.PropertyToID("_FrustumPlanes"); // Shader属性ID
    private static readonly int _ChunkBoundsBuffer = Shader.PropertyToID("_ChunkBoundsBuffer"); // Shader属性ID

    private ComputeBuffer m_InstanceChunkIDsBuffer;
    private static readonly int _InstanceChunkIDs = Shader.PropertyToID("_InstanceChunkIDs");

    // --- 核心数据与配置 ---
    private Camera mainCamera;                              // 渲染时使用的主相机
    private int _ItemCount;                                 // 所有植被类型的实例【总数】
    private int _InstanceTypeNum;                           // 植被类型的数量 (例如，草是一种类型，白桦树是另一种)
    private bool m_FrustumCull_On = true;                   // 是否开启视锥剔除
    private bool m_LodCull_On = true;                       // 是否开启LOD距离剔除
    private float m_MaxDrawDistance = 0f;                   // 最大渲染距离

    // --- Compute Shaders & Kernels ---
    private ComputeShader calculateDataMatrixCS;          // 用于将位置、旋转、缩放(TRS)计算为变换矩阵(Matrix)的CS
    private ComputeShader bitonicSortingCS;               // 用于对实例按距离进行双调排序的CS
    private ComputeShader cullingCS;                      // 核心剔除CS，包含区块剔除和实例剔除(视锥+LOD)的Kernel
    private ComputeShader copyInstancesDataCS;            // 用于执行流压缩（Stream Compaction）的CS，将可见实例数据拷贝到紧凑的RT
    private ComputeShader scanVisInstancesCS;             // 用于执行并行前缀和（Parallel Prefix Sum）第一步（组内扫描）的CS
    private ComputeShader scanVisGroupSumCS;              // 用于执行并行前缀和第二步（组间扫描）的CS
    private ComputeShader copyInstanceIDOffsetMapCS;      // 用于将各DrawCall的起始实例ID写入RT的CS，用于兼容旧图形API

    private int m_calculateDataMatrixCSKernelID;          // calculateDataMatrixCS 的 "CSMain" Kernel ID
    private int m_bitonicSortingCSKernelID;               // bitonicSortingCS 的 "BitonicSort" Kernel ID
    private int m_bitonicSortingTransposeCSKernelID;      // bitonicSortingCS 的 "MatrixTranspose" Kernel ID (用于排序的辅助步骤)
    private int m_cullingCSKernelID;                      // cullingCS 的 "CSMain" Kernel ID (实例剔除)
    private int m_copyInstancesDataCSKernelID;            // copyInstancesDataCS 的 "CSMain" Kernel ID
    private int m_scanVisInstancesCSKernelID;             // scanVisInstancesCS 的 "CSMain" Kernel ID
    private int m_scanVisGroupSumCSKernelID;              // scanVisGroupSumCS 的 "CSMain" Kernel ID
    private int m_copyInstanceIDOffsetMapCSKernelID;      // copyInstanceIDOffsetMapCS 的 "CSMain" Kernel ID
   
    // --- 线程组数量 (在初始化时计算，在每帧Dispatch时使用) ---
    private int m_calculateDataMatrixCSGroupX;            // calculateDataMatrixCS 需要调度的线程组X维度数量
    private int m_CullingCSGroupX;                        // cullingCS (CSMain) 需要调度的线程组X维度数量
    private int m_CopyInstancesDataCSGroupX;              // copyInstancesDataCS 需要调度的线程组X维度数量
    private int m_scanVisInstancesCSGroupX;               // scanVisInstancesCS 需要调度的线程组X维度数量
    private int m_scanVisGroupSumCSGroupX;                // scanVisGroupSumCS 需要调度的线程组X维度数量
    private int m_copyInstanceIDOffsetMapCSGroupX;        // copyInstanceIDOffsetMapCS 需要调度的线程组X维度数量j                                              

    // --- 渲染时所需的动态数据 ---
    private Matrix4x4 m_MatrixV;              // 主相机的视图矩阵 (World To View)
    private Matrix4x4 m_MatrixP;              // 主相机的投影矩阵 (View To Projection)
    private Vector4 m_CamPosition;            // 主相机的位置
    private float m_CamFieldOfView;           // 主相机的FOV

    // --- 渲染资源 ---
    private C_IndirectRenderingMesh[] m_IndirectMeshes;           // 每种类型的Mesh和Material的集合
    private uint[] m_args;                     // 间接绘制参数的CPU端缓存，用于初始化GPU Buffer
    private Bounds m_bounds;                   // 渲染时使用的全局包围盒

    // --- 尺寸信息 ---
    private int m_VegDataMapRes;                // 存储矩阵的RT的边长 (分辨率)
    private int m_InstanceIDOffsetMapRes;       // 存储ID偏移的RT的边长
    private int m_SortDataSize;                 // 排序数据Buffer的大小（已扩展到2的幂）

    // --- GPU资源：Compute Buffers ---
    private ComputeBuffer m_PositionBuffer;                 // [临时] 初始化时用，存储所有实例的位置
    private ComputeBuffer m_RotationBuffer;                 // [临时] 初始化时用，存储所有实例的旋转
    private ComputeBuffer m_ScaleBuffer;                    // [临时] 初始化时用，存储所有实例的缩放
    private ComputeBuffer m_localToWorldMatrixBuffer;       // 【数据库】存储所有实例的原始M矩阵
    private ComputeBuffer m_InstancesArgsBuffer;            // 存储最终的间接绘制参数 (会被CS修改)
    private ComputeBuffer m_InstanceBoundsDataBuffer;       // 存储每种【类型】的局部包围盒
    private ComputeBuffer m_InstanceLodViewRatioBuffer;     // 存储每种【类型】的LOD切换距离比率
    private ComputeBuffer m_InstanceCastShadowBuffer;       // 存储每种【类型】是否投射阴影
    private ComputeBuffer m_InstanceSortingData;            // 【核心】存储每个【实例】的排序信息 (原始索引+距离)
    private ComputeBuffer m_InstanceSortingDataTemp;        // 双调排序时使用的临时Buffer
    private ComputeBuffer m_IsVisibleBuffer;                // 存储每个实例的可见性标志 (0或1)
    private ComputeBuffer m_ScannedInstanceVisibleBuffer;   // 存储可见性标志的前缀和结果
    private ComputeBuffer m_GroupSumArrayBuffer;            // 并行前缀和的第一步结果 (组内和)
    private ComputeBuffer m_GroupSumArrayOutBuffer;         // 并行前缀和的第二步结果 (组间和)

    // --- 阴影相关的Buffer ---
    private ComputeBuffer m_ShadowArgsBuffer;                       // 存储阴影投射的间接绘制参数 (与主渲染结构相同)
    private ComputeBuffer m_ShadowIsVisibleBuffer;                  // 存储每个实例对于阴影Pass的可见性标志 (0或1)
    private ComputeBuffer m_ShadowScannedInstanceVisibleBuffer;     // 阴影可见性标志的并行前缀和第一步结果（组内局部排名）
    private ComputeBuffer m_ShadowGroupSumArrayBuffer;              // 阴影可见性标志的并行前缀和的中间结果（各组总和）
    private ComputeBuffer m_ShadowGroupSumArrayOutBuffer;           // 阴影可见性标志的并行前缀和的最终结果（组起始偏移）

    // --- GPU资源：Render Textures ---
    private RenderTexture m_VegDataMap;               // 【核心】存储可见实例的M矩阵，供VS采样
    private RenderTexture m_InstanceIDOffsetMap;      // 存储每个DrawCall的实例ID偏移
    private RenderTexture m_ShadowVegDataMap;
    private RenderTexture m_ShadowInstanceIDOffsetMap;

    // --- 异步计算 ---
    private CommandBuffer m_SortingCommandBuffer;     // 用于在异步计算队列执行排序的命令缓冲

    #endregion


    #region 常量与Shader属性ID (Constants & Shader IDs)

    // 这些常量定义了ArgsBuffer的布局结构，是整个系统的基石
    private const int NUMBER_OF_DRAW_CALLS = 3;     // 每个植被类型固定有3个LOD，对应3个DrawCall
    private const int NUMBER_OF_ARGS_PER_DRAW = 5;  // DrawMeshInstancedIndirect每个DrawCall需要5个uint参数
    private const int NUMBER_OF_ARGS_PER_INSTANCE_TYPE = NUMBER_OF_DRAW_CALLS * NUMBER_OF_ARGS_PER_DRAW; // 3 * 5 = 15
    private const int SCAN_THREAD_GROUP_SIZE = 128; // 并行扫描(Prefix Sum)算法的线程组大小

    private const int ARGS_BYTE_SIZE_PER_DRAW_CALL = NUMBER_OF_ARGS_PER_DRAW * sizeof(uint); // 5 * 4 = 20 bytes
    private const int ARGS_BYTE_SIZE_PER_INSTANCE_TYPE = NUMBER_OF_ARGS_PER_INSTANCE_TYPE * sizeof(uint); // 15 * 4 = 60 bytes

    // 提前获取Shader属性的ID，避免运行时字符串操作的开销
    private static readonly int _Position = Shader.PropertyToID("_Position");
    private static readonly int _Rotation = Shader.PropertyToID("_Rotation");
    private static readonly int _Scale = Shader.PropertyToID("_Scale");
    private static readonly int _LocalToWorldMatrixsBuffer = Shader.PropertyToID("_LocalToWorldMatrixsBuffer");
    private static readonly int _FrustumCull_On = Shader.PropertyToID("_FrustumCull_On");
    private static readonly int _LodCull_On = Shader.PropertyToID("_LodCull_On");
    private static readonly int _MaxDrawDistance = Shader.PropertyToID("_MaxDrawDistance");
    private static readonly int _CamPosition = Shader.PropertyToID("_CamPosition");
    private static readonly int _CamFieldOfView = Shader.PropertyToID("_CamFieldOfView");
    private static readonly int _UNITY_MATRIX_V = Shader.PropertyToID("_UNITY_MATRIX_V");
    private static readonly int _UNITY_MATRIX_P = Shader.PropertyToID("_UNITY_MATRIX_P");
    private static readonly int _VegDataMapRes = Shader.PropertyToID("_VegDataMapRes");
    private static readonly int _ArgsBuffer = Shader.PropertyToID("_ArgsBuffer");
    private static readonly int _InstanceBoundsDataBuffer = Shader.PropertyToID("_InstanceBoundsDataBuffer");
    private static readonly int _LodViewRatioBuffer = Shader.PropertyToID("_LodViewRatioBuffer");
    private static readonly int _InstanceCastShadowBuffer = Shader.PropertyToID("_InstanceCastShadowBuffer");
    private static readonly int _SortingData = Shader.PropertyToID("_SortingData");
    private static readonly int _IsVisibleBuffer = Shader.PropertyToID("_IsVisibleBuffer");
    private static readonly int _GroupSumArray = Shader.PropertyToID("_GroupSumArray");
    private static readonly int _NumOfGroups = Shader.PropertyToID("_NumOfGroups");
    private static readonly int _ScannedInstanceVisibleBuffer = Shader.PropertyToID("_ScannedInstanceVisibleBuffer");
    private static readonly int _GroupSumArrayOut = Shader.PropertyToID("_GroupSumArrayOut");
    private static readonly int _VegDataMap = Shader.PropertyToID("_VegDataMap");
    private static readonly int _NumOfDrawcalls = Shader.PropertyToID("_NumOfDrawcalls");
    private static readonly int _InstanceIDOffsetMapRes = Shader.PropertyToID("_InstanceIDOffsetMapRes");
    private static readonly int _InstanceIDOffsetMap = Shader.PropertyToID("_InstanceIDOffsetMap");
    private static readonly int _DrawCallIndex = Shader.PropertyToID("_DrawCallIndex");
    private static readonly int _Level = Shader.PropertyToID("_Level");
    private static readonly int _LevelMask = Shader.PropertyToID("_LevelMask");
    private static readonly int _MatrixWidth = Shader.PropertyToID("_MatrixWidth");
    private static readonly int _MatrixHeight = Shader.PropertyToID("_MatrixHeight");
    private static readonly int _Input = Shader.PropertyToID("_Input");
    private static readonly int _Data = Shader.PropertyToID("_Data");
    private static readonly int _ShadowDistance = Shader.PropertyToID("_ShadowDistance");
    private static readonly int _ShadowArgsBuffer = Shader.PropertyToID("_ShadowArgsBuffer");
    private static readonly int _ShadowIsVisibleBuffer = Shader.PropertyToID("_ShadowIsVisibleBuffer");

    #endregion



    #region 初始化与构造函数 (Initialization & Constructor)

    /// <summary>
    /// 构造函数，这是整个系统初始化的入口点。
    /// 它的任务是：读取数据 -> 聚合数据 -> 创建GPU资源 -> 预计算矩阵。
    /// 这是一个重量级操作，只应在开始时执行一次。
    /// 它像一个多步骤的“装配线”，将烘焙好的数据一步步加工成GPU能直接使用的格式。
    /// </summary>
    public InstanceDropRuntime(C_ChunkedTerrainVegetation chunkedData, C_GPUDriverComputeShader computeShaders, Camera camera)
    {
        Debug.Log("  构造函数开始  ");

        // ==========================================================================================
        // 【步骤 1: 数据接收与预处理】
        // ==========================================================================================
        this.mainCamera = camera;
        this.vegChunkedData = chunkedData;
        this.m_bounds = new Bounds(mainCamera.transform.position, Vector3.one * 1000); // 增大包围盒以适应大世界

        _NumChunks = vegChunkedData?._Chunks?.Count ?? 0;
        _InstanceTypeNum = vegChunkedData?._PrefabInfos?.Count ?? 0;
        _ItemCount = vegChunkedData?._AllInstanceTransforms?.Length ?? 0;

        if (_ItemCount == 0){
            Debug.LogWarning("  植被数据包含0个实例。初始化将被跳过  ");
            return;
        }

        // 标准化LOD数据
        for (int i = 0; i < _InstanceTypeNum; i++)
        {
            vegChunkedData._PrefabInfos[i]._VegetationLodGroup = ResetVegetationLodGroup(vegChunkedData._PrefabInfos[i]._VegetationLodGroup);
        }

        // ==========================================================================================
        // 【步骤 2: 【重写】在CPU端聚合所有实例数据】
        // 【当前步骤】: 直接从新的分块数据源聚合数据。
        // ==========================================================================================
        Debug.Log("  步骤2:从新数据源聚合数据...  ");

        // --- 创建临时的CPU列表来存储聚合后的数据 (这部分代码与旧版类似) ---
        var m_Position = new List<Vector3>(_ItemCount);
        var m_Rotation = new List<Vector3>(_ItemCount);
        var m_Scale = new List<float>(_ItemCount);
        var sortingData = new List<C_SortingData>(_ItemCount);
        var instancesBoundsInputData = new List<C_IndirectInstanceCSInput>(_InstanceTypeNum);
        var instancesLodViewRatio = new List<C_LodViewRatio>(_InstanceTypeNum);
        var instanceCastShadow = new List<uint>(_InstanceTypeNum);

        m_args = new uint[_InstanceTypeNum * NUMBER_OF_ARGS_PER_INSTANCE_TYPE];
        m_IndirectMeshes = new C_IndirectRenderingMesh[_InstanceTypeNum];

        // 1. 填充【原型】相关的数据 (types)
        for (int i = 0; i < _InstanceTypeNum; i++)
        {
            var currentPrefabInfo = vegChunkedData._PrefabInfos[i];
            m_IndirectMeshes[i] = InitIndirectRenderingMesh(currentPrefabInfo._VegetationLodGroup);

            int argsIndex = i * NUMBER_OF_ARGS_PER_INSTANCE_TYPE;
            m_args[argsIndex + 0] = currentPrefabInfo._VegetationLodGroup[0]._LodMesh.GetIndexCount(0);
            m_args[argsIndex + 5] = currentPrefabInfo._VegetationLodGroup[1]._LodMesh.GetIndexCount(0);
            m_args[argsIndex + 10] = currentPrefabInfo._VegetationLodGroup[2]._LodMesh.GetIndexCount(0);

            // 注意: 这里我们假设第一个LOD的包围盒是有效的，与旧逻辑保持一致
            instancesBoundsInputData.Add(new C_IndirectInstanceCSInput() { boundsCenter = currentPrefabInfo._LodBounds.center, boundsExtents = currentPrefabInfo._LodBounds.extents });
            instancesLodViewRatio.Add(new C_LodViewRatio() { lod0Range = currentPrefabInfo._VegetationLodGroup[0]._ViewDisRatio, lod1Range = currentPrefabInfo._VegetationLodGroup[1]._ViewDisRatio, lod2Range = currentPrefabInfo._VegetationLodGroup[2]._ViewDisRatio });
            instanceCastShadow.Add(currentPrefabInfo._CastShadow);
        }

        // 2. 填充【实例】相关的数据 (instances)
        // 【关键】: 直接遍历扁平化的全局数组，顺序是正确的！
        for (int i = 0; i < _ItemCount; i++)
        {
            var currentTransform = vegChunkedData._AllInstanceTransforms[i];
            var currentTypeID = vegChunkedData._AllInstancePrefabTypeIDs[i];

            m_Position.Add(currentTransform.postion);
            m_Rotation.Add(currentTransform.rotation);
            m_Scale.Add(currentTransform.scale);

            sortingData.Add(new C_SortingData()
            {
                // 【核心修正】: `drawCallInstanceIndex` 的生成逻辑现在直接依赖于我们烘焙好的数据
                drawCallInstanceIndex = ((((uint)currentTypeID * NUMBER_OF_ARGS_PER_INSTANCE_TYPE) << 16) + ((uint)i)),
                distanceToCam = Vector3.Distance(currentTransform.postion, mainCamera.transform.position)
            });
        }
        Debug.Log($"  数据聚合完成。实例总数:{_ItemCount}, 类型: {_InstanceTypeNum}  ");


        // ==========================================================================================
        // 【步骤 3: 计算GPU资源尺寸 (完全复用)】
        // ==========================================================================================
        if (this._ItemCount > 0)
        {
            m_VegDataMap = CreateRT(_ItemCount * 3, RenderTextureFormat.ARGBFloat, out m_VegDataMapRes, out m_ShadowVegDataMap);
        }
        m_InstanceIDOffsetMap = CreateRT(_InstanceTypeNum * NUMBER_OF_DRAW_CALLS, RenderTextureFormat.ARGBFloat, out m_InstanceIDOffsetMapRes, out m_ShadowInstanceIDOffsetMap);
        ExpandSortingDataSizeToPower2(ref sortingData, _ItemCount, _InstanceTypeNum, out m_SortDataSize);


        // ==========================================================================================
        // 【步骤 4 & 5: 初始化GPU管线
        // ==========================================================================================
        ComputeShaderInit(computeShaders);

        if (_NumChunks > 0)
        {
            m_VisibleChunkFlagsBuffer = new ComputeBuffer(_NumChunks, sizeof(int));
            
            // 【新增】创建并上传区块包围盒数据
            m_ChunkBoundsBuffer = new ComputeBuffer(_NumChunks, Marshal.SizeOf(typeof(Bounds)));    
            var chunkBounds = new Bounds[_NumChunks];
            var gpuChunkInfos = new C_GpuChunkInfo[_NumChunks]; // 创建一个新的 C_GpuChunkInfo 数组

            for (int i = 0; i < _NumChunks; i++)
            {
                gpuChunkInfos[i] = new C_GpuChunkInfo(chunkedData._Chunks[i]._StartIndex,chunkedData._Chunks[i]._Count);
                chunkBounds[i] = chunkedData._Chunks[i]._Bounds;
            }
            m_ChunkInfoBuffer = new ComputeBuffer(_NumChunks, Marshal.SizeOf(typeof(C_GpuChunkInfo)), ComputeBufferType.Structured, ComputeBufferMode.Immutable);
            m_ChunkInfoBuffer.SetData(gpuChunkInfos);
            m_ChunkBoundsBuffer.SetData(chunkBounds);

            m_InstancePrefabTypeIDsBuffer = new ComputeBuffer(vegChunkedData._AllInstancePrefabTypeIDs.Length, sizeof(int), ComputeBufferType.Structured, ComputeBufferMode.Immutable);
            m_InstancePrefabTypeIDsBuffer.SetData(vegChunkedData._AllInstancePrefabTypeIDs);
        }

        if (_ItemCount > 0)
        {
            m_PositionBuffer.SetData(m_Position);
            m_RotationBuffer.SetData(m_Rotation);
            m_ScaleBuffer.SetData(m_Scale);
        }

        m_InstancesArgsBuffer.SetData(m_args);
        m_ShadowArgsBuffer.SetData(m_args);

        if (_InstanceTypeNum > 0)
        {
            m_InstanceBoundsDataBuffer.SetData(instancesBoundsInputData);
            m_InstanceLodViewRatioBuffer.SetData(instancesLodViewRatio);
            m_InstanceCastShadowBuffer.SetData(instanceCastShadow);
        }

        m_InstanceSortingData.SetData(sortingData);
        m_InstanceSortingDataTemp.SetData(sortingData);
        Debug.Log($"    上传到GPU缓冲区的CPU数据    ");

        // ==========================================================================================
        // 【步骤 6: 最终设置与预计算 (完全复用)】
        // ==========================================================================================
        InitMatPropBlock();
        if (_ItemCount > 0)
        {
            CalculateVegData();      // 【修改】调用重构后的新方法
        }
        ComputeBufferInitSet();
        CreateSortingCommandBuffer();

        Debug.Log(" [构造函数结束] 初始化成功  ");
    }
    #endregion



    #region 运行时更新与渲染 (Runtime Update & Rendering)

    /// <summary>
    /// 每帧调用的主更新函数，驱动整个渲染管线。
    /// </summary>
    public void UpdateDraw()
    {
        if (_ItemCount == 0) return; // 如果没有实例，直接返回

        // 1. 在GPU上执行Culling, Scan, Compact等一系列计算任务
        ComputeBufferUpdate();

        // 2. 更新用于渲染的全局包围盒中心为相机位置。
        m_bounds.center = mainCamera.transform.position;

        // 3. 提交实际的绘制指令
        DrawInstance();
        DrawInstanceShadow();
    }

    /// <summary>
    /// 负责执行所有核心的Compute Shader任务。
    /// 这是每帧都在运转的“引擎室”，一个由多个CS任务组成的流水线。
    /// </summary>
    private void ComputeBufferUpdate()
    {
        // ==========================================================================================
        // 阶段零：GPU端区块剔除
        // ==========================================================================================
        if (_NumChunks > 0)
        {
            // 1. 在CPU计算视锥平面 (这部分开销极小，可以保留在CPU)
            Plane[] planes = GeometryUtility.CalculateFrustumPlanes(mainCamera);
            for (int i = 0; i < 6; i++)
            {
                m_frustumPlanes[i] = new Vector4(planes[i].normal.x, planes[i].normal.y, planes[i].normal.z, planes[i].distance);
            }

            // 2. 设置新Kernel的参数并Dispatch
            cullingCS.SetVectorArray(_FrustumPlanes, m_frustumPlanes);
            cullingCS.Dispatch(m_cullChunksKernelID, m_cullChunksGroupX, 1, 1);
        }

        // ==========================================================================================
        // 【阶段一：准备工作 (CPU -> GPU)】
        // ==========================================================================================
        // 【当前步骤】: 将每帧都会变化的CPU端数据（主要是相机信息）上传到GPU，并重置上一帧的计数器。
        // 【输入】: mainCamera的最新transform, QualitySettings的阴影距离。
        // 【输出】: GPU端的各个Compute Shader接收到了最新的uniform参数。
        //          _ArgsBuffer被一个近乎为0的数组覆盖，清空了上一帧的instanceCount。
        // 【目的】: 为本帧的GPU计算提供最新的上下文环境。
        // ==========================================================================================
        m_CamPosition = mainCamera.transform.position;
        m_CamFieldOfView = mainCamera.fieldOfView;
        m_MatrixV = mainCamera.worldToCameraMatrix;
        m_MatrixP = mainCamera.projectionMatrix;

        m_InstancesArgsBuffer.SetData(m_args);
        m_ShadowArgsBuffer.SetData(m_args);

        cullingCS.SetInt(_FrustumCull_On, m_FrustumCull_On ? 1 : 0);
        cullingCS.SetInt(_LodCull_On, m_LodCull_On ? 1 : 0);
        cullingCS.SetFloat(_MaxDrawDistance, m_MaxDrawDistance > 0 ? m_MaxDrawDistance : 10000.0f);
        cullingCS.SetFloat(_ShadowDistance, QualitySettings.shadowDistance);
        cullingCS.SetVector(_CamPosition, m_CamPosition);
        cullingCS.SetFloat(_CamFieldOfView, m_CamFieldOfView);
        cullingCS.SetMatrix(_UNITY_MATRIX_V, m_MatrixV);
        cullingCS.SetMatrix(_UNITY_MATRIX_P, m_MatrixP);
        cullingCS.SetBuffer(m_cullingCSKernelID, _ArgsBuffer, m_InstancesArgsBuffer);
        cullingCS.SetBuffer(m_cullingCSKernelID, _ShadowArgsBuffer, m_ShadowArgsBuffer);



        // ==========================================================================================
        // 【阶段二：剔除 (Culling)】
        // ==========================================================================================
        // 【当前步骤】: 在GPU上并行地对所有实例进行视锥和LOD剔除。
        // 【输入】: 所有实例的M矩阵、包围盒、LOD数据，以及刚上传的相机信息。
        // 【输出】: 
        //    1. _IsVisibleBuffer: 一个0/1的掩码数组，标记了每个实例是否可见。
        //    2. _ArgsBuffer: 其中的instanceCount字段被原子地增加了，统计了每个LOD的可见实例数。
        // 【目的】: 完成第一轮筛选，得到一个“稀疏”的可见性列表，为后续的“紧凑化”做准备。
        // ==========================================================================================
        cullingCS.Dispatch(m_cullingCSKernelID, m_CullingCSGroupX, 1, 1);


        // ==========================================================================================
        // 【阶段三：前缀和 (Prefix Sum) - Step 1: 组内扫描】
        // ==========================================================================================
        // 【当前步骤】: 对剔除后得到的_IsVisibleBuffer，在每个线程组内部进行前缀和计算。
        // 【输入】: _IsVisibleBuffer (0/1掩码数组)。
        // 【输出】:
        //    1. _ScannedInstanceVisibleBuffer: 存储了每个实例在其线程组内部的“局部排名”。
        //    2. _GroupSumArrayBuffer: 存储了每个线程组内可见实例的“总人数”。
        // 【目的】: 完成“紧凑化”所需的第一步计算，为下一步的组间扫描提供数据。
        // ==========================================================================================
        // --- 主渲染 ---
        scanVisInstancesCS.SetBuffer(m_scanVisInstancesCSKernelID, _IsVisibleBuffer, m_IsVisibleBuffer);
        scanVisInstancesCS.SetBuffer(m_scanVisInstancesCSKernelID, _GroupSumArray, m_GroupSumArrayBuffer);
        scanVisInstancesCS.SetBuffer(m_scanVisInstancesCSKernelID, _ScannedInstanceVisibleBuffer, m_ScannedInstanceVisibleBuffer);
        scanVisInstancesCS.Dispatch(m_scanVisInstancesCSKernelID, m_scanVisInstancesCSGroupX, 1, 1);

        // --- 阴影 (重复一次，处理阴影的可见性数据) ---
        scanVisInstancesCS.SetBuffer(m_scanVisInstancesCSKernelID, _IsVisibleBuffer, m_ShadowIsVisibleBuffer);
        scanVisInstancesCS.SetBuffer(m_scanVisInstancesCSKernelID, _GroupSumArray, m_ShadowGroupSumArrayBuffer);
        scanVisInstancesCS.SetBuffer(m_scanVisInstancesCSKernelID, _ScannedInstanceVisibleBuffer, m_ShadowScannedInstanceVisibleBuffer);
        scanVisInstancesCS.Dispatch(m_scanVisInstancesCSKernelID, m_scanVisInstancesCSGroupX, 1, 1);


        // ==========================================================================================
        // 【阶段四：前缀和 (Prefix Sum) - Step 2: 组间扫描】
        // ==========================================================================================
        // 【当前步骤】: 对上一步得到的“各组总人数”数组，再进行一次前缀和。
        // 【输入】: _GroupSumArrayBuffer。
        // 【输出】: _GroupSumArrayOutBuffer: 存储了每个线程组在最终紧凑列表中的“起始排队位置”。
        // 【目的】: 完成“紧凑化”所需的所有计算。现在，任何一个可见实例都可以通过
        //         “它的组的起始位置” + “它在组内的排名” = “它在最终队伍里的精确位置” 来定位自己。
        // ==========================================================================================
        // --- 主渲染 ---
        scanVisGroupSumCS.SetBuffer(m_scanVisGroupSumCSKernelID, _GroupSumArray, m_GroupSumArrayBuffer);
        scanVisGroupSumCS.SetBuffer(m_scanVisGroupSumCSKernelID, _GroupSumArrayOut, m_GroupSumArrayOutBuffer);
        scanVisGroupSumCS.Dispatch(m_scanVisGroupSumCSKernelID, m_scanVisGroupSumCSGroupX, 1, 1);

        // --- 阴影 ---
        scanVisGroupSumCS.SetBuffer(m_scanVisGroupSumCSKernelID, _GroupSumArray, m_ShadowGroupSumArrayBuffer);
        scanVisGroupSumCS.SetBuffer(m_scanVisGroupSumCSKernelID, _GroupSumArrayOut, m_ShadowGroupSumArrayOutBuffer);
        scanVisGroupSumCS.Dispatch(m_scanVisGroupSumCSKernelID, m_scanVisGroupSumCSGroupX, 1, 1);



        // ==========================================================================================
        // 【阶段五：流压缩 (Stream Compaction)】
        // ==========================================================================================
        // 【当前步骤】: 根据前缀和计算出的最终索引，将可见实例的M矩阵从“数据库”Buffer中，
        //             紧凑地拷贝到最终的渲染纹理(_VegDataMap)中。
        // 【输入】: _IsVisibleBuffer, _ScannedInstanceVisibleBuffer, _GroupSumArrayOutBuffer,
        //          以及包含原始M矩阵的 _LocalToWorldMatrixsBuffer。
        // 【输出】:
        //    1. _VegDataMap: 这张RT被填满了所有可见实例的M矩阵，它们是连续存放的。
        //    2. _ArgsBuffer: 其中的startInstance字段被更新，记录了每个DrawCall的数据在_VegDataMap中的起始位置。
        // 【目的】: 生成最终的、可以直接被DrawMeshInstancedIndirect消费的数据。
        // ==========================================================================================
        // --- 主渲染 ---
        copyInstancesDataCS.SetTexture(m_copyInstancesDataCSKernelID, _VegDataMap, m_VegDataMap);
        copyInstancesDataCS.SetBuffer(m_copyInstancesDataCSKernelID, _IsVisibleBuffer, m_IsVisibleBuffer);
        copyInstancesDataCS.SetBuffer(m_copyInstancesDataCSKernelID, _GroupSumArray, m_GroupSumArrayOutBuffer);
        copyInstancesDataCS.SetBuffer(m_copyInstancesDataCSKernelID, _ScannedInstanceVisibleBuffer, m_ScannedInstanceVisibleBuffer);
        copyInstancesDataCS.SetBuffer(m_copyInstancesDataCSKernelID, _ArgsBuffer, m_InstancesArgsBuffer);
        copyInstancesDataCS.Dispatch(m_copyInstancesDataCSKernelID, m_CopyInstancesDataCSGroupX, 1, 1);

        // --- 阴影 ---
        copyInstancesDataCS.SetTexture(m_copyInstancesDataCSKernelID, _VegDataMap, m_ShadowVegDataMap);
        copyInstancesDataCS.SetBuffer(m_copyInstancesDataCSKernelID, _IsVisibleBuffer, m_ShadowIsVisibleBuffer);
        copyInstancesDataCS.SetBuffer(m_copyInstancesDataCSKernelID, _GroupSumArray, m_ShadowGroupSumArrayOutBuffer);
        copyInstancesDataCS.SetBuffer(m_copyInstancesDataCSKernelID, _ScannedInstanceVisibleBuffer, m_ShadowScannedInstanceVisibleBuffer);
        copyInstancesDataCS.SetBuffer(m_copyInstancesDataCSKernelID, _ArgsBuffer, m_ShadowArgsBuffer);
        copyInstancesDataCS.Dispatch(m_copyInstancesDataCSKernelID, m_CopyInstancesDataCSGroupX, 1, 1);



        // ==========================================================================================
        // 【阶段六：生成ID偏移图 (Instance ID Offset Map)】
        // ==========================================================================================
        // 【当前步骤】: 读取_ArgsBuffer中的startInstance值，并将其写入_InstanceIDOffsetMap这张RT。
        // 【输入】: _ArgsBuffer (已被上一步更新)。
        // 【输出】: _InstanceIDOffsetMap: 这张RT被填充了每个DrawCall的起始实例ID偏移。
        // 【目的】: 这是一个兼容性措施。为那些不支持在SV_InstanceID中自动包含基址的图形API
        //         （如OpenGL ES），提供一个在Shader中手动加上偏移的方法。
        // ==========================================================================================
        // --- 主渲染 ---
        copyInstanceIDOffsetMapCS.SetBuffer(m_copyInstanceIDOffsetMapCSKernelID, _ArgsBuffer, m_InstancesArgsBuffer);
        copyInstanceIDOffsetMapCS.SetTexture(m_copyInstanceIDOffsetMapCSKernelID, _InstanceIDOffsetMap, m_InstanceIDOffsetMap);
        copyInstanceIDOffsetMapCS.Dispatch(m_copyInstanceIDOffsetMapCSKernelID, m_copyInstanceIDOffsetMapCSGroupX, 1, 1);

        // --- 阴影 ---
        copyInstanceIDOffsetMapCS.SetBuffer(m_copyInstanceIDOffsetMapCSKernelID, _ArgsBuffer, m_ShadowArgsBuffer);
        copyInstanceIDOffsetMapCS.SetTexture(m_copyInstanceIDOffsetMapCSKernelID, _InstanceIDOffsetMap, m_ShadowInstanceIDOffsetMap);
        copyInstanceIDOffsetMapCS.Dispatch(m_copyInstanceIDOffsetMapCSKernelID, m_copyInstanceIDOffsetMapCSGroupX, 1, 1);



        // ==========================================================================================
        // 【阶段七：异步排序 (Asynchronous Sort)】
        // ==========================================================================================
        // 【当前步骤】: 将一个预先构建好的、包含双调排序所有指令的CommandBuffer，提交到GPU的异步计算队列。
        // 【输入】: m_SortingCommandBuffer (在初始化时已构建好)。
        // 【输出】: 在未来的某个时间点，m_InstanceSortingData这个Buffer的内容会被原地排序。
        // 【目的】: 为【下一帧】的剔除操作进行性能优化。通过按距离排序，可以改善内存访问的局部性，
        //         提高缓存命中率。因为它不影响本帧的渲染结果，所以可以异步执行，不阻塞渲染主线程。
        // ==========================================================================================
        Graphics.ExecuteCommandBufferAsync(m_SortingCommandBuffer, ComputeQueueType.Background);

    }


    private void DrawInstance()
    {
        for (int i = 0; i < _InstanceTypeNum; i++)
        {
            int argsByteOffset = i * ARGS_BYTE_SIZE_PER_INSTANCE_TYPE;
            C_IndirectRenderingMesh indirectMesh = m_IndirectMeshes[i];

            for (int j = 0; j < NUMBER_OF_DRAW_CALLS; j++)
            {
                // ———— 提交主渲染的绘制指令 ————
                Graphics.DrawMeshInstancedIndirect(
                    indirectMesh.meshes[j], 
                    0, 
                    indirectMesh.material[j], 
                    m_bounds, 
                    m_InstancesArgsBuffer, 
                    argsByteOffset + ARGS_BYTE_SIZE_PER_DRAW_CALL * j, 
                    indirectMesh.lodMatPropBlock[j], 
                    ShadowCastingMode.Off, 
                    true);
            }
        }
    }


    /// <summary>
    /// 提交阴影投射的绘制指令
    /// </summary>
    private void DrawInstanceShadow()
    {
        for (int i = 0; i < _InstanceTypeNum; i++)
        {
            int argsByteOffset = i * ARGS_BYTE_SIZE_PER_INSTANCE_TYPE;
            C_IndirectRenderingMesh indirectMesh = m_IndirectMeshes[i];

            for (int j = 0; j < NUMBER_OF_DRAW_CALLS; j++)
            {
                Graphics.DrawMeshInstancedIndirect(
                    indirectMesh.meshes[j], 
                    0, 
                    indirectMesh.material[j], 
                    m_bounds, m_ShadowArgsBuffer, 
                    argsByteOffset + ARGS_BYTE_SIZE_PER_DRAW_CALL * j, 
                    indirectMesh.shadowLodMatPropBlock[j], 
                    ShadowCastingMode.ShadowsOnly, 
                    false);
            }
        }
    }

    public void SetCullingParameters(bool onFrustumCull, bool onLodCull, float maxDrawDistance)
    {
        this.m_FrustumCull_On = onFrustumCull;
        this.m_LodCull_On = onLodCull;
        this.m_MaxDrawDistance = maxDrawDistance;           // 存储新值
    }
    #endregion



    #region 资源释放与辅助方法 (Helpers & Cleanup)

    public void Release()
    {
        ReleaseComputeBuffer(ref m_PositionBuffer);
        ReleaseComputeBuffer(ref m_RotationBuffer);
        ReleaseComputeBuffer(ref m_ScaleBuffer);

        ReleaseComputeBuffer(ref m_localToWorldMatrixBuffer);
        ReleaseComputeBuffer(ref m_InstancesArgsBuffer);
        ReleaseComputeBuffer(ref m_InstanceBoundsDataBuffer);
        ReleaseComputeBuffer(ref m_InstanceLodViewRatioBuffer);
        ReleaseComputeBuffer(ref m_InstanceCastShadowBuffer);
        ReleaseComputeBuffer(ref m_InstanceSortingData);
        ReleaseComputeBuffer(ref m_InstanceSortingDataTemp);
        ReleaseComputeBuffer(ref m_IsVisibleBuffer);
        ReleaseComputeBuffer(ref m_ScannedInstanceVisibleBuffer);
        ReleaseComputeBuffer(ref m_GroupSumArrayBuffer);
        ReleaseComputeBuffer(ref m_GroupSumArrayOutBuffer);
        ReleaseComputeBuffer(ref m_ShadowArgsBuffer);
        ReleaseComputeBuffer(ref m_ShadowIsVisibleBuffer);
        ReleaseComputeBuffer(ref m_ShadowScannedInstanceVisibleBuffer);
        ReleaseComputeBuffer(ref m_ShadowGroupSumArrayBuffer);
        ReleaseComputeBuffer(ref m_ShadowGroupSumArrayOutBuffer);
        ReleaseRendertexture(ref m_VegDataMap);
        ReleaseRendertexture(ref m_InstanceIDOffsetMap);
        ReleaseRendertexture(ref m_ShadowVegDataMap);
        ReleaseRendertexture(ref m_ShadowInstanceIDOffsetMap);

        ReleaseComputeBuffer(ref m_ChunkInfoBuffer);
        ReleaseComputeBuffer(ref m_VisibleChunkFlagsBuffer);
        ReleaseComputeBuffer(ref m_InstancePrefabTypeIDsBuffer);
        ReleaseComputeBuffer(ref m_ChunkBoundsBuffer); 
        ReleaseComputeBuffer(ref m_InstanceChunkIDsBuffer); 

        ReleaseCommandBuffer(ref m_SortingCommandBuffer);

        if (m_IndirectMeshes != null)
        {
            for (int i = 0; i < m_IndirectMeshes.Length; i++)
            {
                if (m_IndirectMeshes[i]?.material == null) continue;
                for (int j = 0; j < m_IndirectMeshes[i].material.Length; j++)
                {
                    if (Application.isPlaying) GameObject.Destroy(m_IndirectMeshes[i].material[j]);
                    else GameObject.DestroyImmediate(m_IndirectMeshes[i].material[j]);
                }
            }
        }
    }

    // --- 所有辅助方法的完整实现 ---
    private void ComputeShaderInit(C_GPUDriverComputeShader computeShaders)
    {
        calculateDataMatrixCS = computeShaders.calculateDataMatrixCompute;
        bitonicSortingCS = computeShaders.bitonicSortingCS;
        cullingCS = computeShaders.cullingCompute;
        copyInstancesDataCS = computeShaders.copyInstancesDataCompute;
        scanVisInstancesCS = computeShaders.scanVisInstancesCompute;
        scanVisGroupSumCS = computeShaders.scanVisGroupSumCompute;
        copyInstanceIDOffsetMapCS = computeShaders.copyInstanceIDOffsetMapCompute;

        m_calculateDataMatrixCSKernelID = calculateDataMatrixCS.FindKernel("CSMain");
        m_bitonicSortingCSKernelID = bitonicSortingCS.FindKernel("BitonicSort");
        m_bitonicSortingTransposeCSKernelID = bitonicSortingCS.FindKernel("MatrixTranspose");
        m_cullingCSKernelID = cullingCS.FindKernel("CSMain");
        m_cullChunksKernelID = cullingCS.FindKernel("CullChunks"); // 【新增】获取新Kernel的ID
        m_scanVisInstancesCSKernelID = scanVisInstancesCS.FindKernel("CSMain");
        m_scanVisGroupSumCSKernelID = scanVisGroupSumCS.FindKernel("CSMain");
        m_copyInstancesDataCSKernelID = copyInstancesDataCS.FindKernel("CSMain");
        m_copyInstanceIDOffsetMapCSKernelID = copyInstanceIDOffsetMapCS.FindKernel("CSMain");

        if (_ItemCount > 0)
        {
            m_PositionBuffer = new ComputeBuffer(_ItemCount, sizeof(float) * 3);
            m_RotationBuffer = new ComputeBuffer(_ItemCount, sizeof(float) * 3);
            m_ScaleBuffer = new ComputeBuffer(_ItemCount, sizeof(float));
            m_localToWorldMatrixBuffer = new ComputeBuffer(_ItemCount, sizeof(float) * 16);
            m_IsVisibleBuffer = new ComputeBuffer(_ItemCount, sizeof(uint));
            m_GroupSumArrayBuffer = new ComputeBuffer(_ItemCount, sizeof(uint));
            m_ScannedInstanceVisibleBuffer = new ComputeBuffer(_ItemCount, sizeof(uint));
            m_GroupSumArrayOutBuffer = new ComputeBuffer(_ItemCount, sizeof(uint));
            m_ShadowIsVisibleBuffer = new ComputeBuffer(_ItemCount, sizeof(uint));
            m_ShadowGroupSumArrayBuffer = new ComputeBuffer(_ItemCount, sizeof(uint));
            m_ShadowScannedInstanceVisibleBuffer = new ComputeBuffer(_ItemCount, sizeof(uint));
            m_ShadowGroupSumArrayOutBuffer = new ComputeBuffer(_ItemCount, sizeof(uint));
        }

        // m_InstancesArgsBuffer 初始化
        m_InstancesArgsBuffer = new ComputeBuffer(_InstanceTypeNum * NUMBER_OF_ARGS_PER_INSTANCE_TYPE, sizeof(uint), ComputeBufferType.IndirectArguments);
        m_ShadowArgsBuffer = new ComputeBuffer(_InstanceTypeNum * NUMBER_OF_ARGS_PER_INSTANCE_TYPE, sizeof(uint), ComputeBufferType.IndirectArguments);

        if (_InstanceTypeNum > 0)
        {
            m_InstanceBoundsDataBuffer = new ComputeBuffer(_InstanceTypeNum, Marshal.SizeOf(typeof(C_IndirectInstanceCSInput)));
            m_InstanceLodViewRatioBuffer = new ComputeBuffer(_InstanceTypeNum, Marshal.SizeOf(typeof(C_LodViewRatio)));
            m_InstanceCastShadowBuffer = new ComputeBuffer(_InstanceTypeNum, sizeof(uint));
        }

        m_InstanceSortingData = new ComputeBuffer(m_SortDataSize, Marshal.SizeOf(typeof(C_SortingData)));
        m_InstanceSortingDataTemp = new ComputeBuffer(m_SortDataSize, Marshal.SizeOf(typeof(C_SortingData)));
    }


    private void ComputeBufferInitSet()
    {
        if (_NumChunks > 0)
        {
            // 【新增】计算新Kernel的线程组数
            m_cullChunksGroupX = Mathf.CeilToInt((float)_NumChunks / 64f);

            // 【新增】为新Kernel设置不变的Buffer
            cullingCS.SetBuffer(m_cullChunksKernelID, _ChunkBoundsBuffer, m_ChunkBoundsBuffer);
            cullingCS.SetBuffer(m_cullChunksKernelID, "_VisibleChunkFlags", m_VisibleChunkFlagsBuffer);

            cullingCS.SetInt("_NumChunks", _NumChunks);
            cullingCS.SetBuffer(m_cullingCSKernelID, "_ChunkInfos", m_ChunkInfoBuffer);
            cullingCS.SetBuffer(m_cullingCSKernelID, "_VisibleChunkFlags", m_VisibleChunkFlagsBuffer);
            cullingCS.SetBuffer(m_cullingCSKernelID, "_InstancePrefabTypeIDs", m_InstancePrefabTypeIDsBuffer);

            if (m_InstanceChunkIDsBuffer != null)
            {
                cullingCS.SetBuffer(m_cullingCSKernelID, _InstanceChunkIDs, m_InstanceChunkIDsBuffer);
            }
        }


        if (_ItemCount == 0) return;
        m_CullingCSGroupX = Mathf.Max(1, Mathf.CeilToInt((float)_ItemCount / 64f));
        m_scanVisInstancesCSGroupX = Mathf.Max(1, Mathf.CeilToInt((float)_ItemCount / (2f * SCAN_THREAD_GROUP_SIZE)));
        m_scanVisGroupSumCSGroupX = 1;
        m_CopyInstancesDataCSGroupX = Mathf.Max(1, Mathf.CeilToInt((float)_ItemCount / (2f * SCAN_THREAD_GROUP_SIZE)));
        m_copyInstanceIDOffsetMapCSGroupX = Mathf.Max(1, Mathf.CeilToInt((float)(_InstanceTypeNum * NUMBER_OF_DRAW_CALLS) / 64f));

        cullingCS.SetBuffer(m_cullingCSKernelID, _InstanceBoundsDataBuffer, m_InstanceBoundsDataBuffer);
        cullingCS.SetBuffer(m_cullingCSKernelID, _LodViewRatioBuffer, m_InstanceLodViewRatioBuffer);
        cullingCS.SetBuffer(m_cullingCSKernelID, _InstanceCastShadowBuffer, m_InstanceCastShadowBuffer);
        cullingCS.SetBuffer(m_cullingCSKernelID, _SortingData, m_InstanceSortingData);
        cullingCS.SetBuffer(m_cullingCSKernelID, _LocalToWorldMatrixsBuffer, m_localToWorldMatrixBuffer);
        cullingCS.SetBuffer(m_cullingCSKernelID, _IsVisibleBuffer, m_IsVisibleBuffer);
        cullingCS.SetBuffer(m_cullingCSKernelID, _ShadowIsVisibleBuffer, m_ShadowIsVisibleBuffer);

        scanVisGroupSumCS.SetInt(_NumOfGroups, ExpandGroupSizeToPower2(m_scanVisInstancesCSGroupX));
        copyInstancesDataCS.SetInt(_VegDataMapRes, m_VegDataMapRes);
        copyInstancesDataCS.SetInt(_NumOfDrawcalls, _InstanceTypeNum * NUMBER_OF_DRAW_CALLS);
        copyInstancesDataCS.SetBuffer(m_copyInstancesDataCSKernelID, _SortingData, m_InstanceSortingData);
        copyInstancesDataCS.SetBuffer(m_copyInstancesDataCSKernelID, _LocalToWorldMatrixsBuffer, m_localToWorldMatrixBuffer);
        copyInstanceIDOffsetMapCS.SetInt(_InstanceIDOffsetMapRes, m_InstanceIDOffsetMapRes);
    }

    private void CalculateVegData()
    {
        // 1. 原有的矩阵计算绑定
        calculateDataMatrixCS.SetBuffer(m_calculateDataMatrixCSKernelID, _Position, m_PositionBuffer);
        calculateDataMatrixCS.SetBuffer(m_calculateDataMatrixCSKernelID, _Rotation, m_RotationBuffer);
        calculateDataMatrixCS.SetBuffer(m_calculateDataMatrixCSKernelID, _Scale, m_ScaleBuffer);
        calculateDataMatrixCS.SetBuffer(m_calculateDataMatrixCSKernelID, _LocalToWorldMatrixsBuffer, m_localToWorldMatrixBuffer);

        // 2. 【新增】为区块ID计算绑定新的 Buffer 和参数
        if (_NumChunks > 0)
        {
            m_InstanceChunkIDsBuffer = new ComputeBuffer(_ItemCount, sizeof(uint));
            calculateDataMatrixCS.SetInt("_NumChunks", _NumChunks);
            calculateDataMatrixCS.SetBuffer(m_calculateDataMatrixCSKernelID, "_ChunkInfos", m_ChunkInfoBuffer);
            calculateDataMatrixCS.SetBuffer(m_calculateDataMatrixCSKernelID, _InstanceChunkIDs, m_InstanceChunkIDsBuffer);
        }

        // 3. Dispatch
        m_calculateDataMatrixCSGroupX = Mathf.Max(1, Mathf.CeilToInt((float)_ItemCount / 64f));
        calculateDataMatrixCS.Dispatch(m_calculateDataMatrixCSKernelID, m_calculateDataMatrixCSGroupX, 1, 1);

        // 4. 释放临时Buffer
        ReleaseComputeBuffer(ref m_PositionBuffer);
        ReleaseComputeBuffer(ref m_RotationBuffer);
        ReleaseComputeBuffer(ref m_ScaleBuffer);
    }

    private void InitMatPropBlock()
    {
        if (m_IndirectMeshes == null) return;
        int index = 0;
        for (int i = 0; i < m_IndirectMeshes.Length; i++)
        {
            C_IndirectRenderingMesh indirectMesh = m_IndirectMeshes[i];
            for (int j = 0; j < NUMBER_OF_DRAW_CALLS; j++)
            {
                indirectMesh.lodMatPropBlock[j].SetInt(_DrawCallIndex, index);
                indirectMesh.lodMatPropBlock[j].SetFloat(_VegDataMapRes, m_VegDataMapRes);
                indirectMesh.lodMatPropBlock[j].SetFloat(_InstanceIDOffsetMapRes, m_InstanceIDOffsetMapRes);
                indirectMesh.lodMatPropBlock[j].SetTexture(_VegDataMap, m_VegDataMap);
                indirectMesh.lodMatPropBlock[j].SetTexture(_InstanceIDOffsetMap, m_InstanceIDOffsetMap);
                indirectMesh.shadowLodMatPropBlock[j].SetInt(_DrawCallIndex, index);
                indirectMesh.shadowLodMatPropBlock[j].SetFloat(_VegDataMapRes, m_VegDataMapRes);
                indirectMesh.shadowLodMatPropBlock[j].SetFloat(_InstanceIDOffsetMapRes, m_InstanceIDOffsetMapRes);
                indirectMesh.shadowLodMatPropBlock[j].SetTexture(_VegDataMap, m_ShadowVegDataMap);
                indirectMesh.shadowLodMatPropBlock[j].SetTexture(_InstanceIDOffsetMap, m_ShadowInstanceIDOffsetMap);
                indirectMesh.material[j].EnableKeyword("_UT_INSTANCING_ON");
                index++;
            }
        }
    }

    private void CreateSortingCommandBuffer()
    {
        m_SortingCommandBuffer = new CommandBuffer { name = "AsyncSorting" };
        m_SortingCommandBuffer.SetExecutionFlags(CommandBufferExecutionFlags.AsyncCompute);
        uint NUM_SORTINGDATA = (uint)m_SortDataSize;
        uint BITONIC_BLOCK_SIZE = 256;
        uint TRANSPOSE_BLOCK_SIZE = 8;
        uint matrixWidth = BITONIC_BLOCK_SIZE;
        uint matrixHeight = NUM_SORTINGDATA / BITONIC_BLOCK_SIZE;
        int sortGroupX = Mathf.Max(1, (int)(NUM_SORTINGDATA / BITONIC_BLOCK_SIZE));
        int transposeGroupX = Mathf.Max(1, (int)(matrixWidth / TRANSPOSE_BLOCK_SIZE));
        int transposeGroupY = Mathf.Max(1, (int)(matrixHeight / TRANSPOSE_BLOCK_SIZE));

        for (uint level = 2; level <= BITONIC_BLOCK_SIZE; level <<= 1)
        {
            SetSortingConstants(m_SortingCommandBuffer, bitonicSortingCS, level, level, matrixWidth, matrixHeight);
            m_SortingCommandBuffer.SetComputeBufferParam(bitonicSortingCS, m_bitonicSortingCSKernelID, _Data, m_InstanceSortingData);
            m_SortingCommandBuffer.DispatchCompute(bitonicSortingCS, m_bitonicSortingCSKernelID, sortGroupX, 1, 1);
        }

        for (uint level = (BITONIC_BLOCK_SIZE << 1); level <= NUM_SORTINGDATA; level <<= 1)
        {
            uint colLevel = (level / BITONIC_BLOCK_SIZE);
            uint colLevelMask = (level & ~NUM_SORTINGDATA) / BITONIC_BLOCK_SIZE;
            SetSortingConstants(m_SortingCommandBuffer, bitonicSortingCS, colLevel, colLevelMask, matrixWidth, matrixHeight);
            m_SortingCommandBuffer.SetComputeBufferParam(bitonicSortingCS, m_bitonicSortingTransposeCSKernelID, _Input, m_InstanceSortingData);
            m_SortingCommandBuffer.SetComputeBufferParam(bitonicSortingCS, m_bitonicSortingTransposeCSKernelID, _Data, m_InstanceSortingDataTemp);
            m_SortingCommandBuffer.DispatchCompute(bitonicSortingCS, m_bitonicSortingTransposeCSKernelID, transposeGroupX, transposeGroupY, 1);

            m_SortingCommandBuffer.SetComputeBufferParam(bitonicSortingCS, m_bitonicSortingCSKernelID, _Data, m_InstanceSortingDataTemp);
            m_SortingCommandBuffer.DispatchCompute(bitonicSortingCS, m_bitonicSortingCSKernelID, sortGroupX, 1, 1);

            SetSortingConstants(m_SortingCommandBuffer, bitonicSortingCS, BITONIC_BLOCK_SIZE, level, matrixHeight, matrixWidth);
            m_SortingCommandBuffer.SetComputeBufferParam(bitonicSortingCS, m_bitonicSortingTransposeCSKernelID, _Input, m_InstanceSortingDataTemp);
            m_SortingCommandBuffer.SetComputeBufferParam(bitonicSortingCS, m_bitonicSortingTransposeCSKernelID, _Data, m_InstanceSortingData);
            m_SortingCommandBuffer.DispatchCompute(bitonicSortingCS, m_bitonicSortingTransposeCSKernelID, transposeGroupY, transposeGroupX, 1);

            m_SortingCommandBuffer.SetComputeBufferParam(bitonicSortingCS, m_bitonicSortingCSKernelID, _Data, m_InstanceSortingData);
            m_SortingCommandBuffer.DispatchCompute(bitonicSortingCS, m_bitonicSortingCSKernelID, sortGroupX, 1, 1);
        }
    }

    private void SetSortingConstants(CommandBuffer commandBuffer, ComputeShader compute, uint level, uint levelMask, uint width, uint height)
    {
        commandBuffer.SetComputeIntParam(compute, _Level, (int)level);
        commandBuffer.SetComputeIntParam(compute, _LevelMask, (int)levelMask);
        commandBuffer.SetComputeIntParam(compute, _MatrixWidth, (int)width);
        commandBuffer.SetComputeIntParam(compute, _MatrixHeight, (int)height);
    }

    private static void ReleaseCommandBuffer(ref CommandBuffer buffer) { if (buffer != null) { buffer.Release(); buffer = null; } }
    private static void ReleaseComputeBuffer(ref ComputeBuffer buffer) { if (buffer != null) { buffer.Release(); buffer = null; } }
    private static void ReleaseRendertexture(ref RenderTexture rt) { if (rt != null) { rt.Release(); rt = null; } }

    private C_VegetationLod[] ResetVegetationLodGroup(C_VegetationLod[] lodGroup)
    {
        C_VegetationLod[] result = new C_VegetationLod[NUMBER_OF_DRAW_CALLS];
        if (lodGroup == null || lodGroup.Length == 0) return result;
        int originalLodCount = lodGroup.Length;
        float lastValidViewRatio = 1.0f;
        for (int i = 0; i < NUMBER_OF_DRAW_CALLS; i++)
        {
            if (i < originalLodCount)
            {
                result[i] = lodGroup[i];
                if (lodGroup[i] != null) lastValidViewRatio = lodGroup[i]._ViewDisRatio;
            }
            else
            {
                C_VegetationLod lastLodTemplate = lodGroup[originalLodCount - 1];
                result[i] = new C_VegetationLod(lastLodTemplate._LodMesh, lastLodTemplate._LodMat, 0);
                float step = (float)(i - originalLodCount + 1) / (NUMBER_OF_DRAW_CALLS - originalLodCount + 1);
                result[i]._ViewDisRatio = Mathf.Lerp(lastValidViewRatio, 0, step);
            }
        }
        return result;
    }

    private C_IndirectRenderingMesh InitIndirectRenderingMesh(C_VegetationLod[] lodGroup)
    {
        C_IndirectRenderingMesh indirectMesh = new C_IndirectRenderingMesh();
        indirectMesh.meshes = new Mesh[NUMBER_OF_DRAW_CALLS];
        indirectMesh.material = new Material[NUMBER_OF_DRAW_CALLS];
        indirectMesh.lodMatPropBlock = new MaterialPropertyBlock[NUMBER_OF_DRAW_CALLS];
        indirectMesh.shadowLodMatPropBlock = new MaterialPropertyBlock[NUMBER_OF_DRAW_CALLS];
        for (int i = 0; i < NUMBER_OF_DRAW_CALLS; i++)
        {
            indirectMesh.meshes[i] = lodGroup[i]._LodMesh;
            indirectMesh.material[i] = new Material(lodGroup[i]._LodMat);
            indirectMesh.lodMatPropBlock[i] = new MaterialPropertyBlock();
            indirectMesh.shadowLodMatPropBlock[i] = new MaterialPropertyBlock();
        }
        return indirectMesh;
    }

    private int ExpandGroupSizeToPower2(int group)
    {
        int expandGroup = 1;
        while (expandGroup < group) expandGroup *= 2;
        return expandGroup;
    }

    private void ExpandSortingDataSizeToPower2(ref List<C_SortingData> data, int numofInstances, int drawCallNum, out int dataSize)
    {
        int originalSize = data.Count;
        int expandedSize = 2;
        while (expandedSize < originalSize) expandedSize *= 2;
        if (expandedSize < 2048) expandedSize = 2048;
        dataSize = expandedSize;
        int difference = expandedSize - originalSize;
        for (int i = 0; i < difference; i++)
        {
            data.Add(new C_SortingData()
            {
                drawCallInstanceIndex = (((uint)drawCallNum * NUMBER_OF_ARGS_PER_INSTANCE_TYPE) << 16) + ((uint)(numofInstances + i)),
                distanceToCam = 5000.0f
            });
        }
    }

    private int SizeSelected(int count)
    {
        if (count <= 4) return 2; if (count <= 16) return 4; if (count <= 64) return 8; if (count <= 256) return 16;
        if (count <= 1024) return 32; if (count <= 4096) return 64; if (count <= 16384) return 128; if (count <= 65536) return 256;
        if (count <= 262144) return 512; if (count <= 1048576) return 1024;
        return 2048;
    }

    private RenderTexture CreateRT(int count, RenderTextureFormat format, out int resolution, out RenderTexture shadowRT)
    {
        int size = SizeSelected(count);
        resolution = size;
        RenderTexture rt = new RenderTexture(size, size, 0, format) { enableRandomWrite = true, useMipMap = false, filterMode = FilterMode.Point };
        rt.Create();
        shadowRT = new RenderTexture(size, size, 0, format) { enableRandomWrite = true, useMipMap = false, filterMode = FilterMode.Point };
        shadowRT.Create();
        return rt;
    }

    #endregion


}