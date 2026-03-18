#ifndef PH_LIGHTTREE_LIGHT_TREE_INCLUDE
#define PH_LIGHTTREE_LIGHT_TREE_INCLUDE

layout(std430) restrict readonly buffer ph_light_tree {
    float light_tree_data[];
};

layout(std430) restrict readonly buffer ph_light_tree_indices {
    int light_tree_indices[];
};

uniform int ph_light_tree_node_count;

const float lt_min_distance_sq = 0.01f;
const float lt_min_node_error = 1e-6f;
const float lt_two_pi = 6.28318530718f;
const float lt_pi = 3.14159265359f;

struct LightTreeNode {
    vec3 aabbMin;
    int leftChild;
    vec3 aabbMax;
    int rightChild;
    vec3 orientationAxis;
    float totalIntensity;
    int subtreeStart;
    int subtreeCount;
    int representativeLightIndex;
    float thetaO;
    float thetaE;
    float energyVarianceCV;
    float level;
    float clusterRadius;
};

float lt_light_orientation_term(Light light, vec3 lightDirection);
void lt_select_light_from_leaf(LightTreeNode leaf, vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor, inout uint rng, out int lightIndex, out float pdf);

LightTreeNode lt_get_node(int index) {
    int baseIndex = index * 16;
    int packedMeta = floatBitsToInt(light_tree_data[baseIndex + 15]);
    int packedDepth = (packedMeta >> 24) & 255;
    int packedThetaO = (packedMeta >> 16) & 255;
    int packedThetaE = (packedMeta >> 8) & 255;
    int packedEnergyCV = packedMeta & 255;
    // Tree nodes are stored in world space by Java, but shading positions and
    // light positions (from load_light) are in camera-relative space (world - world_offset).
    // Convert node AABB to camera-relative to match.  clusterRadius is unaffected
    // because (max - offset) - (min - offset) = max - min.
    vec3 aabbMin = vec3(light_tree_data[baseIndex + 0], light_tree_data[baseIndex + 1], light_tree_data[baseIndex + 2]) - world_offset;
    vec3 aabbMax = vec3(light_tree_data[baseIndex + 4], light_tree_data[baseIndex + 5], light_tree_data[baseIndex + 6]) - world_offset;
    float clusterRadius = 0.5f * length(max(aabbMax - aabbMin, vec3(0.0f)));
    return LightTreeNode(
        aabbMin,
        floatBitsToInt(light_tree_data[baseIndex + 3]),
        aabbMax,
        floatBitsToInt(light_tree_data[baseIndex + 7]),
        normalize(vec3(light_tree_data[baseIndex + 8], light_tree_data[baseIndex + 9], light_tree_data[baseIndex + 10]) + vec3(1e-6f)),
        light_tree_data[baseIndex + 11],
        floatBitsToInt(light_tree_data[baseIndex + 12]),
        floatBitsToInt(light_tree_data[baseIndex + 13]),
        floatBitsToInt(light_tree_data[baseIndex + 14]),
        float(packedThetaO) / 255.0f * lt_pi,
        float(packedThetaE) / 255.0f * lt_pi,
        float(packedEnergyCV) / 255.0f,
        float(packedDepth),
        clusterRadius
    );
}

bool lt_is_leaf(LightTreeNode node) {
    return node.leftChild < 0 && node.rightChild < 0;
}

vec3 lt_node_centroid(LightTreeNode node) {
    return 0.5f * (node.aabbMin + node.aabbMax);
}

float lt_luminance_coeff(vec3 color) {
    return dot(color, vec3(0.2126f, 0.7152f, 0.0722f));
}

float lt_safe_acos(float value) {
    return acos(clamp(value, -1.0f, 1.0f));
}


