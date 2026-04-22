#!/usr/bin/env python3
"""Replace non-ASCII characters in all shader files with ASCII equivalents."""
import os
ROOT = 'assets/photonic/shaders'
# Common replacements
REPLACEMENTS = {
    '\u2014': '--',  # em-dash
    '\u2013': '-',   # en-dash
    '\u2018': "'",   # left single quote
    '\u2019': "'",   # right single quote
    '\u201C': '"',   # left double quote
    '\u201D': '"',   # right double quote
    '\u2026': '...', # ellipsis
    '\u00B1': '+/-', # plus-minus
    '\u00B0': 'deg', # degree
    '\u00B5': 'u',   # micro
    '\u00D7': 'x',   # multiplication
    '\u2022': '*',   # bullet
    '\u00A0': ' ',   # non-breaking space
    '\u2190': '<-',
    '\u2192': '->',
    '\u2191': '^',
    '\u2193': 'v',
    '\u00BD': '1/2',
    '\u00BC': '1/4',
    '\u00BE': '3/4',
    '\u221E': 'inf',
    '\u2260': '!=',
    '\u2264': '<=',
    '\u2265': '>=',
    '\u00B2': '^2',
    '\u00B3': '^3',
    '\u03C0': 'pi',
    '\u03B1': 'alpha',
    '\u03B2': 'beta',
    '\u03B3': 'gamma',
    '\u03B4': 'delta',
    '\u03B8': 'theta',
    '\u03BB': 'lambda',
    '\u03BC': 'mu',
    '\u03C3': 'sigma',
    '\u03C9': 'omega',
    '\u2032': "'",   # prime
    '\u2033': '"',   # double prime
    '\u221A': 'sqrt',
    '\u2248': '~=',
    '\u2261': '==',
}

modified = []
for root, _, files in os.walk(ROOT):
    for f in files:
        if not f.endswith(('.glsl', '.fsh', '.vsh')):
            continue
        path = os.path.join(root, f)
        with open(path, 'rb') as fp:
            data = fp.read()
        if all(b < 128 for b in data):
            continue
        try:
            text = data.decode('utf-8')
        except UnicodeDecodeError as e:
            print(f'{path}: cannot decode as UTF-8: {e}')
            continue
        new_text = text
        for u, ascii_repl in REPLACEMENTS.items():
            new_text = new_text.replace(u, ascii_repl)
        # Any remaining non-ASCII? replace with '?'
        remaining_non_ascii = [c for c in new_text if ord(c) > 127]
        if remaining_non_ascii:
            unique = set(remaining_non_ascii)
            print(f'{path}: remaining non-ASCII chars {[hex(ord(c)) for c in unique]} - replacing with "?"')
            new_text = ''.join(c if ord(c) < 128 else '?' for c in new_text)
        new_data = new_text.encode('utf-8')
        if new_data != data:
            with open(path, 'wb') as fp:
                fp.write(new_data)
            modified.append(path)

print(f'\nModified {len(modified)} files')
for p in modified:
    print(f'  {p}')
