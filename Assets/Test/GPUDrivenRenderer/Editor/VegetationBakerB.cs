using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;
using UnityEngine.Animations.Rigging;
public class TerrainVegetationBaker_Chunked : EditorWindow
{
    #region 窗口管理和UI绘制


    // --- 静态方法，用于在Unity菜单中创建窗口 ---
    [MenuItem("Tools/GPU Driven/Terrain Vegetation Baker (Chunked)")]
    public static void ShowWindow()
    {
        // 获取或创建一个新的编辑器窗口实例
        GetWindow<TerrainVegetationBaker_Chunked>("Terrain Veg Baker (Chunked)");
    }

    // --- UI状态变量 ---
    private Terrain targetTerrain;      // 用户拖入的目标地形
    private Vector2 scrollPos;          // 用于滚动视图

    // [SerializeField]
    // private float chunkSize = 4f;          // 分块大小的UI变量

    // 【新增】自适应分块的UI参数
    [SerializeField]
    private int maxInstancesPerChunk = 256;
    [SerializeField]
    private float minChunkSize = 8f;

    private string savePath;                                                // 【修改】移除硬编码的默认路径，改为在启用时加载
    private string fileName = "BakedVegetationData";                        // 【新增】用于自定义文件名的变量
    private const string BakerSavePathKey = "TerrainVegBaker_SavePath";     // 【新增】用于存储 EditorPrefs Key 的常量


    //新增 临时数据结构，用于构建区块
    private class ChunkBuilder
    {
        public Bounds Bounds;
        // 存储实例的变换信息和其对应的原型ID
        public List<(C_VegetationTransform transform, int prefabTypeID)> Instances = new List<(C_VegetationTransform, int)>();
        private bool isInitialized = false;

        // 辅助方法，用于安全地扩展包围盒
        public void Encapsulate(Bounds bounds)
        {
            if (!isInitialized)
            {
                Bounds = bounds;
                isInitialized = true;
            }
            else
            {
                Bounds.Encapsulate(bounds);
            }
        }
    }


    // --- 数据结构，用于在UI中存储每个地形原型的配置 ---
    private class PrototypeLODConfig
    {
        public bool shouldBake = true; // 是否烘焙这个原型
        public List<C_VegetationLod> lods = new List<C_VegetationLod>() { new C_VegetationLod(null, null, 0.5f) }; // LOD配置列表
    }

    // 存储树原型的LOD配置
    private List<PrototypeLODConfig> treePrototypeConfigs = new List<PrototypeLODConfig>();



    // 【新增】当窗口启用时调用，用于加载上次的路径
    private void OnEnable()
    {
        // 从 EditorPrefs 加载上次保存的路径，如果不存在，则提供一个默认值
        savePath = EditorPrefs.GetString(BakerSavePathKey, "Assets/GPUDrivenRenderer/BakedVegetation");
    }



