import re
import os
import sys

files = [
    'assets/photonic/shaders/lighttree/reuse_bridge.glsl',
    'assets/photonic/shaders/lighttree/restir_gi_initial_sampling_impl.glsl',
    'assets/photonic/shaders/lighttree/restir_di_initial_impl.glsl',
    'assets/photonic/shaders/lighttree/restir_di_temporal_impl.glsl',
    'assets/photonic/shaders/lighttree/restir_di_scatter_impl.glsl',
    'assets/photonic/shaders/lighttree/LightingPasses/DI/GenerateInitialSamples.fsh',
]

for f in files:
    if not os.path.exists(f):
        continue
    ifs = 0
    endifs = 0
    depth = 0
    max_depth = 0
    err_line = None
    with open(f, 'r', encoding='utf-8') as fh:
        for i, L in enumerate(fh, 1):
            if re.match(r'\s*#(if|ifdef|ifndef)\b', L):
                ifs += 1
                depth += 1
                max_depth = max(max_depth, depth)
            elif re.match(r'\s*#endif\b', L):
                endifs += 1
                depth -= 1
                if depth < 0 and err_line is None:
                    err_line = i
    print(f"{f}: if={ifs} endif={endifs} final_depth={depth} max_depth={max_depth} err_line={err_line}")
