#!/usr/bin/env python3
"""
Checks #if/#ifdef/#ifndef vs #endif balance across specified GLSL files.
Also flags orphan #else directives (not between a matching pair).
Read-only: does not modify files.
"""

import os
import re
import sys

SHADER_ROOT = r"E:\RE\photonics\assets\photonic\shaders"

# Explicit parent files
PARENT_FILES = [
    os.path.join(SHADER_ROOT, "common", "header.glsl"),
    os.path.join(SHADER_ROOT, "common", "util.glsl"),
    os.path.join(SHADER_ROOT, "photonics.glsl"),
    os.path.join(SHADER_ROOT, "ph_core.glsl"),
    os.path.join(SHADER_ROOT, "shader_interface.glsl"),
]

# common/impl/*.glsl
COMMON_IMPL_DIR = os.path.join(SHADER_ROOT, "common", "impl")

# lighttree top-level and LightingPasses/DI/
LIGHTTREE_DIR = os.path.join(SHADER_ROOT, "lighttree")
LIGHTING_DI_DIR = os.path.join(LIGHTTREE_DIR, "LightingPasses", "DI")

# Regex: match line starting with optional whitespace, then '#', then optional ws, then directive
RE_IF     = re.compile(r'^\s*#\s*(if|ifdef|ifndef)\b')
RE_ENDIF  = re.compile(r'^\s*#\s*endif\b')
RE_ELSE   = re.compile(r'^\s*#\s*else\b')
RE_ELIF   = re.compile(r'^\s*#\s*elif\b')


def collect_files():
    files = []
    # Parent files
    for p in PARENT_FILES:
        if os.path.isfile(p):
            files.append(p)

    # common/impl/*.glsl
    if os.path.isdir(COMMON_IMPL_DIR):
        for name in sorted(os.listdir(COMMON_IMPL_DIR)):
            full = os.path.join(COMMON_IMPL_DIR, name)
            if os.path.isfile(full) and name.lower().endswith(".glsl"):
                files.append(full)

    # lighttree top-level (all GLSL-family shader files: .glsl, .fsh, .vsh)
    if os.path.isdir(LIGHTTREE_DIR):
        for name in sorted(os.listdir(LIGHTTREE_DIR)):
            full = os.path.join(LIGHTTREE_DIR, name)
            if os.path.isfile(full) and name.lower().split(".")[-1] in ("glsl", "fsh", "vsh"):
                files.append(full)

    # LightingPasses/DI/*
    if os.path.isdir(LIGHTING_DI_DIR):
        for name in sorted(os.listdir(LIGHTING_DI_DIR)):
            full = os.path.join(LIGHTING_DI_DIR, name)
            if os.path.isfile(full) and name.lower().split(".")[-1] in ("glsl", "fsh", "vsh"):
                files.append(full)

    # De-duplicate preserving order
    seen = set()
    unique = []
    for f in files:
        norm = os.path.normcase(os.path.abspath(f))
        if norm not in seen:
            seen.add(norm)
            unique.append(f)
    return unique


def analyze(path):
    """Return dict with counts and orphan_else list (line numbers)."""
    if_count = 0
    endif_count = 0
    orphan_else = []
    stack_depth = 0  # tracks currently open #if blocks at time of #else

    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for lineno, line in enumerate(fh, 1):
                if RE_IF.match(line):
                    if_count += 1
                    stack_depth += 1
                elif RE_ENDIF.match(line):
                    endif_count += 1
                    if stack_depth > 0:
                        stack_depth -= 1
                    # else: underflow — unmatched endif, will be reflected in net count
                elif RE_ELSE.match(line):
                    if stack_depth <= 0:
                        orphan_else.append(lineno)
                # #elif is fine; needs an open block but we don't explicitly flag it
    except OSError as exc:
        return {"error": str(exc)}

    return {
        "if_count": if_count,
        "endif_count": endif_count,
        "net": if_count - endif_count,
        "orphan_else": orphan_else,
    }


def main():
    files = collect_files()

    rows = []
    flagged_net = []
    flagged_else = []

    for f in files:
        rel = os.path.relpath(f, SHADER_ROOT)
        result = analyze(f)
        if "error" in result:
            rows.append((rel, "-", "-", "-", f"ERROR: {result['error']}"))
            continue
        rows.append((
            rel,
            result["if_count"],
            result["endif_count"],
            result["net"],
            ",".join(str(n) for n in result["orphan_else"]) if result["orphan_else"] else "",
        ))
        if result["net"] != 0:
            flagged_net.append((rel, result["net"]))
        if result["orphan_else"]:
            flagged_else.append((rel, result["orphan_else"]))

    # Formatted table
    path_w = max(len(r[0]) for r in rows) if rows else 10
    path_w = max(path_w, len("File"))
    header = f"{'File'.ljust(path_w)}  {'#if*':>5}  {'#endif':>6}  {'NET':>5}  orphan_else_lines"
    sep = "-" * len(header)

    print("GLSL #if / #endif balance report")
    print(f"Shader root: {SHADER_ROOT}")
    print(f"Files analyzed: {len(files)}")
    print()
    print(header)
    print(sep)
    for rel, a, b, n, orphan in rows:
        flag = " <-- NET!=0" if isinstance(n, int) and n != 0 else ""
        flag2 = "  <-- orphan #else" if orphan else ""
        print(f"{rel.ljust(path_w)}  {str(a):>5}  {str(b):>6}  {str(n):>5}  {orphan}{flag}{flag2}")

    print()
    print("Summary")
    print(sep)
    if not flagged_net:
        print("All files balanced (NET == 0).")
    else:
        print(f"Files with NET != 0 ({len(flagged_net)}):")
        for rel, n in flagged_net:
            print(f"  {rel}  NET={n:+d}")

    if not flagged_else:
        print("No orphan #else directives detected.")
    else:
        print(f"Files with orphan #else ({len(flagged_else)}):")
        for rel, lines in flagged_else:
            print(f"  {rel}  lines: {', '.join(str(l) for l in lines)}")

    # Exit code: 0 if all clean, 1 if any issues
    if flagged_net or flagged_else:
        sys.exit(1)


if __name__ == "__main__":
    main()
