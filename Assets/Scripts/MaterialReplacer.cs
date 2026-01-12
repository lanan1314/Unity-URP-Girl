using System;
using System.Collections.Generic;
using UnityEngine;

[ExecuteAlways]
public class MaterialReplacer : MonoBehaviour
{
    [Serializable]
    public struct Entry
    {
        [Tooltip("子物体名或关键字，例如 cloth / body / hair_outer")]
        public string childNameOrKeyword;

        [Tooltip("给这个子物体(或名称包含该关键字的子物体)设置的材质")]
        public Material material;

        [Tooltip("是否使用“包含”匹配（勾选=包含，不勾选=完全相等）")]
        public bool useContains;
    }

    [Tooltip("在这里配置 子物体名(或关键字) -> 材质 的映射")]
    public List<Entry> map = new List<Entry>();

    [ContextMenu("Apply Materials To Children")]
    public void Apply()
    {
        if (map == null || map.Count == 0) return;

        // 处理所有 Renderer（包含 SkinnedMeshRenderer 和 MeshRenderer）
        var renderers = GetComponentsInChildren<Renderer>(true);

        foreach (var r in renderers)
        {
            string childName = r.gameObject.name;

            foreach (var e in map)
            {
                if (e.material == null) continue;

                bool matched = e.useContains
                    ? childName.IndexOf(e.childNameOrKeyword, StringComparison.OrdinalIgnoreCase) >= 0
                    : string.Equals(childName, e.childNameOrKeyword, StringComparison.OrdinalIgnoreCase);

                if (matched)
                {
                    // 直接替换到 renderer.sharedMaterial，避免在编辑器生成实例材质
                    r.sharedMaterial = e.material;
                    break;
                }
            }
        }
    }

    // 在检视面板修改映射后自动应用（可按需注释）
    private void OnValidate()
    {
        // 仅在编辑器且对象处于场景中时自动应用
#if UNITY_EDITOR
        if (!Application.isPlaying && gameObject.scene.IsValid())
            Apply();
#endif
    }
}