    // --- 编辑器窗口的GUI渲染方法 ---
    private void OnGUI()
    {
        scrollPos = EditorGUILayout.BeginScrollView(scrollPos);

        EditorGUILayout.LabelField("1. 选择目标地形", EditorStyles.boldLabel);

        // 监视targetTerrain字段的变化
        EditorGUI.BeginChangeCheck();
        targetTerrain = (Terrain)EditorGUILayout.ObjectField("Target Terrain", targetTerrain, typeof(Terrain), true);

        // 如果用户选择了新的地形
        if (EditorGUI.EndChangeCheck())
        {
            // 更新UI以显示新地形的植被原型信息
            UpdatePrototypeConfigs();
        }

        // 只有在选择了地形后，才显示后续配置项
        if (targetTerrain != null)
        {
            EditorGUILayout.Space(10);
            EditorGUILayout.LabelField("2. 配置植被原型", EditorStyles.boldLabel);
            DrawTreePrototypesGUI();

            EditorGUILayout.Space(20);
            EditorGUILayout.LabelField("3. Chunking Options", EditorStyles.boldLabel);
            // chunkSize = EditorGUILayout.FloatField("Chunk Size (meters)", chunkSize);
            maxInstancesPerChunk = EditorGUILayout.IntField(new GUIContent(
                "Max Instances Per Chunk", "每个区块能容纳的最大实例数。值越小，密集区的区块就越小。"), 
                maxInstancesPerChunk);
            minChunkSize = EditorGUILayout.FloatField(new GUIContent(
                "Min Chunk Size (meters)", "区块允许的最小尺寸，防止无限分裂。"), 
                minChunkSize);


            EditorGUILayout.Space(20);
            EditorGUILayout.LabelField("4. 执行烘焙", EditorStyles.boldLabel);

            // --- 路径选择 ---
            EditorGUILayout.BeginHorizontal();
            // 监视路径文本框的变化
            EditorGUI.BeginChangeCheck();
            savePath = EditorGUILayout.TextField("Save Folder", savePath);
            // 如果路径被用户手动修改，也保存它
            if (EditorGUI.EndChangeCheck())
            {
                EditorPrefs.SetString(BakerSavePathKey, savePath);
            }
            // 添加一个浏览文件夹的按钮
            if (GUILayout.Button("Browse...", GUILayout.Width(80)))
            {
                string selectedPath = EditorUtility.OpenFolderPanel("Select Save Folder", savePath, "");
                // 检查用户是否选择了路径且路径在Assets文件夹内
                if (!string.IsNullOrEmpty(selectedPath) && selectedPath.StartsWith(Application.dataPath))
                {
                    // 将绝对路径转换为相对于 "Assets/" 的相对路径
                    savePath = "Assets" + selectedPath.Substring(Application.dataPath.Length);
                    EditorPrefs.SetString(BakerSavePathKey, savePath); // 保存新路径
                }
            }
            EditorGUILayout.EndHorizontal();

            // --- 【新增】文件名输入框 ---
            fileName = EditorGUILayout.TextField("File Name", fileName);


            if (GUILayout.Button("Bake Terrain Vegetation"))
            {
                BakeChunked(); // 调用核心烘焙逻辑
            }
        }
        else
        {
            EditorGUILayout.HelpBox("请拖入一个场景中的Terrain对象以开始。", MessageType.Info);
        }

        EditorGUILayout.EndScrollView();
    }

    // --- 当地形改变时，更新原型配置列表 ---
    private void UpdatePrototypeConfigs()
    {
        treePrototypeConfigs.Clear();
        if (targetTerrain == null) return;

        // 遍历地形数据中定义的所有树原型
        foreach (var treeProto in targetTerrain.terrainData.treePrototypes)
        {
            // 每次循环都创建一个全新的配置对象
            var config = new PrototypeLODConfig();
            // 【关键修正】先清空默认创建的LOD，我们接下来会重新、可靠地填充它
            config.lods.Clear();

            var prefab = treeProto.prefab;
            if (prefab != null)
            {
                var lodGroup = prefab.GetComponent<LODGroup>();

                // --- 分支1: 预制件有LODGroup组件 ---
                if (lodGroup != null && lodGroup.GetLODs().Length > 0)
                {
                    var lods = lodGroup.GetLODs();
                    foreach (var lod in lods)
                    {
                        // 尝试从LOD的第一个renderer获取Mesh和Material
                        Mesh lodMesh = null;
                        Material lodMat = null;

                        if (lod.renderers != null && lod.renderers.Length > 0 && lod.renderers[0] != null)
                        {
                            var renderer = lod.renderers[0];
                            var meshFilter = renderer.GetComponent<MeshFilter>();
                            if (meshFilter != null)
                            {
                                lodMesh = meshFilter.sharedMesh;
                            }
                            lodMat = renderer.sharedMaterial;
                        }

                        // 无论是否成功获取，都添加一个LOD配置项，
                        // 这样即使用户的LODGroup配置有误，UI上也能显示出来让他修复
                        config.lods.Add(new C_VegetationLod(
                            lodMesh,
                            lodMat,
                            lod.screenRelativeTransitionHeight
                        ));
                    }
                }
                // --- 分支2: 预制件没有LODGroup组件 ---
                else
                {
                    // 尝试从预制件根节点获取
                    Mesh rootMesh = null;
                    Material rootMat = null;
                    var renderer = prefab.GetComponent<Renderer>();
                    if (renderer != null)
                    {
                        var meshFilter = renderer.GetComponent<MeshFilter>();
                        if (meshFilter != null)
                        {
                            rootMesh = meshFilter.sharedMesh;
                        }
                        rootMat = renderer.sharedMaterial;
                    }
                    // 添加一个代表LOD0的配置项
                    config.lods.Add(new C_VegetationLod(rootMesh, rootMat, 0.5f));
                }
            }

            // --- 【最终保障】---
            // 在所有逻辑结束后，如果lods列表因为任何原因（如prefab为null）还是空的，
            // 我们必须保证它至少有一个元素，否则UI和后续逻辑会出错。
            if (config.lods.Count == 0)
            {
                config.lods.Add(new C_VegetationLod(null, null, 0.5f));
            }

            treePrototypeConfigs.Add(config);
        }
    }

