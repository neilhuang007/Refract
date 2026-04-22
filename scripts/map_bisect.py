#!/usr/bin/env python3
"""Check NV line 3189 using strategies."""
with open('run/preprocessed_GenerateInitialSamples.glsl', 'r', encoding='utf-8') as f:
    lines = f.readlines()

d_mapping = []
d_out = []
in_block = False
for i, l in enumerate(lines, 1):
    s = l
    out = ''
    j = 0
    while j < len(s):
        if not in_block and s[j:j+2] == '/*':
            in_block = True; j += 2
        elif in_block and s[j:j+2] == '*/':
            in_block = False; j += 2
        elif in_block:
            j += 1
        else:
            out += s[j]; j += 1
    idx = out.find('//')
    if idx >= 0:
        out = out[:idx]
    if out.rstrip() != '':
        d_mapping.append(i); d_out.append(out.rstrip())

for nv in [3189, 3215, 3217, 3231, 3241, 3277, 3327]:
    if nv <= len(d_out):
        print(f"NV {nv} -> orig {d_mapping[nv-1]}: {d_out[nv-1][:100]}")
