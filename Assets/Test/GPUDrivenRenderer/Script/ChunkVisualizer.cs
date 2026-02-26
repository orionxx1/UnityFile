// 文件名: ChunkVisualizer.cs
// 作用: 在Unity编辑器中，使用Gizmos功能来可视化已烘焙的植被区块。

using UnityEngine;

// 使用 [ExecuteInEditMode] 或 [ExecuteAlways] 让脚本在编辑器模式下也能运行 OnDrawGizmos
[ExecuteAlways]
public class ChunkVisualizer : MonoBehaviour
{
    [Header("Data Source")]
    [Tooltip("将您烘焙好的 C_ChunkedTerrainVegetation 数据资产文件拖拽到这里")]
    public C_ChunkedTerrainVegetation vegetationData;

    [Header("Visualization Settings")]
    [Tooltip("是否显示区块的可视化线框")]
    public bool showChunks = true;

    [Tooltip("区块线框的颜色")]
    public Color chunkColor = new Color(1.0f, 0.92f, 0.016f, 0.8f); // 经典的黄色

    [Tooltip("是否为每个区块显示其包含的实例数量")]
    public bool showInstanceCount = false;

#if UNITY_EDITOR
    // OnDrawGizmos 是 Unity 的一个特殊方法，用于在 Scene 视图中绘制调试信息。
    // 它只在编辑器中被调用。
    private void OnDrawGizmos()
    {
        // 如果开关关闭或没有数据，则不执行任何操作
        if (!showChunks || vegetationData == null || vegetationData._Chunks == null)
        {
            return;
        }

        // --- 绘制所有区块的包围盒 ---
        // 设置 Gizmos 的颜色
        Gizmos.color = chunkColor;

        // 遍历数据资产中的所有区块
        foreach (var chunk in vegetationData._Chunks)
        {
            // Gizmos.DrawWireCube 会根据给定的中心点和尺寸绘制一个线框立方体
            Gizmos.DrawWireCube(chunk._Bounds.center, chunk._Bounds.size);
        }

        // --- (可选) 绘制实例数量文本 ---
        if (showInstanceCount)
        {
            // 为文本设置一个不同的颜色，以便区分
            UnityEditor.Handles.color = Color.white;

            foreach (var chunk in vegetationData._Chunks)
            {
                // 使用 UnityEditor.Handles.Label 在每个区块的中心位置绘制一个文本标签
                // 显示该区块的实例数量
                UnityEditor.Handles.Label(chunk._Bounds.center, $"Count: {chunk._Count}");
            }
        } 
    }
#endif
}