    // --- 绘制所有树原型的配置UI ---
    private void DrawTreePrototypesGUI()
    {
        if (targetTerrain == null || targetTerrain.terrainData.treePrototypes.Length == 0)
        {
            EditorGUILayout.HelpBox("此地形没有配置任何树原型。", MessageType.None);
            return;
        }

        EditorGUILayout.LabelField("树 (Trees)", EditorStyles.boldLabel);
        for (int i = 0; i < targetTerrain.terrainData.treePrototypes.Length; i++)
        {
            var proto = targetTerrain.terrainData.treePrototypes[i];
            var config = treePrototypeConfigs[i];

            EditorGUILayout.BeginVertical(EditorStyles.helpBox);

            // 使用ToggleLeft，并显示预制件的预览图，更直观
            string protoName = proto.prefab ? proto.prefab.name : $"Tree {i} (No Prefab)";
            config.shouldBake = EditorGUILayout.ToggleLeft(new GUIContent(protoName, AssetPreview.GetAssetPreview(proto.prefab)), config.shouldBake, EditorStyles.boldLabel);

            // 如果勾选了烘焙，才显示详细配置
            if (config.shouldBake)
            {
                EditorGUI.indentLevel++;
                for (int j = 0; j < config.lods.Count; j++)
                {
                    EditorGUILayout.LabelField($"LOD {j}", EditorStyles.miniBoldLabel);
                    config.lods[j]._LodMesh = (Mesh)EditorGUILayout.ObjectField("Mesh", config.lods[j]._LodMesh, typeof(Mesh), false);
                    config.lods[j]._LodMat = (Material)EditorGUILayout.ObjectField("Material", config.lods[j]._LodMat, typeof(Material), false);

                    // 最后一个LOD代表剔除距离，其View Ratio固定为0
                    if (j == config.lods.Count - 1)
                    {
                        EditorGUILayout.LabelField("View Ratio: 0 (Culling Distance)", EditorStyles.miniLabel);
                        config.lods[j]._ViewDisRatio = 0.0f;
                    }
                    else
                    {
                        config.lods[j]._ViewDisRatio = EditorGUILayout.Slider("View Ratio", config.lods[j]._ViewDisRatio, 0.0f, 1.0f);
                    }
                }
                // 添加/删除LOD层级的按钮
                EditorGUILayout.BeginHorizontal();
                if (GUILayout.Button("Add LOD", EditorStyles.miniButtonLeft)) { config.lods.Add(new C_VegetationLod(null, null, 0.1f)); }
                if (config.lods.Count > 1 && GUILayout.Button("Remove LOD", EditorStyles.miniButtonRight)) { config.lods.RemoveAt(config.lods.Count - 1); }
                EditorGUILayout.EndHorizontal();
                EditorGUI.indentLevel--;
            }

            EditorGUILayout.EndVertical();
        }
    }

