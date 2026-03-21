with open(r'E:\RE\photonics\src\at\redi2go\photonic\client\ModSettingsScreen.java', 'rb') as f:
    content = f.read()

marker = b'}, "Turns pixelated projected RT cast light on or off.", () -> true));'
idx = content.find(marker)
if idx == -1:
    print('ERROR: marker not found')
    exit(1)

# Find the end of the marker line
end_of_line = content.find(b'\n', idx + len(marker))
before = content[:end_of_line + 1]
after = content[end_of_line + 1:]

insert = (
    b'      PhotonicsStorage.Parameter<Boolean> oilifyEnabled = PhotonicsStorage.OILIFY_ENABLED;\n'
    b'      buttons.add(new ModSettingsScreen.PButton("Oilify: " + (oilifyEnabled.value ? "On" : "Off"), w -> {\n'
    b'         oilifyEnabled.value = !oilifyEnabled.value;\n'
    b'         oilifyEnabled.modified();\n'
    b'         w.setMessage(Text.of("Oilify: " + (oilifyEnabled.value ? "On" : "Off")));\n'
    b'      }, "Applies an oil painting effect to the world using\\nan anisotropic Kuwahara filter.", () -> true));\n'
)

new_content = before + insert + after
with open(r'E:\RE\photonics\src\at\redi2go\photonic\client\ModSettingsScreen.java', 'wb') as f:
    f.write(new_content)
print('Done')
