import re
import sys
from collections import defaultdict

# Run preproc first
import subprocess
subprocess.check_call([sys.executable, 'scripts/preproc.py'])

text = open('run/preprocessed_GenerateInitialSamples.glsl', 'r', encoding='utf-8').read()
lines = text.split('\n')

# Remove block comments
text_no_block = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
# Remove line comments (but keep line count)
clean_lines = []
for l in text_no_block.split('\n'):
    # remove // comments
    if '//' in l:
        # handle strings? not common in GLSL
        idx = l.find('//')
        l = l[:idx]
    clean_lines.append(l)

# Match function definitions: return_type name(...) { 
# Must have { after ) not ;
full_text = '\n'.join(clean_lines)
# pattern: word+ space word ( ... ) { -- definition
# pattern: word+ space word ( ... ) ; -- declaration
func_pattern = re.compile(r'(?m)^\s*([A-Za-z_][A-Za-z0-9_]*(?:\s*\*)?)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)\s*(;|\{)', re.DOTALL)

# Better: find all occurrences of `name(` preceded by a type name at start of line or after newline
# Use a custom parse
func_defs = defaultdict(list)
func_decls = defaultdict(list)

# Simple scanner: find `name ( args )` and check for { or ;
pattern2 = re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(', re.MULTILINE)

lines_clean = full_text.split('\n')
i = 0
while i < len(lines_clean):
    l = lines_clean[i]
    m = re.match(r'^\s*([A-Za-z_][A-Za-z0-9_<>]*)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(', l)
    if m:
        ret_type = m.group(1)
        fname = m.group(2)
        # skip keywords
        if ret_type in ('if', 'while', 'for', 'return', 'switch', 'else', 'do', 'struct', 'const', 'uniform', 'varying', 'in', 'out', 'inout', 'layout'):
            i += 1
            continue
        # find matching ) and following { or ;
        joined = l
        j = i
        while ')' not in joined and j < len(lines_clean) - 1:
            j += 1
            joined += ' ' + lines_clean[j]
        # get text after last )
        idx = joined.rfind(')')
        tail = joined[idx+1:].lstrip()
        # also check following lines if tail empty
        if not tail.strip() and j < len(lines_clean) - 1:
            k = j + 1
            while k < len(lines_clean) and not lines_clean[k].strip():
                k += 1
            if k < len(lines_clean):
                tail = lines_clean[k].strip()
        if tail.startswith('{'):
            func_defs[fname].append(i + 1)
        elif tail.startswith(';'):
            func_decls[fname].append(i + 1)
    i += 1

print("=== DUPLICATED DEFINITIONS ===")
for fname, lines in sorted(func_defs.items()):
    if len(lines) > 1:
        print(f"{fname}: lines {lines}")

print()
print("=== DUPLICATED DECLARATIONS ===")
for fname, lines in sorted(func_decls.items()):
    if len(lines) > 1:
        print(f"{fname}: lines {lines}")

print()
print("=== DECL THEN DEF (OK) ===")
for fname in sorted(set(func_decls.keys()) & set(func_defs.keys())):
    print(f"{fname}: decl={func_decls[fname]} def={func_defs[fname]}")