    #endregion


    #region 烘焙方法
    // --- 核心烘焙方法 ---

    // --- 【替换】用下面的代码完整替换掉你旧的 BakeChunked 方法 ---
    private void BakeChunked()
    {
        // 1. 数据和参数验证
        if (!ValidateAllPrototypes()) return;
        if (maxInstancesPerChunk <= 0)
        {
            EditorUtility.DisplayDialog("Error", "Max Instances Per Chunk must be greater than 0.", "OK");
            return;
        }
        if (minChunkSize <= 0)
        {
            EditorUtility.DisplayDialog("Error", "Min Chunk Size must be greater than 0.", "OK");
            return;
        }
        // (此处可以添加您自己的文件名和路径验证逻辑)
        // ...

        Debug.Log("Step 1: Pre-processing all terrain instances...");

        var terrainData = targetTerrain.terrainData;
        var terrainPos = targetTerrain.transform.position;
        var terrainSize = terrainData.size;

        // 2. 预处理所有实例，计算它们的世界坐标和总包围盒
        var allInstancePoints = new List<InstancePoint>(terrainData.treeInstanceCount);
        var totalBounds = new Bounds();
        bool firstInstance = true;

        for (int i = 0; i < terrainData.treeInstanceCount; i++)
        {
            var instance = terrainData.treeInstances[i];

            // 只处理需要烘焙的原型
            if (instance.prototypeIndex >= treePrototypeConfigs.Count || !treePrototypeConfigs[instance.prototypeIndex].shouldBake)
            {
                continue;
            }

            // 计算实例的世界坐标 (只用于空间划分)
            Vector3 instanceWorldPos = new Vector3(
                instance.position.x * terrainSize.x,
                instance.position.y * terrainSize.y,
                instance.position.z * terrainSize.z
            ) + terrainPos;

            allInstancePoints.Add(new InstancePoint { Position = instanceWorldPos, OriginalIndex = i });

            // 扩展总包围盒
            if (firstInstance)
            {
                totalBounds = new Bounds(instanceWorldPos, Vector3.zero);
                firstInstance = false;
            }
            else
            {
                totalBounds.Encapsulate(instanceWorldPos);
            }
        }

        if (allInstancePoints.Count == 0)
        {
            EditorUtility.DisplayDialog("Info", "No bakeable instances found on the terrain.", "OK");
            return;
        }

        // 3. 递归构建四叉树来划分区块
        Debug.Log("Step 2: Building Quadtree for adaptive chunking...");
        // 【修改】================================================================
        //  创建一个能包围 totalBounds 的、最小的正方形根节点
        // ========================================================================
        // a. 找出最长的边 (X 或 Z)
        float maxSideLength = Mathf.Max(totalBounds.size.x, totalBounds.size.z);

        // b. 基于最长边，创建一个新的正方形尺寸
        Vector3 squareSize = new Vector3(maxSideLength, totalBounds.size.y, maxSideLength);

        // c. 使用 totalBounds 的中心和新的正方形尺寸来创建根节点的包围盒
        Bounds rootBounds = new Bounds(totalBounds.center, squareSize);

        // d. 使用这个正方形的 rootBounds 来创建根节点
        var rootNode = new QuadtreeNode { Bounds = rootBounds };
        // ========================================================================


        // 【修改】初次调用时，传入包含所有实例的列表 allInstancePoints
        BuildQuadtree(rootNode, allInstancePoints);

        // 4. 从四叉树中提取所有叶子节点作为最终的区块
        Debug.Log("Step 3: Extracting leaf nodes as final chunks...");
        var finalChunks = new List<QuadtreeNode>();
        var nodeStack = new Stack<QuadtreeNode>();
        nodeStack.Push(rootNode);

        while (nodeStack.Count > 0)
        {
            var currentNode = nodeStack.Pop();

            if (currentNode.Children == null) // 如果是叶子节点
            {
                if (currentNode.InstanceIndices.Count > 0) // 只添加包含实例的叶子节点
                {
                    finalChunks.Add(currentNode);
                }
            }
            else // 如果是父节点, 将子节点压入栈
            {
                for (int i = 0; i < 4; i++)
                {
                    if (currentNode.Children[i] != null)
                    {
                        nodeStack.Push(currentNode.Children[i]);
                    }
                }
            }
        }

        Debug.Log($"Found {finalChunks.Count} adaptive chunks.");

        // 5. 创建并填充最终的 ScriptableObject
        Debug.Log("Step 4: Aggregating data and creating asset...");
        var asset = ScriptableObject.CreateInstance<C_ChunkedTerrainVegetation>();

        // a. 填充原型信息 (_PrefabInfos)
        asset._PrefabInfos = new List<C_VegetationPrefabInfo>();
        for (int i = 0; i < treePrototypeConfigs.Count; i++)
        {
            var config = treePrototypeConfigs[i];
            Bounds prefabLocalBounds = CalculatePrefabLocalBounds(config);
            asset._PrefabInfos.Add(new C_VegetationPrefabInfo
            {
                _VegetationLodGroup = config.lods.ToArray(),
                _LodBounds = prefabLocalBounds
            });
        }

        // b. 扁平化数据，聚合实例并填充区块元数据
        var allTransforms = new List<C_VegetationTransform>();
        var allTypeIDs = new List<int>();
        asset._Chunks = new List<C_VegetationChunk>();

        // 【重要】创建一个从原始实例索引到新实例索引的映射
        var originalToNewIndexMap = new Dictionary<int, int>();
        int newIndexCounter = 0;

        // 按区块顺序，聚合所有实例数据
        foreach (var chunkNode in finalChunks)
        {
            foreach (int originalIndex in chunkNode.InstanceIndices)
            {
                if (!originalToNewIndexMap.ContainsKey(originalIndex))
                {
                    originalToNewIndexMap[originalIndex] = newIndexCounter;

                    var instance = terrainData.treeInstances[originalIndex];
                    C_VegetationTransform vegTransform = CalculateVegetationTransform(instance, instance.prototypeIndex);
                    allTransforms.Add(vegTransform);
                    allTypeIDs.Add(instance.prototypeIndex);

                    newIndexCounter++;
                }
            }
        }

        // 再次遍历区块，这次是为了构建 C_VegetationChunk
        uint currentStartIndex = 0;
        foreach (var chunkNode in finalChunks)
        {
            if (chunkNode.InstanceIndices.Count == 0) continue;

            uint instanceCountInChunk = (uint)chunkNode.InstanceIndices.Count;

            // 计算区块精确的3D包围盒
            Bounds chunk3DBounds = new Bounds();
            bool firstInChunk = true;
            foreach (int originalIndex in chunkNode.InstanceIndices)
            {
                int newIndex = originalToNewIndexMap[originalIndex];
                Bounds instanceWorldBounds = CalculateInstanceWorldBounds(allTransforms[newIndex], allTypeIDs[newIndex]);
                if (firstInChunk)
                {
                    chunk3DBounds = instanceWorldBounds;
                    firstInChunk = false;
                }
                else
                {
                    chunk3DBounds.Encapsulate(instanceWorldBounds);
                }
            }

            asset._Chunks.Add(new C_VegetationChunk
            {
                _Bounds = chunk3DBounds,
                _StartIndex = currentStartIndex,
                _Count = instanceCountInChunk
            });

            currentStartIndex += instanceCountInChunk;
        }

        // 由于实例顺序可能因字典处理而改变，我们需要根据区块重新排序
        var sortedTransforms = new C_VegetationTransform[allTransforms.Count];
        var sortedTypeIDs = new int[allTypeIDs.Count];
        foreach (var chunk in asset._Chunks)
        {
            // 这里的逻辑需要重新审视，确保实例顺序与区块定义一致。
            // 一个更简单的方法是：直接在遍历finalChunks时构建最终数组。
        }

        // --- 【聚合逻辑】---
        allTransforms.Clear();
        allTypeIDs.Clear();
        asset._Chunks.Clear();

        uint runningIndex = 0;
        foreach (var chunkNode in finalChunks)
        {
            if (chunkNode.InstanceIndices.Count == 0) continue;

            Bounds chunk3DBounds = new Bounds();
            bool firstInChunk = true;
            uint startIndexForThisChunk = runningIndex;

            foreach (int originalIndex in chunkNode.InstanceIndices)
            {
                var instance = terrainData.treeInstances[originalIndex];
                var vegTransform = CalculateVegetationTransform(instance, instance.prototypeIndex);
                allTransforms.Add(vegTransform);
                allTypeIDs.Add(instance.prototypeIndex);

                Bounds instanceWorldBounds = CalculateInstanceWorldBounds(vegTransform, instance.prototypeIndex);
                if (firstInChunk) { chunk3DBounds = instanceWorldBounds; firstInChunk = false; }
                else { chunk3DBounds.Encapsulate(instanceWorldBounds); }
            }

            asset._Chunks.Add(new C_VegetationChunk
            {
                _Bounds = chunk3DBounds,
                _StartIndex = startIndexForThisChunk,
                _Count = (uint)chunkNode.InstanceIndices.Count
            });
            runningIndex += (uint)chunkNode.InstanceIndices.Count;
        }


        asset._AllInstanceTransforms = allTransforms.ToArray();
        asset._AllInstancePrefabTypeIDs = allTypeIDs.ToArray();
        Debug.Log($"Step 5: Baking complete. Total instances: {asset._AllInstanceTransforms.Length}, Total chunks: {asset._Chunks.Count}");

        // 6. 保存资产 (使用您之前优化的带覆盖确认的逻辑)
        if (!Directory.Exists(savePath)) Directory.CreateDirectory(savePath);
        string finalPath = $"{savePath}/{fileName}.asset";

        if (File.Exists(finalPath))
        {
            if (!EditorUtility.DisplayDialog("File Exists", $"The file '{fileName}.asset' already exists.\nDo you want to overwrite it?", "Overwrite", "Cancel"))
            {
                Debug.Log("Baking cancelled by user.");
                return;
            }
        }

        AssetDatabase.CreateAsset(asset, finalPath);
        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();

        EditorUtility.DisplayDialog("Success", $"Chunked vegetation baked successfully to:\n{finalPath}", "OK");
        Selection.activeObject = asset;
    }

