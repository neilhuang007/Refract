filepath = r'E:\RE\photonics\src\test\java\at\redi2go\photonic\client\rendering\patching\RenderDispatcherParityTest.java'

with open(filepath, 'rb') as f:
    content = f.read()

old = b'renderScale * GI_SCALE, window.getFramebufferHeight() * renderScale * GI_SCALE'
new = b'renderScale, window.getFramebufferHeight() * renderScale'
if old in content:
    content = content.replace(old, new)
    print('Fixed RenderDispatcherParityTest')

with open(filepath, 'wb') as f:
    f.write(content)
print('Done')
