using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace GPUDrivenTerrainLearn{

    [CreateAssetMenu(menuName = "GPUDrivenTerrainLearn/TerrainAsset")]
    public class TerrainAsset : ScriptableObject
    {
        public const uint MAX_NODE_ID = 34124; //5x5+10x10+20x20+40x40+80x80+160x160 - 1
        public const int MAX_LOD = 5;

        /// <summary>
        /// MAX LOD下，世界由5x5个区块组成
        /// </summary>
        public const int MAX_LOD_NODE_COUNT = 5;

        [SerializeField]
        private Vector3 _worldSize = new Vector3(10240,2048,10240);
        
        [SerializeField]
        private Texture2D _albedoMap;

        [SerializeField]
        private ComputeShader _terrainCompute;

        public Vector3 worldSize{
            get{
                return _worldSize;
            }
        }
        
        public Texture2D albedoMap{
            get{
                return _albedoMap;
            }
        }
        public ComputeShader computeShader{
            get{
                return _terrainCompute;
            }
        }

        private static Mesh _patchMesh;

        public static Mesh patchMesh{
            get{
                if(!_patchMesh){
                    _patchMesh = MeshUtility.CreatePlaneMesh(16);
                }
                return _patchMesh;
            }
        }

        public static Mesh _unitCubeMesh;

        public static Mesh unitCubeMesh{
            get{
                if(!_unitCubeMesh){
                    _unitCubeMesh = MeshUtility.CreateCube(1);
                }
                return _unitCubeMesh;
            }
        }
    }
}