    // 四叉树递归构建函数
    private void BuildQuadtree(QuadtreeNode node, List<InstancePoint> parentInstances)
    {
        // 1. 将父节点列表中的实例分配到当前节点
        foreach (var p in parentInstances)
        {
            if (node.Bounds.Contains(p.Position))
            {
                node.InstanceIndices.Add(p.OriginalIndex);
            }
        }

        // 2. 检查是否需要分裂 (递归的终止条件)
        if (node.InstanceIndices.Count <= maxInstancesPerChunk || node.Bounds.size.x <= minChunkSize)
        {
            return; // 成为叶子节点
        }

        // 3. 执行分裂
        Vector3 center = node.Bounds.center;
        Vector3 childHalfSize = node.Bounds.size * 0.25f; // size is diameter, so half is size * 0.5, quarter is size * 0.25
        Vector3 childSize = new Vector3(node.Bounds.size.x * 0.5f, node.Bounds.size.y, node.Bounds.size.z * 0.5f);

        node.Children = new QuadtreeNode[4];
        // Top-Right [0], Top-Left [1], Bottom-Left [2], Bottom-Right [3]
        node.Children[0] = new QuadtreeNode { Bounds = new Bounds(new Vector3(center.x + childHalfSize.x, center.y, center.z + childHalfSize.z), childSize) };
        node.Children[1] = new QuadtreeNode { Bounds = new Bounds(new Vector3(center.x - childHalfSize.x, center.y, center.z + childHalfSize.z), childSize) };
        node.Children[2] = new QuadtreeNode { Bounds = new Bounds(new Vector3(center.x - childHalfSize.x, center.y, center.z - childHalfSize.z), childSize) };
        node.Children[3] = new QuadtreeNode { Bounds = new Bounds(new Vector3(center.x + childHalfSize.x, center.y, center.z - childHalfSize.z), childSize) };

        // 4. 将本节点的实例“传递”给子节点进行递归构建
        var instancesInThisNode = new List<InstancePoint>();
        foreach (var index in node.InstanceIndices)
        {
            // 这是一个潜在的性能瓶颈，理想情况是直接使用 allInstancePoints 的引用
            // 为了简单，我们先这样实现
            var treeInstance = targetTerrain.terrainData.treeInstances[index];
            Vector3 pos = new Vector3(treeInstance.position.x * targetTerrain.terrainData.size.x, treeInstance.position.y * targetTerrain.terrainData.size.y, treeInstance.position.z * targetTerrain.terrainData.size.z) + targetTerrain.transform.position;
            instancesInThisNode.Add(new InstancePoint { Position = pos, OriginalIndex = index });
        }

        foreach (var child in node.Children)
        {
            BuildQuadtree(child, instancesInThisNode);
        }

        // 分裂后，父节点不再是叶子节点，清空其实例列表
        node.InstanceIndices.Clear();
    }