// Paper Eq. 1: min/max distance importance pair for a node AABB.
// Returns vec2(importance_at_dMin, importance_at_dMax).
// Direction/angle bounds still use the centroid as a conservative reference.
vec2 lt_node_importance_minmax(LightTreeNode node, vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor) {
    vec3 center = lt_node_centroid(node);
    vec3 toCenter = center - shadingPos;
    float distanceToCenter = max(length(toCenter), 1e-4f);
    vec3 dirToNode = toCenter / distanceToCenter;

    // Uncertainty angle sin/cos: replaces asin(r/d)
    float sinU = clamp(node.clusterRadius / distanceToCenter, 0.0f, 0.9999f);
    float cosU = sqrt(1.0f - sinU * sinU);

    // Paper Eq. 3: incident term cos(max(θ_i - θ_u, 0))
    // Algebraic: cos(acos(cosI) - asin(sinU)) = cosI*cosU + sinI*sinU
    float cosI = dot(normalize(mappedNormal), dirToNode);
    float incident;
    if (cosI >= cosU) {
        // θ_i ≤ θ_u → clamped to 0 → cos(0) = 1
        incident = 1.0f;
    } else {
        float sinI = sqrt(max(1.0f - cosI * cosI, 0.0f));
        incident = cosI * cosU + sinI * sinU;
    }
    if (incident <= 0.0f) {
        return vec2(0.0f);
    }

    // Conty & Kulla Eq. 3: orientation term cos(max(θ - θ_o - θ_u, 0))
    // Compute cos/sin of θ_o locally to avoid struct bloat / register pressure
    float cosO = cos(node.thetaO);
    float sinO = sin(node.thetaO);
    float cosE = cos(node.thetaE);

    // Combined offset: cos/sin(θ_o + θ_u) via angle addition formula
    float cosA = dot(node.orientationAxis, -dirToNode);
    float cosOU = cosO * cosU - sinO * sinU;
    float sinOU = sinO * cosU + cosO * sinU;

    float orientation;
    // Guard: when θ_o + θ_u ≥ π the orientation cone covers all directions.
    // sinOU ≤ 0 detects this (sin is negative in (π, 2π)).
    // Without this guard, the cosine comparison wraps incorrectly past π,
    // causing systematic underestimation for point/sphere lights (θ_o = π).
    if (sinOU <= 0.0f || cosA >= cosOU) {
        orientation = 1.0f;
    } else {
        float sinA = sqrt(max(1.0f - cosA * cosA, 0.0f));
        orientation = cosA * cosOU + sinA * sinOU;
    }

    // Cutoff: θ' ≥ θ_e ↔ cos(θ') ≤ cos(θ_e)
    if (orientation <= cosE) {
        return vec2(0.0f);
    }
    if (orientation <= 0.0f) {
        return vec2(0.0f);
    }

    float albedoWeight = clamp(lt_luminance_coeff(albedoColor), 0.05f, 1.0f);
    float numerator = max(node.totalIntensity, 0.0f) * albedoWeight * incident * orientation;

    // Closest point on AABB to shadingPos (squared distance)
    vec3 closest = clamp(shadingPos, node.aabbMin, node.aabbMax);
    vec3 closestDelta = closest - shadingPos;
    float dMinSq = max(dot(closestDelta, closestDelta), lt_min_distance_sq);

    // Farthest point on AABB from shadingPos (squared distance)
    vec3 farthestDelta = max(abs(node.aabbMin - shadingPos), abs(node.aabbMax - shadingPos));
    float dMaxSq = max(dot(farthestDelta, farthestDelta), lt_min_distance_sq);

    return vec2(numerator / dMinSq, numerator / dMaxSq);
}

// Paper Eq. 2: averaged branch probability from min/max importance pairs
float lt_compute_branch_probability(vec2 wJ, vec2 wK) {
    float sumMin = wJ.x + wK.x;
    float sumMax = wJ.y + wK.y;
    float pMin = sumMin > 0.0f ? wJ.x / sumMin : 0.5f;
    float pMax = sumMax > 0.0f ? wJ.y / sumMax : 0.5f;
    return (pMin + pMax) * 0.5f;
}

float lt_light_orientation_term(Light light, vec3 lightDirection) {
    if (light.orientationSpread >= lt_pi) {
        return 1.0f;
    }
    float axisAngle = lt_safe_acos(dot(light.emissionAxis, -lightDirection));
    return max(cos(max(axisAngle - light.orientationSpread, 0.0f)), 0.0f);
}

