#!/usr/bin/env python3
"""Find non-ASCII characters across all shader files included in the preprocessed one."""
import os
ROOT = 'assets/photonic/shaders'
count_files = 0
count_non_ascii = 0
files_with_nonascii = []
for root, _, files in os.walk(ROOT):
    for f in files:
        if f.endswith(('.glsl', '.fsh', '.vsh')):
            count_files += 1
            path = os.path.join(root, f)
            with open(path, 'rb') as fp:
                data = fp.read()
            if any(b > 127 for b in data):
                count_non_ascii += 1
                files_with_nonascii.append(path)
                # Show first few locations
                locs = []
                for i, b in enumerate(data):
                    if b > 127:
                        line = data[:i].count(b'\n') + 1
                        locs.append((i, line, b))
                        if len(locs) >= 3: break
                print(f"{path}: {len(locs)} non-ASCII bytes (first {locs})")
print(f"\n{count_non_ascii}/{count_files} files have non-ASCII chars")
