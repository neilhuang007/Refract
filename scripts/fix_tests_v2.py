filepath = r'E:\RE\photonics\src\test\java\at\redi2go\photonic\client\rendering\world\WorldUpdateLatencyTest.java'

with open(filepath, 'rb') as f:
    content = f.read()

old = b'this.chunks.isEmpty() ? Integer.MAX_VALUE : CHUNK_LOAD_BUDGET'
new = b'this.chunks.isEmpty() ? INITIAL_CHUNK_LOAD_BUDGET : CHUNK_LOAD_BUDGET'
if old in content:
    content = content.replace(old, new)
    print('Fixed WorldUpdateLatencyTest')

old2 = b'void initialChunkLoadingUsesUnlimitedBootstrapBudget()'
new2 = b'void initialChunkLoadingUsesHigherBootstrapBudget()'
if old2 in content:
    content = content.replace(old2, new2)
    print('Renamed test method')

with open(filepath, 'wb') as f:
    f.write(content)
print('Done')
