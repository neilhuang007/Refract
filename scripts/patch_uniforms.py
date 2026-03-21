with open(r'E:\RE\photonics\src\at\redi2go\photonic\client\mixin\CommonUniformsMixin.java', 'rb') as f:
    content = f.read()

marker = b'uniforms.uniform1f(\n            UniformUpdateFrequency.PER_FRAME, "ph_mod_cast_light_pixelation_enabled", () -> PhotonicsStorage.PIXELATED_PROJECTION.value ? 1.0F : 0.0F\n         );'
idx = content.find(marker)
if idx == -1:
    print('ERROR: marker not found')
    # Try searching for partial
    partial = b'ph_mod_cast_light_pixelation_enabled'
    pidx = content.find(partial)
    print('Partial found at:', pidx)
    if pidx != -1:
        print(repr(content[pidx-30:pidx+120]))
    exit(1)

end_idx = idx + len(marker)
before = content[:end_idx]
after = content[end_idx:]

insert = (
    b'\n         uniforms.uniform1f(\n'
    b'            UniformUpdateFrequency.PER_FRAME, "ph_mod_oilify_enabled", () -> PhotonicsStorage.OILIFY_ENABLED.value ? 1.0F : 0.0F\n'
    b'         );'
)

new_content = before + insert + after
with open(r'E:\RE\photonics\src\at\redi2go\photonic\client\mixin\CommonUniformsMixin.java', 'wb') as f:
    f.write(new_content)
print('Done')
