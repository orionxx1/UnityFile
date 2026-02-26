using UnityEngine;

// 方便在编辑器中看到和操作
[ExecuteInEditMode]
[RequireComponent(typeof(BoxCollider))]
public class RF_CloudTex_BoxAABB : MonoBehaviour
{
    // 静态引用，用于追踪场景中唯一的激活实例
    public static RF_CloudTex_BoxAABB ActiveBoxInstance { get; private set; }

    // 全局Gizmo显示开关 ---
    public static bool ShowGizmosGlobally = true; // 默认开启

    private BoxCollider _boxCollider;
    public Bounds WorldBounds => _boxCollider.bounds;

    void OnEnable()
    {
        _boxCollider = GetComponent<BoxCollider>();
        if (_boxCollider == null)
        {
            _boxCollider = gameObject.AddComponent<BoxCollider>();
            _boxCollider.isTrigger = true; // 确保是Trigger，避免物理碰撞
        }
        // 确保BoxCollider的中心和大小与Transform同步 (如果不是通过Inspector直接修改Collider)
        // 你可能需要根据实际情况调整collider的center和size，如果它们不是 (0,0,0) 和 (1,1,1)
        // 例如：_boxCollider.center = Vector3.zero; _boxCollider.size = Vector3.one;

        if (ActiveBoxInstance == null)
        {
            ActiveBoxInstance = this;
        }
        else if (ActiveBoxInstance != this)
        {
            Debug.LogWarning($"RF_CloudTex_BoxAABB: An active instance already exists ('{ActiveBoxInstance.gameObject.name}'). " +
                             $"Disabling this new instance ('{gameObject.name}'). Only one active box is supported.", this.gameObject);
            enabled = false; // 禁用这个新的实例
            // 或者销毁它
            // if (Application.isPlaying) Destroy(this); else DestroyImmediate(this);
            return;
        }
        // 如果 ActiveBoxInstance == this，说明是同一个对象被重新激活，这是允许的
    }

    void OnDisable()
    {
        if (ActiveBoxInstance == this)
        {
            ActiveBoxInstance = null;
        }
    }

    void OnDrawGizmos()
    {
        if (!ShowGizmosGlobally)
        {
            return;
        }

        if (_boxCollider == null) _boxCollider = GetComponent<BoxCollider>();

        if (_boxCollider != null)
        {
            Matrix4x4 originalMatrix = Gizmos.matrix;
            // 使用transform的TRS来绘制OBB Gizmo，而不是世界空间的AABB
            // Gizmos.matrix = transform.localToWorldMatrix; // 这样会包含父对象的变换
            // 更准确地，我们用BoxCollider的局部中心和物体的旋转和缩放
            Gizmos.matrix = Matrix4x4.TRS(transform.TransformPoint(_boxCollider.center), transform.rotation, transform.lossyScale);

            Gizmos.color = new Color(0.5f, 0.8f, 1f, 0.3f);
            Gizmos.DrawCube(Vector3.zero, _boxCollider.size); // 在局部坐标系中心绘制，使用collider的size

            Gizmos.color = Color.white;
            Gizmos.DrawWireCube(Vector3.zero, _boxCollider.size);

            Gizmos.matrix = originalMatrix;
        }
    }
}