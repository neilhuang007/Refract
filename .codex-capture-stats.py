from PIL import Image
from pathlib import Path
import math
root = Path('run/automation/captures')
series = ['direct','direct_raw','direct_denoised','direct_soft','lighting','indirect','indirect_raw','final']
for idx in range(1,21):
    row = [f'{idx:03d}']
    for s in series:
        p = root / f'{s}-{idx:03d}.png'
        im = Image.open(p).convert('RGB')
        vals = list(im.getdata())
        mx = 0.0
        avg = 0.0
        for r,g,b in vals:
            lum = 0.2126*r + 0.7152*g + 0.0722*b
            mx = max(mx, lum)
            avg += lum
        avg /= max(1, len(vals))
        row.append(f'{s}:avg={avg:.2f},max={mx:.0f}')
    print(' | '.join(row))
