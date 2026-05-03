import importlib.util, os, re, sys
root=os.getcwd()
spec=importlib.util.spec_from_file_location('preproc', os.path.join(root,'scripts/preproc.py'))
pre=importlib.util.module_from_spec(spec); old=sys.argv; sys.argv=['preproc']
try: spec.loader.exec_module(pre)
finally: sys.argv=old
for rel in [
 'lighttree/LightingPasses/DI/TemporalReprojection.fsh',
 'lighttree/LightingPasses/DI/TemporalBinningOffsets.fsh',
 'lighttree/LightingPasses/DI/TemporalBinning.fsh',
 'lighttree/LightingPasses/DI/ScatterTemporalResolve.fsh',
 'lighttree/LightingPasses/DI/ScatterBackupTemporalResampling.fsh',
 'lighttree/LightingPasses/DI/MultiTemporalReprojection.fsh',
 'lighttree/LightingPasses/DI/MultiTemporalBinningOffsets.fsh',
 'lighttree/LightingPasses/DI/MultiTemporalBinning.fsh',
 'lighttree/LightingPasses/DI/MultiScatterTemporalResampling.fsh',
 'lighttree/LightingPasses/DI/CollectTemporalSamples.fsh',
 'lighttree/LightingPasses/DI/GatherTemporalResampling.fsh',
 'lighttree/LightingPasses/DI/SpatialResampling.fsh',
 'lighttree/LightingPasses/DI/ShadeSamples.fsh']:
    text='\n'.join(pre.expand(os.path.join(pre.ROOT, rel), {}))
    blocks=re.findall(r'layout\s*\(std430[^)]*\)\s*(?:restrict\s*)?(?:readonly\s*)?(?:coherent\s*)?(?:restrict\s*)?buffer\s+(\w+)', text)
    ublocks=re.findall(r'layout\s*\(std140[^)]*\)\s*(?:restrict\s*)?(?:readonly\s*)?buffer\s+(\w+)', text)
    print(rel, 'std430', len(blocks), blocks, 'std140buf', len(ublocks), ublocks)
