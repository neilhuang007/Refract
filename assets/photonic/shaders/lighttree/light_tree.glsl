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
float lt_last_traversal_pdf = 1.0f;

struct LightTreeNode {
    vec3 aabbMin;
    int leftChild;
    vec3 aabbMax;
    int rightChild;
    vec3 aggregateFlux;
    float totalIntensity;
    int leafStart;
    int leafCount;
    float level;
    float reserved;
};

uint pcg_hash(inout uint state) {
    return ph_rand_pcg(state);
}

float lt_random_float(inout uint rng) {
    return float(pcg_hash(rng)) / 4294967295.0f;
}

LightTreeNode lt_get_node(int index) {
    int baseIndex = index * 16;
    return LightTreeNode(
        vec3(
            light_tree_data[baseIndex + 0],
            light_tree_data[baseIndex + 1],
            light_tree_data[baseIndex + 2]
        ),
        floatBitsToInt(light_tree_data[baseIndex + 3]),
        vec3(
            light_tree_data[baseIndex + 4],
            light_tree_data[baseIndex + 5],
            light_tree_data[baseIndex + 6]
        ),
        floatBitsToInt(light_tree_data[baseIndex + 7]),
        vec3(
            light_tree_data[baseIndex + 8],
            light_tree_data[baseIndex + 9],
            light_tree_data[baseIndex + 10]
        ),
        light_tree_data[baseIndex + 11],
        floatBitsToInt(light_tree_data[baseIndex + 12]),
        floatBitsToInt(light_tree_data[baseIndex + 13]),
        light_tree_data[baseIndex + 14],
        light_tree_data[baseIndex + 15]
    );
}

bool lt_is_leaf(LightTreeNode node) {
    return node.leafStart >= 0;
}

float lt_node_importance(LightTreeNode node, vec3 shadingPos) {
    vec3 closestPoint = clamp(shadingPos, node.aabbMin, node.aabbMax);
    vec3 toBounds = closestPoint - shadingPos;
    float distanceSq = max(dot(toBounds, toBounds), lt_min_distance_sq);
    return max(node.totalIntensity, 0.0f) / distanceSq;
}

int lt_stochastic_traverse(vec3 shadingPos, inout uint rng) {
    lt_last_traversal_pdf = 1.0f;
    if (ph_light_tree_node_count <= 0) {
        return -1;
    }

    int nodeIndex = 0;
    for (int iteration = 0; iteration < ph_light_tree_node_count; iteration++) {
        LightTreeNode node = lt_get_node(nodeIndex);
        if (lt_is_leaf(node)) {
            return nodeIndex;
        }
        if (node.leftChild < 0 || node.rightChild < 0) {
            return nodeIndex;
        }

        LightTreeNode leftNode = lt_get_node(node.leftChild);
        LightTreeNode rightNode = lt_get_node(node.rightChild);
        float leftImportance = max(lt_node_importance(leftNode, shadingPos), 0.0f);
        float rightImportance = max(lt_node_importance(rightNode, shadingPos), 0.0f);
        float sumImportance = leftImportance + rightImportance;

        if (sumImportance <= 0.0f) {
            float fallbackChoice = lt_random_float(rng);
            float branchPdf = 0.5f;
            lt_last_traversal_pdf *= branchPdf;
            nodeIndex = fallbackChoice < 0.5f ? node.leftChild : node.rightChild;
            continue;
        }

        float leftPdf = leftImportance / sumImportance;
        float choice = lt_random_float(rng);
        bool chooseLeft = choice < leftPdf;
        lt_last_traversal_pdf *= chooseLeft ? leftPdf : (1.0f - leftPdf);
        nodeIndex = chooseLeft ? node.leftChild : node.rightChild;
    }

    return nodeIndex;
}

void lt_select_light_from_leaf(LightTreeNode leaf, vec3 shadingPos, inout uint rng, out int lightIndex, out float pdf) {
    lightIndex = -1;
    pdf = 0.0f;
    if (!lt_is_leaf(leaf) || leaf.leafCount <= 0) {
        return;
    }

    int offset = int(floor(lt_random_float(rng) * float(leaf.leafCount)));
    offset = clamp(offset, 0, leaf.leafCount - 1);
    lightIndex = light_tree_indices[leaf.leafStart + offset];

    float uniformLeafPdf = 1.0f / float(leaf.leafCount);
    pdf = lt_last_traversal_pdf * uniformLeafPdf;
    pdf = max(pdf, 1e-6f);
}

vec3 lt_evaluate_light(int lightIndex, vec3 shadingPos, vec3 normal) {
    if (lightIndex < 0 || lightIndex >= ph_light_count) {
        return vec3(0.0f);
    }

    Light light = load_light(lightIndex);
    vec3 toLight = light.position - shadingPos;
    float distanceSq = max(dot(toLight, toLight), 1e-4f);
    vec3 lightDirection = toLight * inversesqrt(distanceSq);
    float ndotl = clamp(dot(normalize(normal), lightDirection), 0.0f, 1.0f);
    if (ndotl <= 0.0f) {
        return vec3(0.0f);
    }

    float attenuation = light.attenuation.x + distanceSq * light.falloff * light.attenuation.y;
    if (attenuation <= 0.0f) {
        return vec3(0.0f);
    }

    vec3 radiance = light.color * light.intensity / attenuation;
    return max(radiance * ndotl, vec3(0.0f));
}

#endif
