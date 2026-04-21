import re

with open('assets/photonic/shaders/lighttree/reuse_bridge.glsl', 'r', encoding='utf-8') as fh:
    lines = fh.readlines()

depth = 0
stack = []
for i, L in enumerate(lines, 1):
    s = L.strip()
    if re.match(r'#(if|ifdef|ifndef)\b', s):
        depth += 1
        stack.append((i, s[:80], depth))
        print(f"  L{i:5}: +{depth} {s[:80]}")
    elif s.startswith('#endif'):
        opener = stack.pop() if stack else None
        print(f"  L{i:5}: -{depth} {s[:80]}  (closes L{opener[0] if opener else '?'})")
        depth -= 1
    elif s.startswith('#else') or s.startswith('#elif'):
        print(f"  L{i:5}:  ={depth} {s[:80]}")

print(f"\nFinal depth: {depth}")
print(f"\nUnclosed:")
for o in stack:
    print(f"  {o}")
