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
const int lt_max_cut_nodes = 24;
const int lt_heap_capacity = 32;
const float lt_min_node_error = 1e-6f;
const float lt_cut_error_ratio = 0.02f;
const float lt_two_pi = 6.28318530718f;
const float lt_pi = 3.14159265359f;

struct LightTreeNode {
    vec3 aabbMin;
    int leftChild;
    vec3 aabbMax;
    int rightChild;
    vec3 orientationAxis;
    float totalIntensity;
    int leafStart;
    int leafCount;
    int representativeLightIndex;
    float geometricBound;
    float orientationBound;
    float errorBound;
    float level;
    float clusterRadius;
};

struct LtCutNode {
    int nodeIndex;
    float estimate;
    float error;
};

struct LtCutResult {
    int count;
    float totalEstimate;
    float totalError;
    LtCutNode nodes[lt_max_cut_nodes];
};

float lt_light_orientation_term(Light light, vec3 lightDirection);
void lt_select_light_from_leaf(LightTreeNode leaf, vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor, inout uint rng, out int lightIndex, out float pdf);
float lt_light_pdf_in_leaf(LightTreeNode leaf, vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor, int lightIndex);
bool lt_node_contains_light(LightTreeNode node, int lightIndex);
float lt_light_pdf_in_node(LightTreeNode node, vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor, int lightIndex);
float lt_cut_light_pdf(LtCutResult cut, vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor, int lightIndex);

LightTreeNode lt_get_node(int index) {
    int baseIndex = index * 16;
    int packedMeta = floatBitsToInt(light_tree_data[baseIndex + 15]);
    int packedDepth = (packedMeta >> 24) & 255;
    int packedGeometric = (packedMeta >> 16) & 255;
    int packedOrientation = (packedMeta >> 8) & 255;
    vec3 aabbMin = vec3(light_tree_data[baseIndex + 0], light_tree_data[baseIndex + 1], light_tree_data[baseIndex + 2]);
    vec3 aabbMax = vec3(light_tree_data[baseIndex + 4], light_tree_data[baseIndex + 5], light_tree_data[baseIndex + 6]);
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
        float(packedGeometric) / 255.0f,
        float(packedOrientation) / 255.0f,
        max((float(packedGeometric) + float(packedOrientation)) / 255.0f, lt_min_node_error),
        float(packedDepth),
        clusterRadius
    );
}

