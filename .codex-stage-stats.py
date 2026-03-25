from PIL import Image
from pathlib import Path
root = Path('run/automation/captures')
series = ['stage_albedo','stage_normal','stage_mapped_normal','stage_material','stage_position','stage_lighting','stage_indirect']
for idx in [9,10,17,18,19,20]:
    row = [f'{idx:03d}']
    for s in series:
        p = root / f'{s}-{idx:03d}.png'
        im = Image.open(p).convert('RGB')
        vals = list(im.getdata())
        avg = sum((0.2126*r + 0.7152*g + 0.0722*b) for r,g,b in vals) / len(vals)
        row.append(f'{s}:avg={avg:.2f}')
    print(' | '.join(row))
