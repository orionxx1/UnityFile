using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using UnityEditor;
using UnityEngine;
using UnityEngine.Profiling; 


[ExecuteAlways]
public class InstanceDropController : MonoBehaviour
{
    [Header("Culling Options")]
    public bool isOn = true; // 总开关，可以一键启用/禁用整个系统
    public bool _FrustumCull_On = true;                         // 是否开启视锥剔除
    public bool _LodCull_On = true;                             // 是否开启LOD距离剔除
    public float _MaxDrawDistance = 100f; 

    [Header("Data")]
    public Terrain targetTerrain;                                // 拖入你要控制的Terrain
    public C_ChunkedTerrainVegetation vegData;                   // 将你用烘焙工具生成的 Vegetation Data asset 文件拖到这里
    public C_GPUDriverComputeShader _GPUDriverComputeShader;     // 将包含所有Compute Shader引用的 ScriptableObject 拖到这里

    // --- 私有成员变量 ---
    private InstanceDropRuntime prefabsRunTime; // 对核心渲染管线的引用
    private bool lastIsOn; // 用于检测 isOn 开关的变化

    // --- Unity生命周期方法 ---
    private void Update()
    {
        // 检测总开关的变化
        if (lastIsOn != isOn){
            lastIsOn = isOn;
            ControlTerrainDrawing(isOn);
            if (!isOn){
                Clear();    // 如果关闭了系统，清理所有资源
            }
        }

        // 使用Profiler API来包裹我们的渲染逻辑，方便在Profiler窗口中查看其性能消耗
        Profiler.BeginSample("GPUVegetationDraw");

        // 确保系统已开启，数据已提供，并且硬件支持所需功能
        if (isOn && vegData != null && SystemInfo.SupportsRenderTextureFormat(RenderTextureFormat.ARGBFloat)){
            ExecuteGPUCulling();    // 调用核心执行方法
        }

        Profiler.EndSample();
    }

    private void OnEnable()
    {
        // 当脚本启用时，立即根据当前 isOn 的状态更新一次Terrain的绘制状态
        lastIsOn = isOn;
        ControlTerrainDrawing(isOn);
    }

    void OnDisable()
    {
        if (targetTerrain != null){
            targetTerrain.drawTreesAndFoliage = true; // 恢复绘制
        }
        Clear();
    }

    // --- 核心逻辑方法 ---
    void ExecuteGPUCulling()
    {
        if (vegData == null)    return;     // 安全检查

        // 如果在打包后的游戏中，必须有主相机
#if !UNITY_EDITOR
        if (Camera.main == null)    return;
#endif        

        // 【初始化触发点】
        // 如果 prefabsRunTime 还未被创建，就 new 一个实例。
        // 这是整个系统最消耗性能的初始化步骤，只会在第一次执行时发生。
        if (prefabsRunTime == null)
        {
            if (vegData != null)
            {
#if UNITY_EDITOR       
                Camera cam = Camera.main;
                if (cam == null) cam = SceneView.lastActiveSceneView.camera; // 如果Game相机没内容就换成Scene相机
#else
                Camera cam = Camera.main;
#endif
                if (cam != null){
                    prefabsRunTime = new InstanceDropRuntime(vegData, _GPUDriverComputeShader, cam);
                }
            }
        }

        // 如果初始化成功，并且有植被数据
        if (prefabsRunTime != null)
        {
            if (vegData._AllInstanceTransforms != null && vegData._AllInstanceTransforms.Length > 0)
            {
                prefabsRunTime.SetCullingParameters(_FrustumCull_On, _LodCull_On, _MaxDrawDistance);
                prefabsRunTime.UpdateDraw();    // 【每帧驱动】调用核心的更新与绘制方法
            }
        }
    }


    private void ControlTerrainDrawing(bool useCustomRendering)
    {
        if (targetTerrain == null)  return;

        if (useCustomRendering){
            targetTerrain.drawTreesAndFoliage = false;
        }
        else{
            targetTerrain.drawTreesAndFoliage = true;
        }
    }


