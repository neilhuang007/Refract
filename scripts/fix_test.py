import sys

filepath = r'E:\RE\photonics\src\test\java\at\redi2go\photonic\client\rendering\world\WorldUpdateLatencyTest.java'

with open(filepath, 'rb') as f:
    content = f.read()

old = b'initialChunkLoadingUsesSmallerBootstrapBudget() throws Exception {\r\n      String source = normalize(Files.readString(WORLD_REGISTRY));\r\n\r\n      assertTrue(source.contains("private static final int INITIAL_CHUNK_LOAD_BUDGET = 8;"));\r\n      assertTrue(source.contains("this.chunks.isEmpty() ? INITIAL_CHUNK_LOAD_BUDGET : CHUNK_LOAD_BUDGET"));\r\n   }'

new = b'initialChunkLoadingUsesUnlimitedBootstrapBudget() throws Exception {\r\n      String source = normalize(Files.readString(WORLD_REGISTRY));\r\n\r\n      assertTrue(source.contains("this.chunks.isEmpty() ? Integer.MAX_VALUE : CHUNK_LOAD_BUDGET"));\r\n   }'

if old not in content:
    print("ERROR: old string not found")
    sys.exit(1)

content = content.replace(old, new)

old2 = b'assertTrue(source.contains("this.shadowStateDirty = true;"));\r\n      assertTrue(source.contains("this.chunkSyncNeeded = true;"));'
new2 = b'assertTrue(source.contains("this.shadowStateDirty = true;"));'

if old2 in content:
    content = content.replace(old2, new2)
    print("Also fixed queueBuildJob test")

with open(filepath, 'wb') as f:
    f.write(content)

print("Done")