bool lt_is_leaf(LightTreeNode node) {
    return node.leafStart >= 0;
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

float lt_node_orientation_spread(LightTreeNode node) {
    return clamp(node.orientationBound * 4.0f * lt_pi, 0.0f, lt_pi);
}

float lt_cluster_uncertainty_angle(LightTreeNode node, vec3 shadingPos) {
    vec3 center = lt_node_centroid(node);
    float distanceToCenter = max(length(center - shadingPos), 1e-4f);
    return asin(clamp(node.clusterRadius / distanceToCenter, 0.0f, 0.9999f));
}

float lt_node_importance(LightTreeNode node, vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor) {
    vec3 center = lt_node_centroid(node);
    vec3 toCenter = center - shadingPos;
    float distanceSq = max(dot(toCenter, toCenter), lt_min_distance_sq);
    vec3 dirToNode = normalize(toCenter);
    float thetaU = lt_cluster_uncertainty_angle(node, shadingPos);
    float incidentAngle = lt_safe_acos(dot(normalize(mappedNormal), dirToNode));
    float thetaIPrime = max(incidentAngle - thetaU, 0.0f);
    float incident = cos(thetaIPrime);
    if (incident <= 0.0f) {
        return 0.0f;
    }

    float axisAngle = lt_safe_acos(dot(node.orientationAxis, -dirToNode));
    float orientationSpread = lt_node_orientation_spread(node);
    float thetaPrime = max(axisAngle - orientationSpread - thetaU, 0.0f);
    float orientation = cos(thetaPrime);
    if (orientation <= 0.0f) {
        return 0.0f;
    }

    float albedoWeight = clamp(lt_luminance_coeff(albedoColor), 0.05f, 1.0f);
    return max(node.totalIntensity, 0.0f) * albedoWeight * incident * orientation / distanceSq;
}

float lt_node_error_bound(LightTreeNode node, vec3 shadingPos, vec3 shadingNormal) {
    vec3 center = lt_node_centroid(node);
    vec3 toCenter = center - shadingPos;
    float distanceToCenter = max(length(toCenter), 1e-4f);
    float clampedSinTheta = clamp(node.clusterRadius / distanceToCenter, 0.0f, 0.9999f);
    float coneHalfAngle = asin(clampedSinTheta);
    float geomCosBound = cos(coneHalfAngle);
    float directionCos = max(dot(node.orientationAxis, -normalize(toCenter)), 0.0f);
    float orientationCosBound = directionCos <= 0.0f ? 0.0f : cos(max(acos(clamp(directionCos, 0.0f, 1.0f)) - coneHalfAngle, 0.0f));
    float incidentBound = max(dot(normalize(shadingNormal), normalize(toCenter)), 0.0f);
    float boundEstimate = max(node.totalIntensity, 0.0f) * incidentBound * max(orientationCosBound, 0.0f) / max(distanceToCenter * distanceToCenter * max(geomCosBound * geomCosBound, 1e-4f), lt_min_distance_sq);
    return max(boundEstimate, lt_min_node_error);
}

LtCutNode lt_make_cut_node(int nodeIndex, vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor) {
    LightTreeNode node = lt_get_node(nodeIndex);
    float estimate = max(lt_node_importance(node, shadingPos, shadingNormal, mappedNormal, albedoColor), lt_min_node_error);
    float upperBound = lt_node_error_bound(node, shadingPos, shadingNormal);
    float error = max(upperBound - estimate, 0.0f);
    return LtCutNode(nodeIndex, estimate, error);
}

void lt_heap_push(inout LtCutNode heap[lt_heap_capacity], inout int heapCount, LtCutNode value) {
    if (heapCount >= lt_heap_capacity) {
        return;
    }
    int index = heapCount++;
    heap[index] = value;
    while (index > 0) {
        int parent = (index - 1) / 2;
        if (heap[parent].error >= heap[index].error) {
            break;
        }
        LtCutNode tmp = heap[parent];
        heap[parent] = heap[index];
        heap[index] = tmp;
        index = parent;
    }
}

LtCutNode lt_heap_pop(inout LtCutNode heap[lt_heap_capacity], inout int heapCount) {
    LtCutNode result = heap[0];
    heapCount--;
    if (heapCount > 0) {
        heap[0] = heap[heapCount];
        int index = 0;
        while (true) {
            int left = index * 2 + 1;
            int right = left + 1;
            int largest = index;
            if (left < heapCount && heap[left].error > heap[largest].error) {
                largest = left;
            }
            if (right < heapCount && heap[right].error > heap[largest].error) {
                largest = right;
            }
            if (largest == index) {
                break;
            }
            LtCutNode tmp = heap[index];
            heap[index] = heap[largest];
            heap[largest] = tmp;
            index = largest;
        }
    }
    return result;
}

LtCutResult lt_build_cut(vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor, int refinementBudget) {
    LtCutResult result;
    result.count = 0;
    result.totalEstimate = 0.0f;
    result.totalError = 0.0f;
    if (ph_light_tree_node_count <= 0) {
        return result;
    }

    LtCutNode heap[lt_heap_capacity];
    int heapCount = 0;
    lt_heap_push(heap, heapCount, lt_make_cut_node(0, shadingPos, shadingNormal, mappedNormal, albedoColor));

    while (heapCount > 0 && result.count + heapCount <= lt_max_cut_nodes) {
        float totalEstimate = 0.0f;
        float maxError = 0.0f;
        int maxErrorIndex = -1;
        for (int i = 0; i < heapCount; i++) {
            totalEstimate += heap[i].estimate;
            if (heap[i].error > maxError) {
                maxError = heap[i].error;
                maxErrorIndex = i;
            }
        }

        if (heapCount >= refinementBudget || maxErrorIndex < 0 || maxError <= lt_cut_error_ratio * max(totalEstimate, lt_min_node_error)) {
            break;
        }

        LtCutNode candidate = heap[maxErrorIndex];
        heap[maxErrorIndex] = heap[heapCount - 1];
        heapCount--;
        int repairIndex = maxErrorIndex;
        while (repairIndex > 0) {
            int parent = (repairIndex - 1) / 2;
            if (heap[parent].error >= heap[repairIndex].error) {
                break;
            }
            LtCutNode tmp = heap[parent];
            heap[parent] = heap[repairIndex];
            heap[repairIndex] = tmp;
            repairIndex = parent;
        }
        while (true) {
            int left = repairIndex * 2 + 1;
            int right = left + 1;
            int largest = repairIndex;
            if (left < heapCount && heap[left].error > heap[largest].error) {
                largest = left;
            }
            if (right < heapCount && heap[right].error > heap[largest].error) {
                largest = right;
            }
            if (largest == repairIndex) {
                break;
            }
            LtCutNode tmp = heap[repairIndex];
            heap[repairIndex] = heap[largest];
            heap[largest] = tmp;
            repairIndex = largest;
        }

        LightTreeNode node = lt_get_node(candidate.nodeIndex);
        if (lt_is_leaf(node) || node.leftChild < 0 || node.rightChild < 0) {
            lt_heap_push(heap, heapCount, candidate);
            break;
        }

        lt_heap_push(heap, heapCount, lt_make_cut_node(node.leftChild, shadingPos, shadingNormal, mappedNormal, albedoColor));
        lt_heap_push(heap, heapCount, lt_make_cut_node(node.rightChild, shadingPos, shadingNormal, mappedNormal, albedoColor));
    }

    while (heapCount > 0 && result.count < lt_max_cut_nodes) {
        LtCutNode candidate = lt_heap_pop(heap, heapCount);
        result.nodes[result.count++] = candidate;
        result.totalEstimate += candidate.estimate;
        result.totalError += candidate.error;
    }

    return result;
}

float lt_light_orientation_term(Light light, vec3 lightDirection) {
    float oriented = max(dot(light.emissionAxis, -lightDirection), 0.0f);
    if (light.orientationSpread >= 3.0f) {
        return 1.0f;
    }
    return max(oriented, 0.1f);
}

float lt_leaf_light_importance(Light light, vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor) {
    vec3 toLight = light.position - shadingPos;
    float distSq = max(dot(toLight, toLight), lt_min_distance_sq);
    vec3 lightDir = normalize(toLight);
    vec3 geomN = normalize(shadingNormal);
    vec3 mapN = normalize(mappedNormal);
    float mappedAgreement = clamp(dot(geomN, mapN), 0.0f, 1.0f);
    float normalVariation = 1.0f - mappedAgreement;
    float diffuseFacing = clamp(dot(mapN, lightDir), 0.0f, 1.0f);
    float albedoWeight = clamp(dot(albedoColor, vec3(0.2126f, 0.7152f, 0.0722f)), 0.05f, 1.0f);
    float incident = albedoWeight * mix(diffuseFacing, max(diffuseFacing, 0.25f), normalVariation);
    float orientation = lt_light_orientation_term(light, lightDir);
    return max(light.intensity * orientation * max(incident, 0.05f) / distSq, lt_min_node_error);
}

float lt_lightcut_cluster_error(LightTreeNode node, vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor) {
    float estimate = lt_node_importance(node, shadingPos, shadingNormal, mappedNormal, albedoColor);
    float upperBound = lt_node_error_bound(node, shadingPos, shadingNormal);
    return max(upperBound - estimate, 0.0f);
}

float lt_leaf_variance_measure(LightTreeNode leaf, vec3 shadingPos) {
    vec3 center = lt_node_centroid(leaf);
    float distanceToCenter = max(length(center - shadingPos), 1e-4f);
    float minDistance = max(distanceToCenter - leaf.clusterRadius, 1e-3f);
    float maxDistance = max(distanceToCenter + leaf.clusterRadius, minDistance + 1e-3f);
    float geomMean = 1.0f / max(minDistance * maxDistance, 1e-4f);
    float geomVariance = max((maxDistance * maxDistance + maxDistance * minDistance + minDistance * minDistance)
        / (3.0f * max(minDistance * minDistance * maxDistance * maxDistance, 1e-4f)) - geomMean * geomMean, 0.0f);
    float energyVariance = max(leaf.errorBound, 0.0f) * max(leaf.totalIntensity, 0.0f);
    float sigmaSq = (energyVariance * geomVariance + energyVariance * geomMean * geomMean + leaf.totalIntensity * leaf.totalIntensity * geomVariance)
        * float(max(leaf.leafCount, 1) * max(leaf.leafCount, 1));
    return 1.0f / pow(1.0f + sqrt(max(sigmaSq, 0.0f)), 0.25f);
}

bool lt_should_split_candidate(LightTreeNode node, vec3 shadingPos) {
    if (!lt_is_leaf(node) || node.leafCount <= 1) {
        return false;
    }
    return lt_leaf_variance_measure(node, shadingPos) < 0.45f;
}

LtCutResult lt_build_candidate_cut(vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor, int refinementBudget) {
    LtCutResult cut = lt_build_cut(shadingPos, shadingNormal, mappedNormal, albedoColor, refinementBudget);
    if (cut.count <= 0) {
        return cut;
    }

    bool changed = true;
    while (changed && cut.count < lt_max_cut_nodes) {
        changed = false;
        for (int i = 0; i < cut.count && cut.count < lt_max_cut_nodes; i++) {
            LightTreeNode node = lt_get_node(cut.nodes[i].nodeIndex);
            float clusterError = lt_lightcut_cluster_error(node, shadingPos, shadingNormal, mappedNormal, albedoColor);
            bool shouldSplitLeaf = lt_should_split_candidate(node, shadingPos);
            bool shouldSplitInterior = !lt_is_leaf(node) && clusterError > lt_cut_error_ratio * max(cut.totalEstimate, lt_min_node_error);
            if ((!shouldSplitLeaf && !shouldSplitInterior) || node.leftChild < 0 || node.rightChild < 0) {
                continue;
            }

            LtCutNode left = lt_make_cut_node(node.leftChild, shadingPos, shadingNormal, mappedNormal, albedoColor);
            LtCutNode right = lt_make_cut_node(node.rightChild, shadingPos, shadingNormal, mappedNormal, albedoColor);
            cut.totalEstimate += left.estimate + right.estimate - cut.nodes[i].estimate;
            cut.totalError += left.error + right.error - cut.nodes[i].error;
            cut.nodes[i] = left;
            for (int j = cut.count; j > i + 1; j--) {
                cut.nodes[j] = cut.nodes[j - 1];
            }
            cut.nodes[i + 1] = right;
            cut.count++;
            changed = true;
        }
    }

    return cut;
}

bool lt_node_contains_light(LightTreeNode node, int lightIndex) {
    if (lightIndex < 0) {
        return false;
    }

    const int lt_contains_stack_capacity = 64;
    int pendingNodes[lt_contains_stack_capacity];
    int pendingCount = 0;
    LightTreeNode currentNode = node;

    for (int iteration = 0; iteration < lt_contains_stack_capacity; iteration++) {
        if (lt_is_leaf(currentNode)) {
            for (int i = 0; i < currentNode.leafCount; i++) {
                if (light_tree_indices[currentNode.leafStart + i] == lightIndex) {
                    return true;
                }
            }
        } else {
            if (currentNode.rightChild >= 0 && pendingCount < lt_contains_stack_capacity) {
                pendingNodes[pendingCount++] = currentNode.rightChild;
            }
            if (currentNode.leftChild >= 0) {
                currentNode = lt_get_node(currentNode.leftChild);
                continue;
            }
        }

        if (pendingCount <= 0) {
            break;
        }
        currentNode = lt_get_node(pendingNodes[--pendingCount]);
    }

    return false;
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
            lightPdf = max(pathPdf * leafPdf, 1e-6f);
            return lightIndex >= 0 && leafPdf > 0.0f;
        }
        if (current.leftChild < 0 || current.rightChild < 0) {
            return false;
        }

        LightTreeNode leftNode = lt_get_node(current.leftChild);
        LightTreeNode rightNode = lt_get_node(current.rightChild);
        float leftImportance = lt_node_importance(leftNode, shadingPos, shadingNormal, mappedNormal, albedoColor);
        float rightImportance = lt_node_importance(rightNode, shadingPos, shadingNormal, mappedNormal, albedoColor);
        float weightSum = leftImportance + rightImportance;
        if (weightSum <= 0.0f) {
            float branchPdf = 0.5f;
            pathPdf *= branchPdf;
            current = (ph_rand_pcg(rng) & 1u) == 0u ? leftNode : rightNode;
            continue;
        }

        float leftPdfBranch = leftImportance / weightSum;
        float xi = float(ph_rand_pcg(rng)) / 4294967295.0f;
        bool chooseLeft = xi < leftPdfBranch;
        pathPdf *= chooseLeft ? leftPdfBranch : (1.0f - leftPdfBranch);
        current = chooseLeft ? leftNode : rightNode;
    }
    return false;
}

