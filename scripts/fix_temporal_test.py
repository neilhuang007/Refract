filepath = r'E:\RE\photonics\src\test\java\at\redi2go\photonic\client\rendering\patching\PhotonicsLightingShaderTemporalTest.java'

with open(filepath, 'rb') as f:
    content = f.read()

# Fix the test that checks for old reset path - now we use blend factor
old = b'assertTrue(shader.contains("if (light_reload || frag == NULL4)"));'
new = b'assertTrue(shader.contains("if (frag == NULL4)"));'
if old in content:
    content = content.replace(old, new)
    print('Fixed reset path assertion')

# Fix the assertion about historyDecay 
old2 = b'assertFalse(shader.contains("} else if (light_reload) {"));'
new2 = b'assertFalse(shader.contains("if (light_reload)\\n"));'
if old2 in content:
    content = content.replace(old2, new2)
    print('Fixed else if light_reload assertion')

with open(filepath, 'wb') as f:
    f.write(content)
print('Done')