// Paper Eq. 3 specialized for a single emitter (no cluster uncertainty).
// Uses the light's actual attenuation model instead of 1/d² so the proposal
// PDF closely tracks the target PDF, reducing ReSTIR weight variance.
float lt_leaf_light_importance(Light light, vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor) {
    vec3 toLight = light.position - shadingPos;
    float distSq = max(dot(toLight, toLight), lt_min_distance_sq);
    vec3 lightDir = normalize(toLight);

    // Paper Eq. 3: |cos θ_i| — no cluster uncertainty for single emitters
    float incident = max(dot(normalize(mappedNormal), lightDir), 0.0f);
    if (incident <= 0.0f) {
        return 0.0f;
    }

    // Orientation: match evaluation's emission cone falloff
    float orientation = 1.0f;
    if (light.orientationSpread < lt_pi) {
        float axisAngle = lt_safe_acos(dot(light.emissionAxis, -lightDir));
        orientation = max(cos(max(axisAngle - light.orientationSpread, 0.0f)), 0.0f);
    }
    if (orientation <= 0.0f) {
        return 0.0f;
    }

    // Match evaluation's attenuation: 1/(atten.x + d²·falloff·atten.y)
    // instead of paper's 1/d² — eliminates importance/evaluation mismatch for nearby lights
    float attenuation = max(light.attenuation.x + distSq * light.falloff * light.attenuation.y, 1e-4f);
    float albedoWeight = clamp(lt_luminance_coeff(albedoColor), 0.05f, 1.0f);
    return max(light.intensity * albedoWeight * incident * orientation / attenuation, lt_min_node_error);
}

// Paper Equations 8-10: Split measure based on variance of (energy x geometric term)
// E[g] = 1/(a*b), V[g] = E[g²] - E[g]², where g = 1/x² over [a,b]
// E[g²] = (b²+ab+a²) / (3*a³*b³)  - paper Eq. 9
// σ² = (V[e]*V[g] + V[e]*E[g]² + E[e]²*V[g]) * N²  - paper Eq. 10
// Remapped to [0,1] via (1 / (1 + σ))^(1/4) as described in paper Sec. 5.4.
float lt_leaf_variance_measure(LightTreeNode leaf, vec3 shadingPos) {
    vec3 center = lt_node_centroid(leaf);
    float distanceToCenter = max(length(center - shadingPos), 1e-4f);
    float minDistance = max(distanceToCenter - leaf.clusterRadius, 1e-3f);
    float maxDistance = max(distanceToCenter + leaf.clusterRadius, minDistance + 1e-3f);

    // Paper Eq 8: E[g] = 1/(a*b) for g = 1/x^2
    float geomMean = 1.0f / max(minDistance * maxDistance, 1e-4f);

    // Paper Eq 9: V[g] = (b^2 + ab + a^2) / (3 * a^3 * b^3) - 1/(a^2 * b^2)
    float a2 = minDistance * minDistance;
    float b2 = maxDistance * maxDistance;
    float a3 = a2 * minDistance;
    float b3 = b2 * maxDistance;
    float geomVariance = max((b2 + minDistance * maxDistance + a2)
        / (3.0f * max(a3 * b3, 1e-6f)) - geomMean * geomMean, 0.0f);

    // Paper Eq 10: sigma^2 = (V[e]*V[g] + V[e]*E[g]^2 + E[e]^2*V[g]) * N^2
    // Using CV encoding: V[e] = CV^2 * (E/N)^2, so sigma^2 = E^2 * (CV^2*V[g] + CV^2*E[g]^2 + V[g])
    float cv2 = leaf.energyVarianceCV * leaf.energyVarianceCV;
    float totalE2 = max(leaf.totalIntensity * leaf.totalIntensity, 1e-8f);
    float sigmaSq = totalE2 * (cv2 * geomVariance + cv2 * geomMean * geomMean + geomVariance);

    float sigma = sqrt(max(sigmaSq, 0.0f));
    return pow(1.0f / (1.0f + sigma), 0.25f);
}