bool lt_sample_cut_node(LtCutResult cut, vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor, inout uint rng, out int lightIndex, out float proposalPdf) {
    lightIndex = -1;
    proposalPdf = 0.0f;
    if (cut.count <= 0 || cut.totalEstimate <= 0.0f) {
        return false;
    }

    float target = float(ph_rand_pcg(rng)) / 4294967295.0f * cut.totalEstimate;
    float cumulative = 0.0f;
    for (int i = 0; i < cut.count; i++) {
        LtCutNode candidate = cut.nodes[i];
        cumulative += candidate.estimate;
        if (cumulative < target && i < cut.count - 1) {
            continue;
        }

        LightTreeNode node = lt_get_node(candidate.nodeIndex);
        if (!lt_sample_light_from_node(node, shadingPos, shadingNormal, mappedNormal, albedoColor, rng, lightIndex, proposalPdf)) {
            return false;
        }
        if (lightIndex < 0) {
            return false;
        }

        proposalPdf = max(lt_cut_light_pdf(cut, shadingPos, shadingNormal, mappedNormal, albedoColor, lightIndex), 1e-6f);
        return true;
    }

    return false;
}

float lt_light_pdf_in_leaf(LightTreeNode leaf, vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor, int lightIndex) {
    if (!lt_is_leaf(leaf) || leaf.leafCount <= 0 || lightIndex < 0) {
        return 0.0f;
    }

    float totalImportance = 0.0f;
    float selectedImportance = 0.0f;
    for (int i = 0; i < leaf.leafCount; i++) {
        int idx = light_tree_indices[leaf.leafStart + i];
        Light light = load_light(idx);
        float importance = lt_leaf_light_importance(light, shadingPos, shadingNormal, mappedNormal, albedoColor);
        totalImportance += importance;
        if (idx == lightIndex) {
            selectedImportance = importance;
        }
    }

    if (selectedImportance <= 0.0f) {
        return 0.0f;
    }
    if (totalImportance <= 0.0f) {
        return 0.0f;
    }

    return selectedImportance / totalImportance;
}

