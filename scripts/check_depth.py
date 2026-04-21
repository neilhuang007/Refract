import re
import sys

depth = 0
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    for i, line in enumerate(f, 1):
        s = line.strip()
        if re.match(r'^#\s*(if|ifdef|ifndef)\b', s):
            depth += 1
            print(f'{i:5d} DEPTH {depth}: {s[:80]}')
        elif re.match(r'^#\s*else\b', s):
            print(f'{i:5d} DEPTH {depth}  ELSE: {s[:80]}')
        elif re.match(r'^#\s*elif\b', s):
            print(f'{i:5d} DEPTH {depth}  ELIF: {s[:80]}')
        elif re.match(r'^#\s*endif\b', s):
            print(f'{i:5d} DEPTH {depth} ENDIF: {s[:80]}')
            depth -= 1
print(f'FINAL DEPTH: {depth}')