    void Clear()
    {
        if (prefabsRunTime != null){
            Debug.Log(" 清除植被渲染资源 ");
            prefabsRunTime.Release();
            prefabsRunTime = null; // 解除引用，让垃圾回收器回收
        }
    }

}


#region 数据结构

// 管理和传递整个 GPU 驱动管线所需的所有 Compute Shader ——————————
[Serializable]
[StructLayout(LayoutKind.Sequential)]
public struct C_GPUDriverComputeShader
{
    public ComputeShader calculateDataMatrixCompute;            // 负责初始化的矩阵计算
    public ComputeShader cullingCompute;                        // 负责每帧的剔除工作
    public ComputeShader scanVisInstancesCompute;               // 负责并行前缀和（扫描）的第一步和第二步
    public ComputeShader scanVisGroupSumCompute;                // ...
    public ComputeShader copyInstancesDataCompute;              // 负责流压缩，将可见实例数据拷贝到最终位置
    public ComputeShader copyInstanceIDOffsetMapCompute;        // 负责生成ID偏移图
    public ComputeShader bitonicSortingCS;                      // 负责异步排序
    public ComputeShader hiZGeneratorCompute;                   // 【新增】

};


// 原型渲染数据（每种实例对应一个）——————————
[System.Serializable]
public class C_IndirectRenderingMesh
{
    // 每个数据类型存储LOD对应的数据
    public Mesh[] meshes;                   // 网格
    public Material[] material;             // 材质
    public MaterialPropertyBlock[] lodMatPropBlock;         // 材质属性块
    public MaterialPropertyBlock[] shadowLodMatPropBlock;   // 阴影投射渲染的材质属性块
}


// 可见实例数据 ——————————
[StructLayout(LayoutKind.Sequential)]
public struct C_SortingData
{
    public uint drawCallInstanceIndex;      // 种类ID_高位区   实例ID_低位区
    public float distanceToCam;             // 实例于相机的距离
};


// 每种植被类型 对应的数据 ——————————
[System.Serializable]
public class C_VegetationPrefab
{
    public int _VegType;                            //0:common, 1:seagrass
    public uint _CastShadow;                        // 该类型是否投射阴影
    public C_VegetationLod[] _VegetationLodGroup;   // LOD相关数据类
    public C_VegetationTransform[] _ItemArray;      // 变换信息，位置、旋转欧拉值、缩放均值
    public Bounds _BlockVegetationBounds;
    private string m_runtimeMapID = string.Empty;

    public string RuntimeMapID{
        get { return m_runtimeMapID; }
    }

    public void RuntimeInit(){
        for (int i = 0; i < _VegetationLodGroup.Length; i++){
            m_runtimeMapID += _VegetationLodGroup[i]._LodMesh.GetInstanceID().ToString();
            m_runtimeMapID += _VegetationLodGroup[i]._LodMat.GetInstanceID().ToString();
        }
    }
}


// LOD相关数据类 ——————————
[System.Serializable]
public class C_VegetationLod
{
    public Mesh _LodMesh;       // 网格
    public Material _LodMat;    // 材质
    [Range(0, 1)] public float _ViewDisRatio;       // 屏幕高度占比
    [HideInInspector] public Bounds _LodBounds;     // 实例包围盒
    [HideInInspector] public MaterialPropertyBlock _LodMatPropBlock;    // 存储用于该LOD的 MaterialPropertyBlock

    public C_VegetationLod(Mesh mesh, Material mat, float dis){
        this._LodMesh = mesh;
        this._LodMat = mat;
        this._ViewDisRatio = dis;
    }

}


// 每个实例对应的变换信息 ——————————
[System.Serializable]
public struct C_VegetationTransform
{
    public Vector3 postion;     // 位置
    public Vector3 rotation;    // 旋转欧拉值
    public float scale;         // 缩放均值

