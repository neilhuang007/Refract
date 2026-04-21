import os
import re
import sys

ROOT = os.path.abspath('assets/photonic/shaders')

def resolve(path, cur_dir):
    # #include "/photonics/..." means absolute from ROOT
    if path.startswith('/'):
        return os.path.join(ROOT, path.lstrip('/'))
    # relative
    return os.path.join(cur_dir, path)

visited_guards = set()

def expand(file_path, defines, depth=0, log=None):
    if depth > 50:
        print(f"!! include depth too deep for {file_path}")
        return []
    if not os.path.exists(file_path):
        return []
    cur_dir = os.path.dirname(file_path)
    out = []
    if_stack = []  # list of (kept, ever_true)
    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
        for ln, line in enumerate(f, 1):
            stripped = line.strip()
            keep = all(s[0] for s in if_stack)

            # handle preprocessor first
            m = re.match(r'#\s*(include|define|undef|ifdef|ifndef|if|else|elif|endif|error|pragma)\b(.*)$', stripped)
            if m:
                directive = m.group(1)
                rest = m.group(2).strip()
                if directive == 'include' and keep:
                    inc_m = re.match(r'"([^"]+)"|<([^>]+)>', rest)
                    if inc_m:
                        inc_path = inc_m.group(1) or inc_m.group(2)
                        inc_file = resolve(inc_path.strip().lstrip('/photonics/').lstrip('/'), cur_dir)
                        if inc_path.startswith('/photonics/'):
                            inc_file = os.path.join(ROOT, inc_path[len('/photonics/'):])
                        elif inc_path.startswith('/'):
                            inc_file = os.path.join(ROOT, inc_path[1:])
                        else:
                            inc_file = os.path.join(cur_dir, inc_path)
                        inc_file = os.path.normpath(inc_file)
                        out.append(f"// BEGIN {inc_file}")
                        out.extend(expand(inc_file, defines, depth+1, log))
                        out.append(f"// END   {inc_file}")
                elif directive == 'define' and keep:
                    dm = re.match(r'(\w+)(\s+.*)?', rest)
                    if dm:
                        defines[dm.group(1)] = (dm.group(2) or '').strip()
                elif directive == 'undef' and keep:
                    defines.pop(rest.strip(), None)
                elif directive == 'ifdef':
                    k = rest.strip()
                    cond = k in defines
                    if_stack.append([keep and cond, cond])
                elif directive == 'ifndef':
                    k = rest.strip()
                    cond = k not in defines
                    if_stack.append([keep and cond, cond])
                elif directive == 'if':
                    # crude: support defined(X), !defined(X), &&, ||
                    expr = rest.strip()
                    try:
                        py = expr
                        py = re.sub(r'defined\s*\(\s*(\w+)\s*\)', lambda m: 'True' if m.group(1) in defines else 'False', py)
                        py = py.replace('!', ' not ').replace('&&', ' and ').replace('||', ' or ')
                        py = re.sub(r'\b(\w+)\b', lambda m: 'True' if m.group(1) in defines and defines[m.group(1)] != '0' else m.group(1), py)
                        py = re.sub(r'\b\w+\b', lambda m: '0' if m.group(0) not in ('True','False','and','or','not') and not m.group(0).isdigit() else m.group(0), py)
                        cond = bool(eval(py))
                    except:
                        cond = False
                    if_stack.append([keep and cond, cond])
                elif directive == 'else':
                    if if_stack:
                        prev = if_stack[-1]
                        new_keep = all(s[0] for s in if_stack[:-1]) and (not prev[1])
                        if_stack[-1] = [new_keep, True]
                elif directive == 'elif':
                    pass  # lazy
                elif directive == 'endif':
                    if if_stack:
                        if_stack.pop()
                continue

            if keep:
                out.append(line.rstrip('\n'))
    return out

entry = 'assets/photonic/shaders/lighttree/LightingPasses/DI/GenerateInitialSamples.fsh'
# Iris auto-defines a pass-specific macro?
defines = {}
lines = expand(entry, defines)
out = 'run/preprocessed_GenerateInitialSamples.glsl'
with open(out, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))
print(f"Wrote {out} with {len(lines)} lines")