    #endregion


    #region 辅助方法

    // 辅助方法1：计算单个实例的精确变换
    private C_VegetationTransform CalculateVegetationTransform(TreeInstance instance, int prototypeIndex)
    {
        var treeProto = targetTerrain.terrainData.treePrototypes[prototypeIndex];
        var terrainSize = targetTerrain.terrainData.size;
        var terrainPos = targetTerrain.transform.position;
    
        var lodGroup = treeProto.prefab.GetComponent<LODGroup>();
        bool hasComplexPrefab = lodGroup != null;
    
        if (hasComplexPrefab)
        {
            var lods = lodGroup.GetLODs();
            Transform childTransform = (lods.Length > 0 && lods[0].renderers.Length > 0 && lods[0].renderers[0] != null) ? lods[0].renderers[0].transform : null;
    
            if (childTransform != null)
                return new C_VegetationTransform(instance, childTransform, terrainSize, terrainPos, 1.0f);
            else
                return new C_VegetationTransform(instance, terrainSize, terrainPos);
        }
        else
        {
            return new C_VegetationTransform(instance, terrainSize, terrainPos);
        }
    }
    
    // 辅助方法2：计算单个原型的局部包围盒
    private Bounds CalculatePrefabLocalBounds(PrototypeLODConfig config)
    {
        Bounds localPrefabBounds = new Bounds();
        bool firstLodMesh = true;
        foreach (var lodConfig in config.lods)
        {
            if (lodConfig._LodMesh != null)
            {
                if (firstLodMesh)
                {
                    localPrefabBounds = lodConfig._LodMesh.bounds;
                    firstLodMesh = false;
                }
                else
                {
                    localPrefabBounds.Encapsulate(lodConfig._LodMesh.bounds);
                }
            }
        }
        return localPrefabBounds;
    }
    
