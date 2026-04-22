#!/usr/bin/env python3
"""Map NV line number to preprocessed file line number."""
with open('run/preprocessed_GenerateInitialSamples.glsl', 'r', encoding='utf-8') as f:
    lines = f.readlines()

nv_lines = [3258, 3284, 3286, 3346]
for nv in nv_lines:
    if nv <= len(lines):
        print(f"NV {nv}: {lines[nv-1].rstrip()}")
