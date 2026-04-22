import re
import sys

lines = open('run/preprocessed_GenerateInitialSamples.glsl', 'r', encoding='utf-8').read().split('\n')
text = '\n'.join(lines)
# Try scenario A: keep all lines (none stripped)
# Try scenario B: strip blank only
# Try scenario C: strip comments + blank
# Iris may also strip our `// BEGIN ...` markers

# Strategy: take error line 3346 (undefined lt_evaluate_ggx_vndf_pdf) — this means
# the BODY of a function that calls lt_evaluate_ggx_vndf_pdf was being parsed
# at that line number. The function that CALLS lt_evaluate_ggx_vndf_pdf is
# RAB_SurfaceEvaluateBrdfPdf at preprocessed line 5723. If error at 3346
# corresponds to file line 5733 that's off by ~2387 lines stripped.

# Let's simply test: count lines that Iris likely sees (stripping blank + comments + //)
# First, compute mapping where line N error corresponds to Kth iris-significant line
text_no_block = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
newlines = text_no_block.split('\n')

# keep only significant lines
compacted = []
for i, l in enumerate(newlines, 1):
    s = l.strip()
    if s.startswith('//'):
        continue
    if not s:
        continue
    compacted.append((i, l))

# The error talks about line 3346 being "lt_evaluate_ggx_vndf_pdf" undefined
# - that means lt_evaluate_ggx_vndf_pdf is CALLED at error line 3346 (not defined)
# - In preprocessed file RAB_SurfaceEvaluateBrdfPdf is line 5723-5735, with the call at 5733
# Let's see what line 3346 maps to in compacted:
targets = [3258, 3284, 3285, 3286, 3346, 3396, 3428, 3429, 3442, 3443]
for t in targets:
    if t-1 < len(compacted):
        orig_line, content = compacted[t-1]
        print(f"Error line {t} -> orig line {orig_line}: {content[:100]}")

print("---")
# Also print: when calling lt_evaluate_ggx_vndf_pdf (preprocessed 5733),
# find its compacted idx
for idx, (orig, c) in enumerate(compacted, 1):
    if 'lt_evaluate_ggx_vndf_pdf' in c:
        print(f"compacted idx {idx}, orig line {orig}: {c[:100]}")