    // 辅助方法3：计算单个实例的世界包围盒
    private Bounds CalculateInstanceWorldBounds(C_VegetationTransform vegTransform, int prototypeIndex)
    {
        var config = treePrototypeConfigs[prototypeIndex];
        Bounds localPrefabBounds = CalculatePrefabLocalBounds(config);
    
        Vector3 worldPos = vegTransform.postion;
        float worldScale = vegTransform.scale;
    
        Vector3 worldBoundsSize = Vector3.Scale(localPrefabBounds.size, new Vector3(worldScale, worldScale, worldScale));
        Vector3 worldBoundsCenter = worldPos + localPrefabBounds.center * worldScale;
    
        return new Bounds(worldBoundsCenter, worldBoundsSize);
    }
    

    // 辅助方法4: 烘焙前的数据验证 (从旧的Bake()方法中提取)
    private bool ValidateAllPrototypes()
    {
        for (int i = 0; i < treePrototypeConfigs.Count; i++)
        {
            var config = treePrototypeConfigs[i];
            if (!config.shouldBake) continue;
    
            string protoName = targetTerrain.terrainData.treePrototypes[i].prefab?.name ?? $"Prototype {i}";
    
            if (config.lods == null || config.lods.Count == 0) { /* ... 错误提示 ... */ return false; }
    
            for (int j = 0; j < config.lods.Count; j++)
            {
                var lod = config.lods[j];
                if (lod._LodMesh == null) { /* ... 错误提示 ... */ return false; }
                if (lod._LodMat == null) { /* ... 错误提示 ... */ return false; }
            }
        }
        return true;
    }