float lt_light_pdf_in_node(LightTreeNode node, vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor, int lightIndex) {
    if (lightIndex < 0) {
        return 0.0f;
    }

    LightTreeNode currentNode = node;
    float branchPdf = 1.0f;

    for (int depth = 0; depth < ph_light_tree_node_count; depth++) {
        if (lt_is_leaf(currentNode)) {
            return branchPdf * lt_light_pdf_in_leaf(currentNode, shadingPos, shadingNormal, mappedNormal, albedoColor, lightIndex);
        }
        if (currentNode.leftChild < 0 || currentNode.rightChild < 0) {
            return 0.0f;
        }

        LightTreeNode leftNode = lt_get_node(currentNode.leftChild);
        LightTreeNode rightNode = lt_get_node(currentNode.rightChild);

        bool lightInLeft = lt_node_contains_light(leftNode, lightIndex);
        bool lightInRight = lt_node_contains_light(rightNode, lightIndex);
        if (!lightInLeft && !lightInRight) {
            return 0.0f;
        }

        float leftImportance = lt_node_importance(leftNode, shadingPos, shadingNormal, mappedNormal, albedoColor);
        float rightImportance = lt_node_importance(rightNode, shadingPos, shadingNormal, mappedNormal, albedoColor);
        float weightSum = leftImportance + rightImportance;

        float nextBranchPdf;
        if (weightSum <= 0.0f) {
            nextBranchPdf = 0.5f;
        } else if (lightInLeft && !lightInRight) {
            nextBranchPdf = leftImportance / weightSum;
        } else if (!lightInLeft && lightInRight) {
            nextBranchPdf = rightImportance / weightSum;
        } else {
            nextBranchPdf = 0.5f;
        }

        if (nextBranchPdf <= 0.0f) {
            return 0.0f;
        }

        branchPdf *= nextBranchPdf;
        currentNode = lightInLeft ? leftNode : rightNode;
    }

    return 0.0f;
}

