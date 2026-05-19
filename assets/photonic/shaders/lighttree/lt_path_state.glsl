#ifndef PHOTONICS_LT_PATH_STATE_GLSL
#define PHOTONICS_LT_PATH_STATE_GLSL

// ---------------------------------------------------------------------------
// Path-state data structures shared across the ReSTIR DI temporal / spatial /
// scatter pipeline. Reference parity is enforced (ReconnectionData.slang
// field-for-field). Do NOT add photonics-specific fields here — those belong
// on per-pixel reservoir headers or surface-identity textures.
// No external types referenced beyond GLSL builtins; safe to include early.
// ---------------------------------------------------------------------------

// ============================================================================
// Scatter Temporal Resampling: Reconnection Data
// ============================================================================
// =====================================================================
// Reference-parity ReconnectionData (ReconnectionData.slang:89-166).
// Field order, names, types and default values MUST match the Slang
// reference 1:1. DO NOT add photonics-specific fields here -- those belong
// on the per-pixel reservoir header or the surface identity texture, NOT on
// the reconnection payload.
// =====================================================================
struct HitInfo {
    vec3  worldPos;    // Object/world-space hit position
    float viewDepth;   // Linear view depth (for bilateral tests)
    uint  faceId;      // Dominant signed block face identifier
    uint  materialId;   // Quantized local material/light identity.
};

HitInfo HitInfo_empty() {
    HitInfo h;
    h.worldPos = vec3(0.0f);
    h.viewDepth = 0.0f;
    h.faceId = 0u;
    h.materialId = 0u;
    return h;
}


#ifndef PH_LIGHTTREE_SHIFTED_PATH_DATA_DECLARED
#define PH_LIGHTTREE_SHIFTED_PATH_DATA_DECLARED
struct ShiftedPathData {
    HitInfo primaryHit;
    vec2 fractionalPixel;
    vec2 lensSample;
    vec3 firstRayDir;
    float subPixelJacobian;
    float lensVertexJacobian;
    float secondaryPathJacobian;
    vec3 radiance;
};
#endif

// Reference-parity ``ReconnectionData`` (ReconnectionData.slang:89-166).
struct ReconnectionData {
    // Some camera / film parameters used generally.
    vec2  subPixel;                     // ReconnectionData.slang:92
    vec2  lensSample;                   // ReconnectionData.slang:93
    float time;                         // ReconnectionData.slang:94

    // The only vertex that contributes actual emission is the final
    // vertex, i.e. the path length is equivalent to the index of the
    // light vertex.
    uint  pathLength;                   // ReconnectionData.slang:98

    // Information about the first vertex.
    HitInfo firstHit;                   // ReconnectionData.slang:101 (HitInfo)
    uint  firstBSDFComponentType;       // ReconnectionData.slang:102 (NOTE camelcase)
    vec3  firstWi;                      // ReconnectionData.slang:103 (toward camera)

    // Information about the second vertex.
    HitInfo secondHit;                  // ReconnectionData.slang:106 (HitInfo)
    uint  secondBSDFComponentType;       // ReconnectionData.slang:107 (NOTE camelcase)
    vec3  secondWo;                      // ReconnectionData.slang:108 (outgoing at x2)

    bool  transmissionEvent;             // ReconnectionData.slang:110

    // Light-side book-keeping for NEE vs BSDF resolution at the shift.
    bool  lightIsNEE;                    // ReconnectionData.slang:113
    bool  lightIsDistant;                // ReconnectionData.slang:114
    float lightPdf;                      // ReconnectionData.slang:115

    // Jacobians carried by every shift map.
    float subPixelJacobian;              // ReconnectionData.slang:119
    float lensVertexJacobian;            // ReconnectionData.slang:120
    float secondaryPathJacobian;         // ReconnectionData.slang:121
    vec3  irradiance;                    // ReconnectionData.slang:122
    vec3  earlyThroughput;               // ReconnectionData.slang:123 (prefix thp)
};

ReconnectionData ReconnectionData_init() {
    ReconnectionData d;
    // ReconnectionData.slang:127-129 -- camera / film parameters.
    d.subPixel = vec2(0.5f, 0.5f);
    d.lensSample = vec2(0.0f, 0.0f);            // Reference: float2(0, 0) (NOT 0.5).
    d.time = 0.0f;

    // ReconnectionData.slang:131.
    d.pathLength = 0u;

    // ReconnectionData.slang:133-135 -- first vertex.
    d.firstHit = HitInfo_empty();
    d.firstBSDFComponentType = 0u;
    d.firstWi = vec3(0.0f, 0.0f, 0.0f);         // Reference: float3(0, 0, 0).

    // ReconnectionData.slang:137-139 -- second vertex.
    d.secondHit = HitInfo_empty();
    d.secondBSDFComponentType = 0u;
    d.secondWo = vec3(0.0f, 0.0f, 0.0f);

    // ReconnectionData.slang:141 -- transmission flag.
    d.transmissionEvent = false;

    // ReconnectionData.slang:143-145 -- NEE / distant / lightPdf.
    d.lightIsNEE = false;
    d.lightIsDistant = false;
    d.lightPdf = 0.0f;

    // ReconnectionData.slang:147-151 -- Jacobians + radiance carriers.
    d.subPixelJacobian = 1.0f;
    d.lensVertexJacobian = 1.0f;
    d.secondaryPathJacobian = 1.0f;
    d.irradiance = vec3(0.0f, 0.0f, 0.0f);
    d.earlyThroughput = vec3(1.0f, 1.0f, 1.0f); // Reference: float3(1, 1, 1), NOT 0.
    return d;
}

#endif // PHOTONICS_LT_PATH_STATE_GLSL
