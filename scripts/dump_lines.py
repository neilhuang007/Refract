import re
import sys

text = open('run/preprocessed_GenerateInitialSamples.glsl', 'r', encoding='utf-8').read()

# Strip comments but keep line count — GLSL compilers usually count lines including comments
# Iris's error line numbers should correspond to the shader string sent to GL
# Let's assume iris sends the file as-is with comments
# But the error at line 3258 shows 'float canonicalWeight;' in our raw file which isn't the error site.

# Actually iris might strip the BEGIN/END comments. Let me check what iris does.
# For now, just dump lines 3250-3280 and 5630-5660
for start, end in [(3250, 3280), (5630, 5660), (5085, 5120)]:
    print(f"\n=== lines {start}-{end} ===")
    for i, l in enumerate(text.split('\n')[start-1:end], start):
        print(f"{i}: {l}")