float lt_cut_light_pdf(LtCutResult cut, vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor, int lightIndex) {
    if (cut.count <= 0 || cut.totalEstimate <= 0.0f || lightIndex < 0) {
        return 0.0f;
    }

    float pdf = 0.0f;
    for (int i = 0; i < cut.count; i++) {
        LtCutNode candidate = cut.nodes[i];
        if (candidate.estimate <= 0.0f) {
            continue;
        }

        LightTreeNode node = lt_get_node(candidate.nodeIndex);
        float nodeSelectionPdf = candidate.estimate / cut.totalEstimate;
        float nodeLightPdf = lt_light_pdf_in_node(node, shadingPos, shadingNormal, mappedNormal, albedoColor, lightIndex);
        pdf += nodeSelectionPdf * nodeLightPdf;
    }

    return pdf;
}

void lt_select_light_from_leaf(LightTreeNode leaf, vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor, inout uint rng, out int lightIndex, out float pdf) {
    lightIndex = -1;
    pdf = 0.0f;
    if (!lt_is_leaf(leaf) || leaf.leafCount <= 0) {
        return;
    }

    float totalImportance = 0.0f;
    for (int i = 0; i < leaf.leafCount; i++) {
        int idx = light_tree_indices[leaf.leafStart + i];
        Light light = load_light(idx);
        totalImportance += lt_leaf_light_importance(light, shadingPos, shadingNormal, mappedNormal, albedoColor);
    }

    if (totalImportance <= 0.0f) {
        lightIndex = light_tree_indices[leaf.leafStart];
        pdf = 1.0f;
        return;
    }

    float target = float(ph_rand_pcg(rng)) / 4294967295.0f * totalImportance;
    float cumulative = 0.0f;
    for (int i = 0; i < leaf.leafCount; i++) {
        int idx = light_tree_indices[leaf.leafStart + i];
        Light light = load_light(idx);
        float importance = lt_leaf_light_importance(light, shadingPos, shadingNormal, mappedNormal, albedoColor);
        cumulative += importance;
        if (cumulative >= target || i == leaf.leafCount - 1) {
            lightIndex = idx;
            pdf = max(importance / totalImportance, 1e-6f);
            return;
        }
    }
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

    float orientationTerm = lt_light_orientation_term(light, lightDirection);
    vec3 radiance = light.color * light.intensity * orientationTerm / attenuation;
    return max(radiance * ndotl, vec3(0.0f));
}

#endif




