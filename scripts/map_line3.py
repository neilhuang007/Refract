#!/usr/bin/env python3
"""Map NV line number with multiple strategies."""
with open('run/preprocessed_GenerateInitialSamples.glsl', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Strategy A: keep all lines, no stripping
# NV 3258 -> our 3258 directly

# Strategy B: strip /* */ block only
in_block = False
b_mapping = []
b_out = []
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
    if out.rstrip() != '':
        b_mapping.append(i); b_out.append(out.rstrip())

# Strategy C: strip // only, keep blank
c_mapping = []
c_out = []
for i, l in enumerate(lines, 1):
    idx = l.find('//')
    if idx >= 0:
        l2 = l[:idx]
    else:
        l2 = l
    if l2.rstrip() != '':
        c_mapping.append(i); c_out.append(l2.rstrip())

# Strategy D: strip both, drop blanks
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

# Strategy E: strip // and block comments but keep blanks
e_mapping = []
e_out = []
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
    e_mapping.append(i); e_out.append(out.rstrip())

print(f"Total lines: A={len(lines)} B={len(b_out)} C={len(c_out)} D={len(d_out)} E={len(e_out)}")
nv = 3258
print(f"\nNV {nv}:")
print(f"A: {lines[nv-1].rstrip()[:80]}")
if nv <= len(b_out): print(f"B(strip blocks+blanks): orig={b_mapping[nv-1]}: {b_out[nv-1][:80]}")
if nv <= len(c_out): print(f"C(strip //+blanks): orig={c_mapping[nv-1]}: {c_out[nv-1][:80]}")
if nv <= len(d_out): print(f"D(strip all+blanks): orig={d_mapping[nv-1]}: {d_out[nv-1][:80]}")
if nv <= len(e_out): print(f"E(strip comments keep blanks): orig={e_mapping[nv-1]}: {e_out[nv-1][:80]}")
