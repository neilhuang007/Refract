"""Preprocess Photonic shaders and run glslangValidator to surface GLSL
syntax issues. Many references resolve at runtime through Iris shader-pack
injection (uniforms, vertex outputs like tex_coord). We append a prelude of
declarations so glslangValidator focuses on semantic errors in our code.
"""
import os
import sys
import subprocess
import importlib.util

ROOT_DIR = os.path.abspath(os.path.dirname(__file__) + '/..')
SHADERS = os.path.join(ROOT_DIR, 'assets/photonic/shaders')
RUN = os.path.join(ROOT_DIR, 'run')
os.makedirs(RUN, exist_ok=True)

# Reuse existing preproc logic
spec = importlib.util.spec_from_file_location('preproc', os.path.join(ROOT_DIR, 'scripts/preproc.py'))
preproc = importlib.util.module_from_spec(spec)
# Prevent the bottom script block from running on import by nulling sys.argv briefly.
_argv = sys.argv
sys.argv = ['preproc']
try:
    spec.loader.exec_module(preproc)
finally:
    sys.argv = _argv

PRELUDE = r"""
// --- shader-pack injected declarations (stubs for standalone validation) ---
// Only declare symbols that the shader code *reads* but Iris normally injects.
// Intentionally omit: ph_light_count, world_offset, and any other uniform that
// the shader or its includes declare with a full `uniform` line (redefining them
// here would trigger glslang redefinition errors).
in vec2 texcoord;
uniform int   frameCounter;
uniform int   frameTime;
uniform int   temporalFrameIndex;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform float shadowFade;
uniform float viewWidth;
uniform float viewHeight;
uniform float near;
uniform float far;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D noisetex;
uniform sampler2D gcolor;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;
uniform mat4 shadowProjection;
uniform mat4 shadowModelView;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform vec3 eyePosition;
uniform vec3 relativeEyePosition;
#define Light RAB_LightInfo
#define modelview_projection ph_current_modelview_projection()
#define previous_modelview_projection ph_previous_modelview_projection()
#define world_camera_position cameraPosition
#define previous_world_camera_position previousCameraPosition
"""

def preprocess(entry_rel):
    entry = os.path.join(SHADERS, entry_rel)
    defines = {}
    lines = preproc.expand(entry, defines)
    return '\n'.join(lines)

import re as _re
_FLOAT_F_RE = _re.compile(r'(?<![A-Za-z_0-9.+-])((?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?)f\b')

def canonicalize_float_literals(text):
    """Iris/Sodium's parser accepts Java-style `0f`, `1f`, `1.0f` as float literals,
    but standard GLSL does not. Translate `<digits>f` -> `<digits>.0` so standalone
    syntax validation with glslangValidator succeeds. Real shaders are unchanged.
    """
    def replace(match):
        literal = match.group(1)
        if '.' in literal or 'e' in literal.lower():
            return literal
        return literal + '.0'

    return _FLOAT_F_RE.sub(replace, text)

def write_preprocessed(entry_rel, out_name):
    text = preprocess(entry_rel)
    text = canonicalize_float_literals(text)
    path = os.path.join(RUN, out_name)
    # Insert prelude after the #version line if present.
    if text.lstrip().startswith('#version'):
        head, _, tail = text.partition('\n')
        text = head + '\n' + PRELUDE + '\n' + tail
    else:
        text = '#version 430\n' + PRELUDE + '\n' + text
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)
    return path

def run_glslang(path, stage='frag'):
    # Pure GLSL syntax check (no SPIR-V target). OpenGL driver-style semantics.
    cp = subprocess.run(
        ['glslangValidator', '-S', stage, path],
        capture_output=True, text=True
    )
    return cp.returncode, cp.stdout + cp.stderr

TARGETS = [
    ('lighttree/LightingPasses/DI/GenerateInitialSamples.fsh', 'frag'),
    ('lighttree/LightingPasses/DI/TemporalReprojection.fsh', 'frag'),
    ('lighttree/LightingPasses/DI/TemporalBinningOffsets.fsh', 'frag'),
    ('lighttree/LightingPasses/DI/TemporalBinning.fsh', 'frag'),
    ('lighttree/LightingPasses/DI/CollectTemporalSamples.fsh', 'frag'),
    ('lighttree/LightingPasses/DI/ScatterTemporalResolve.fsh', 'frag'),
    ('lighttree/LightingPasses/DI/MultiTemporalReprojection.fsh', 'frag'),
    ('lighttree/LightingPasses/DI/MultiTemporalBinning.fsh', 'frag'),
    ('lighttree/LightingPasses/DI/MultiTemporalBinningOffsets.fsh', 'frag'),
    ('lighttree/LightingPasses/DI/MultiScatterTemporalResampling.fsh', 'frag'),
    ('lighttree/LightingPasses/DI/ScatterBackupTemporalResampling.fsh', 'frag'),
    ('lighttree/LightingPasses/DI/RobustReuseOptimization.fsh', 'frag'),
    ('lighttree/LightingPasses/DI/GatherTemporalResampling.fsh', 'frag'),
    ('lighttree/LightingPasses/DI/SpatialResampling.fsh', 'frag'),
    ('lighttree/LightingPasses/DI/ShadeSamples.fsh', 'frag'),
    ('lighttree/LightingPasses/DI/ShadeSamplesLighting.fsh', 'frag'),
    ('lighttree/LightingPasses/DI/ShadeSamplesReservoir.fsh', 'frag'),
    ('lighttree/light_tree_accumulation.fsh', 'frag'),
]

def main():
    any_fail = False
    for rel, stage in TARGETS:
        name = os.path.basename(rel).replace('.fsh', '.preproc.glsl').replace('.vsh', '.preproc.glsl')
        path = write_preprocessed(rel, name)
        rc, out = run_glslang(path, stage)
        print('=' * 80)
        print(rel, '->', 'OK' if rc == 0 else 'FAIL')
        if rc != 0:
            any_fail = True
            # Show first ~80 lines of diagnostics
            for line in out.splitlines()[:80]:
                print('   ', line)
    print('\nSummary:', 'ALL PASS' if not any_fail else 'ERRORS ABOVE')
    sys.exit(0 if not any_fail else 1)

if __name__ == '__main__':
    main()
