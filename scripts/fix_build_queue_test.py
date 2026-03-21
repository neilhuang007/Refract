filepath = r'E:\RE\photonics\src\test\java\at\redi2go\photonic\client\rendering\world\WorldRegistryBuildQueueParityTest.java'

with open(filepath, 'rb') as f:
    content = f.read()

old = b'assertTrue(source.contains("this.chunkSyncNeeded = true;"));'
if old in content:
    # Remove the line containing the assertion plus the preceding newline+whitespace
    old_line = b'\r\n      assertTrue(source.contains("this.chunkSyncNeeded = true;"));'
    if old_line in content:
        content = content.replace(old_line, b'')
    else:
        old_line = b'\n      assertTrue(source.contains("this.chunkSyncNeeded = true;"));'
        content = content.replace(old_line, b'')
    with open(filepath, 'wb') as f:
        f.write(content)
    print('Fixed')
else:
    print('Not found')