    // 【新增】四叉树节点类
    private class QuadtreeNode
    {
        public Bounds Bounds; // 节点的2D包围盒 (y值可以忽略或设为固定)
        public List<int> InstanceIndices = new List<int>(); // 存储落入此节点的实例的索引
        public QuadtreeNode[] Children = null; // 四个子节点
    }

    // 【新增】用于四叉树构建的临时数据结构
    // 存储实例的位置和它在原始数组中的索引，便于后续查找
    private struct InstancePoint
    {
        public Vector3 Position;
        public int OriginalIndex;
    }



    private void BuildQuadtree(QuadtreeNode node, List<InstancePoint> allInstances, int maxInstances, float minSize)
    {
        // 1. 将所有实例分配到当前节点
        foreach (var instance in allInstances)
        {
            if (node.Bounds.Contains(instance.Position))
            {
                node.InstanceIndices.Add(instance.OriginalIndex);
            }
        }

        // 2. 检查是否需要分裂 (递归的终止条件)
        if (node.InstanceIndices.Count <= maxInstances || node.Bounds.size.x <= minSize)
        {
            // 如果实例数量达标，或尺寸已到最小，则不再分裂，该节点成为一个叶子节点
            return;
        }

        // 3. 执行分裂
        Vector3 center = node.Bounds.center;
        Vector3 halfSize = node.Bounds.size * 0.5f;
        Vector3 childSize = new Vector3(halfSize.x, node.Bounds.size.y, halfSize.z);

        node.Children = new QuadtreeNode[4];

        // 创建四个子节点
        // Top-Right
        node.Children[0] = new QuadtreeNode { Bounds = new Bounds(new Vector3(center.x + halfSize.x / 2, center.y, center.z + halfSize.z / 2), childSize) };
        // Top-Left
        node.Children[1] = new QuadtreeNode { Bounds = new Bounds(new Vector3(center.x - halfSize.x / 2, center.y, center.z + halfSize.z / 2), childSize) };
        // Bottom-Left
        node.Children[2] = new QuadtreeNode { Bounds = new Bounds(new Vector3(center.x - halfSize.x / 2, center.y, center.z - halfSize.z / 2), childSize) };
        // Bottom-Right
        node.Children[3] = new QuadtreeNode { Bounds = new Bounds(new Vector3(center.x + halfSize.x / 2, center.y, center.z - halfSize.z / 2), childSize) };

        // 4. 将本节点的实例“传递”给子节点进行递归构建
        // 为了效率，只把当前节点的实例列表传下去，而不是全部实例
        var instancesInThisNode = node.InstanceIndices.Select(i => allInstances[i]).ToList();

        foreach (var child in node.Children)
        {
            BuildQuadtree(child, instancesInThisNode, maxInstances, minSize);
        }

        // 【重要】分裂后，父节点自身的实例列表可以清空，因为它已经不是叶子节点了
        node.InstanceIndices.Clear();
    }

    #endregion

}

