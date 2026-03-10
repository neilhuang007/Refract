filepath = r'E:\RE\photonics\src\test\java\at\redi2go\photonic\client\rendering\patching\GrazingAngleDenoiseRegressionTest.java'

with open(filepath, 'rb') as f:
    content = f.read()

# Fix: "historyDecay = 0.0f;" no longer appears in the context of light_reload; 
# it appears in a graduated blend: mix(0.5f, 0.0f, ...)
# The assertion was: historyDecay must be 0.0 on light_reload
old1 = b'assertTrue(shader.contains("historyDecay = 0.0f;"),\n         "historyDecay must be 0.0 on light_reload");'
if old1 not in content:
    old1 = b'assertTrue(shader.contains("historyDecay = 0.0f;"),\r\n         "historyDecay must be 0.0 on light_reload");'
new1 = b'assertTrue(shader.contains("historyDecay = mix(0.5f, 0.0f,"),\n         "historyDecay must blend to 0.0 during strong blend factor");'
if b'\r\n' in content:
    new1 = new1.replace(b'\n', b'\r\n')
content = content.replace(old1, new1)

# Fix: if (light_reload || frag == NULL4) changed to just if (frag == NULL4)
old2 = b'assertTrue(shader.contains("if (light_reload || frag == NULL4)"),'
new2 = b'assertTrue(shader.contains("if (frag == NULL4)"),'
content = content.replace(old2, new2)

# Fix the message too
old3 = b'"History must be fully reset on light_reload"'
new3 = b'"History must be fully reset when frag is NULL4"'
content = content.replace(old3, new3)

with open(filepath, 'wb') as f:
    f.write(content)
print('Done')