bool lt_sample_light_from_node(LightTreeNode node, vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor, inout uint rng, out int lightIndex, out float lightPdf) {
    lightIndex = -1;
    lightPdf = 0.0f;
    if (lt_is_leaf(node)) {
        lt_select_light_from_leaf(node, shadingPos, shadingNormal, mappedNormal, albedoColor, rng, lightIndex, lightPdf);
        return lightIndex >= 0 && lightPdf > 0.0f;
    }

    LightTreeNode current = node;
    float pathPdf = 1.0f;
    for (int depth = 0; depth < 32; depth++) {
        if (lt_is_leaf(current)) {
            float leafPdf = 0.0f;
            lt_select_light_from_leaf(current, shadingPos, shadingNormal, mappedNormal, albedoColor, rng, lightIndex, leafPdf);
            lightPdf = pathPdf * leafPdf;
            return lightIndex >= 0 && leafPdf > 0.0f;
        }
        if (current.leftChild < 0 || current.rightChild < 0) {
            return false;
        }

        LightTreeNode leftNode = lt_get_node(current.leftChild);
        LightTreeNode rightNode = lt_get_node(current.rightChild);
        // Paper Eq. 1-2: min/max distance dual-probability importance weighting
        vec2 leftW = lt_node_importance_minmax(leftNode, shadingPos, shadingNormal, mappedNormal, albedoColor);
        vec2 rightW = lt_node_importance_minmax(rightNode, shadingPos, shadingNormal, mappedNormal, albedoColor);
        // Paper Algorithm 2: never bail out — fall back to uniform when both are zero
        float leftBranchPdf = lt_compute_branch_probability(leftW, rightW);
        float xi = float(ph_rand_pcg(rng)) / 4294967295.0f;
        bool chooseLeft = xi < leftBranchPdf;
        float chosenBranchPdf = max(chooseLeft ? leftBranchPdf : (1.0f - leftBranchPdf), 1e-6f);

        pathPdf *= chosenBranchPdf;
        current = chooseLeft ? leftNode : rightNode;
    }
    return false;
}

void lt_select_light_from_leaf(LightTreeNode leaf, vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor, inout uint rng, out int lightIndex, out float pdf) {
    lightIndex = -1;
    pdf = 0.0f;
    if (!lt_is_leaf(leaf) || leaf.subtreeCount <= 0) {
        return;
    }

    // Single-pass reservoir sampling: select proportional to importance
    // without needing to know the total in advance
    float totalImportance = 0.0f;
    float selectedImportance = 0.0f;
    for (int i = 0; i < leaf.subtreeCount; i++) {
        int idx = light_tree_indices[leaf.subtreeStart + i];
        Light light = load_light(idx);
        float importance = lt_leaf_light_importance(light, shadingPos, shadingNormal, mappedNormal, albedoColor);
        totalImportance += importance;
        // With probability importance/totalImportance, replace current selection
        if (totalImportance > 0.0f && float(ph_rand_pcg(rng)) / 4294967295.0f < importance / totalImportance) {
            lightIndex = idx;
            selectedImportance = importance;
        }
    }

    if (lightIndex < 0 || totalImportance <= 0.0f) {
        // Fallback: uniform selection
        lightIndex = light_tree_indices[leaf.subtreeStart];
        pdf = 1.0f / float(max(leaf.subtreeCount, 1));
        return;
    }

    pdf = max(selectedImportance / totalImportance, 1e-6f);
}

