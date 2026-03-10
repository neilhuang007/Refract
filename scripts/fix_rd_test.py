filepath = r'E:\RE\photonics\src\test\java\at\redi2go\photonic\client\rendering\patching\RenderDispatcherParityTest.java'

with open(filepath, 'rb') as f:
    content = f.read()

old = b'return new Vector3f(window.getFramebufferWidth() * renderScale, window.getFramebufferHeight() * renderScale, 2.0F);'
new = b'return new Vector3f(window.getFramebufferWidth() * renderScale * GI_SCALE, window.getFramebufferHeight() * renderScale * GI_SCALE, 2.0F);'

if old in content:
    content = content.replace(old, new)
    with open(filepath, 'wb') as f:
        f.write(content)
    print('Fixed')
else:
    print('Not found')
