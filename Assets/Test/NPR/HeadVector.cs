using UnityEngine;                       //引入 Unity 的核心命名空间
using System.Collections.Generic;

[ExecuteAlways] // 让脚本在编辑器下也运行
public class HeadVector : MonoBehaviour
{
    [SerializeField] private Transform headBone;    // 要设置为头部骨骼的 Transform

    // 提前缓存 Shader 属性 ID，提高效率
    private static readonly int FaceForwardID = Shader.PropertyToID("_FaceForward");
    private static readonly int FaceRightID = Shader.PropertyToID("_FaceRight");


    void Update()       //每帧运行
    {
        if (headBone == null) return;       //如果没有设置 headBone，就跳过这帧

        // 获取当前物体及其所有子物体中的 Renderer（包括 SkinnedMeshRenderer 和 MeshRenderer）
        var renderers = GetComponentsInChildren<Renderer>();
        foreach (var renderer in renderers)
        {
            // 遍历 Renderer 的 sharedMaterials（避免运行时实例化材质）
            foreach (var mat in renderer.sharedMaterials)
            {
                if (mat != null)
                {
                    mat.SetVector(FaceForwardID, headBone.forward);
                    mat.SetVector(FaceRightID, headBone.right);
                }
            }
        }
    }
}