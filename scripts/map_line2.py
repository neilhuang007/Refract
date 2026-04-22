#!/usr/bin/env python3
"""Map NV line number assuming comments and blanks are stripped."""
with open('run/preprocessed_GenerateInitialSamples.glsl', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Strip // line comments and /* */ block comments, strip blank lines
stripped_mapping = []  # indices: iris line -> original
in_block = False
iris_lines = []
for i, l in enumerate(lines, 1):
    s = l
    out = ''
    j = 0
    while j < len(s):
        if not in_block and s[j:j+2] == '/*':
            in_block = True
            j += 2
        elif in_block and s[j:j+2] == '*/':
            in_block = False
            j += 2
        elif in_block:
            j += 1
        else:
            out += s[j]
            j += 1
    idx = out.find('//')
    if idx >= 0:
        out = out[:idx]
    rstr = out.rstrip()
    if rstr == '':
        continue
    iris_lines.append(rstr)
    stripped_mapping.append(i)

print(f"Total iris lines: {len(iris_lines)}")
for nv in [3258, 3284, 3286, 3346, 3396, 3420, 3437]:
    if nv <= len(iris_lines):
        orig = stripped_mapping[nv-1]
        print(f"NV {nv} -> orig {orig}: {iris_lines[nv-1][:100]}")
