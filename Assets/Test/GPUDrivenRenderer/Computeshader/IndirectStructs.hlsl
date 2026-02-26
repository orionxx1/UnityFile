#ifndef INDIRECTSTRUCTS_INCLUDE
#define INDIRECTSTRUCTS_INCLUDE

struct InstanceData
{
    float3 boundsCenter;
    float3 boundsExtents;
};

struct SortingData
{
    uint drawCallInstanceIndex;
    float distanceToCam;
};

struct LodViewRatio
{
    float lod0Range;
    float lod1Range;
    float lod2Range;
};

#endif