// Paper Algorithm 2: PickLight - direct stochastic tree traversal
// Returns true if a light was successfully picked
// Uses hierarchical sample warping: single xi drives entire traversal
bool lt_pick_light(vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor, inout float xi, out int lightIndex, out float pdf) {
    lightIndex = -1;
    pdf = 0.0f;
    if (ph_light_tree_node_count <= 0) return false;

    LightTreeNode current = lt_get_node(0); // start at root
    float pathPdf = 1.0f;

    // Traverse from root to leaf using importance-weighted binary decisions
    for (int depth = 0; depth < 32; depth++) {
        if (lt_is_leaf(current)) {
            // At leaf: select light from emitters using importance-weighted CDF
            if (current.subtreeCount <= 0) return false;
            if (current.subtreeCount == 1) {
                lightIndex = light_tree_indices[current.subtreeStart];
                pdf = pathPdf;
                return true;
            }

            // Build CDF over leaf emitters
            float totalImportance = 0.0f;
            for (int i = 0; i < current.subtreeCount; i++) {
                int idx = light_tree_indices[current.subtreeStart + i];
                Light light = load_light(idx);
                totalImportance += lt_leaf_light_importance(light, shadingPos, shadingNormal, mappedNormal, albedoColor);
            }

            if (totalImportance <= 0.0f) {
                // Fallback: uniform selection
                int selected = clamp(int(xi * float(current.subtreeCount)), 0, current.subtreeCount - 1);
                lightIndex = light_tree_indices[current.subtreeStart + selected];
                pdf = pathPdf / float(current.subtreeCount);
                return true;
            }

            // Sample CDF using xi
            float target = xi * totalImportance;
            float cumulative = 0.0f;
            for (int i = 0; i < current.subtreeCount; i++) {
                int idx = light_tree_indices[current.subtreeStart + i];
                Light light = load_light(idx);
                float importance = lt_leaf_light_importance(light, shadingPos, shadingNormal, mappedNormal, albedoColor);
                cumulative += importance;
                if (cumulative >= target || i == current.subtreeCount - 1) {
                    lightIndex = idx;
                    pdf = pathPdf * max(importance / totalImportance, 1e-6f);
                    return true;
                }
            }
            return false;
        }

        // Interior node: binary decision based on child importance
        if (current.leftChild < 0 || current.rightChild < 0) return false;

        LightTreeNode leftNode = lt_get_node(current.leftChild);
        LightTreeNode rightNode = lt_get_node(current.rightChild);
        // Paper Eq. 1-2: min/max distance dual-probability importance weighting
        vec2 leftW = lt_node_importance_minmax(leftNode, shadingPos, shadingNormal, mappedNormal, albedoColor);
        vec2 rightW = lt_node_importance_minmax(rightNode, shadingPos, shadingNormal, mappedNormal, albedoColor);
        // Paper Algorithm 2: never bail out — uniform fallback when both are zero
        float leftProb = lt_compute_branch_probability(leftW, rightW);
        if (xi < leftProb) {
            // Go left, rescale xi to [0, 1) within left branch
            xi = xi / max(leftProb, 1e-6f);
            pathPdf *= leftProb;
            current = leftNode;
        } else {
            // Go right, rescale xi to [0, 1) within right branch
            xi = (xi - leftProb) / max(1.0f - leftProb, 1e-6f);
            pathPdf *= (1.0f - leftProb);
            current = rightNode;
        }
    }
    return false;
}

// Paper Algorithm 3: GetLights - adaptive splitting
// When a node has high internal variance, explore BOTH children (iterative stack version)
// Returns count of lights picked (stored in lightIndices/lightPdfs arrays)
// GLSL does not support recursion — use an explicit stack
const int lt_split_stack_size = 16;

int lt_get_lights_split(
    vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor,
    float splitThreshold, inout uint rng,
    inout int lightIndices[8], inout float lightPdfs[8], int maxLights
) {
    int count = 0;
    int stackNodes[lt_split_stack_size];
    float stackPdfs[lt_split_stack_size];
    int stackTop = 0;

    stackNodes[0] = 0; // root
    stackPdfs[0] = 1.0f;
    stackTop = 1;

    while (stackTop > 0 && count < maxLights) {
        stackTop--;
        int nodeIndex = stackNodes[stackTop];
        float parentPdf = stackPdfs[stackTop];

        LightTreeNode node = lt_get_node(nodeIndex);

        // Check if we should split (explore both children)
        bool shouldSplit = false;
        if (!lt_is_leaf(node) && node.leftChild >= 0 && node.rightChild >= 0) {
            float variance = lt_leaf_variance_measure(node, shadingPos);
            shouldSplit = variance < splitThreshold && count + 2 <= maxLights && stackTop + 2 <= lt_split_stack_size;
        }

        if (shouldSplit) {
            // Paper Section 6: "splitting does not alter [the PDF] since it is
            // a deterministic process."  Both children inherit parentPdf unchanged;
            // only the stochastic decisions inside lt_sample_light_from_node
            // contribute to the final PDF.
            stackNodes[stackTop] = node.rightChild;
            stackPdfs[stackTop] = parentPdf;
            stackTop++;
            stackNodes[stackTop] = node.leftChild;
            stackPdfs[stackTop] = parentPdf;
            stackTop++;
        } else {
            // No split: pick one light from this subtree
            int lightIndex = -1;
            float lightPdf = 0.0f;

            if (lt_sample_light_from_node(node, shadingPos, shadingNormal, mappedNormal, albedoColor, rng, lightIndex, lightPdf)) {
                if (lightIndex >= 0 && lightPdf > 0.0f && count < maxLights) {
                    lightIndices[count] = lightIndex;
                    lightPdfs[count] = parentPdf * lightPdf;
                    count++;
                }
            }
        }
    }

    return count;
}

#endif