    public C_VegetationTransform(TreeInstance instance, Transform childTransorm, Vector3 terrainSize, Vector3 terrainPos, float prefabScale)
    {
        Vector3 parentPos = new Vector3(instance.position.x * terrainSize.x, instance.position.y * terrainSize.y, instance.position.z * terrainSize.z) + terrainPos;
        Quaternion parentRot = Quaternion.Euler(new Vector3(0, Mathf.Rad2Deg * instance.rotation, 0));
        float parentScale = instance.heightScale * prefabScale;

        Vector3 offset = childTransorm.localPosition * parentScale;
        Vector3 childPos = parentPos + parentRot * offset;
        Quaternion childRot = parentRot.normalized * childTransorm.localRotation.normalized;
        this.postion = childPos;
        this.rotation = childRot.eulerAngles;
        this.scale = parentScale * childTransorm.localScale.x;
    }

    public C_VegetationTransform(TreeInstance instance, Vector3 terrainSize, Vector3 terrainPos)
    {
        this.postion = new Vector3(instance.position.x * terrainSize.x, instance.position.y * terrainSize.y, instance.position.z * terrainSize.z) + terrainPos;
        this.rotation = Vector3.zero;
        this.scale = 1;
    }
}


// 每个LOD 屏幕高度占比 ——————————
[StructLayout(LayoutKind.Sequential)]
public struct C_LodViewRatio
{
    public float lod0Range;
    public float lod1Range;
    public float lod2Range;
};


// 实例包围盒尺寸数据 ——————————
[StructLayout(LayoutKind.Sequential)]
public struct C_IndirectInstanceCSInput
{
    public Vector3 boundsCenter;    // 中心位置
    public Vector3 boundsExtents;   // 偏移向量
}

#endregion


#region 烘培数据结构

// 烘培输出数据结构
[System.Serializable]
public class C_ChunkedTerrainVegetation : ScriptableObject
{
    public List<C_VegetationPrefabInfo> _PrefabInfos;
    public List<C_VegetationChunk> _Chunks;
    public C_VegetationTransform[] _AllInstanceTransforms;
    public int[] _AllInstancePrefabTypeIDs;
}


// 原型静态信息
[System.Serializable]
public class C_VegetationPrefabInfo
{
    public uint _CastShadow = 1;                    // 默认投射阴影
    public C_VegetationLod[] _VegetationLodGroup;   // LOD信息数组
    public Bounds _LodBounds;                       // 原型所有LOD网格的联合局部包围盒
}


// 区块数据
[System.Serializable]
public class C_VegetationChunk
{
    public Bounds _Bounds;      // 包围盒
    public uint _StartIndex;    // 起始实例ID
    public uint _Count;         // 存储实例数量
}


// 区块 存储实例的数据
[System.Serializable]
[StructLayout(LayoutKind.Sequential)] 
public struct C_GpuChunkInfo
{
    public uint startIndex;     // 实例开端索引
    public uint count;          // 数量

    public C_GpuChunkInfo(uint start, uint count)
    {
        this.startIndex = start; // 使用 this 明确指向字段
        this.count = count;      // 使用 this 明确指向字段
    }
}

#endregion



/* DrawMeshInstancedIndirect 和  m_InstancesArgsBuffer的定义
public static void DrawMeshInstancedIndirect(
    Mesh mesh,
    int submeshIndex,
    Material material,
    Bounds bounds,
    ComputeBuffer bufferWithArgs,               // 这是我们的 m_InstancesArgsBuffer
    int argsOffset = 0,                         // 这是关键参数！
    MaterialPropertyBlock properties = null,
    ShadowCastingMode castShadows = ShadowCastingMode.On,
    bool receiveShadows = true,
    int layer = 0,
    Camera camera = null
);


struct m_InstancesArgsBuffer
{
    uint vertexCountPerInstance;    // 1. 每个实例的顶点数 (由Mesh提供)
    uint instanceCount;             // 2. 要绘制的实例数量 (由剔除CS计算)
    uint startVertexLocation;       // 3. 起始顶点位置 (通常为0)
    uint startInstanceLocation;     // 4. 起始实例位置 (由压缩CS计算)
    uint baseVertexLocation;        // 5. 基础顶点位置 (通常为0)
};
*/