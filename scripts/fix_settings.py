with open(r'E:\RE\photonics\src\at\redi2go\photonic\client\ModSettingsScreen.java', 'rb') as f:
    content = f.read()

old = (
    b'      PhotonicsStorage.Parameter<Boolean> oilifyEnabled = PhotonicsStorage.OILIFY_ENABLED;\n'
    b'      buttons.add(new ModSettingsScreen.PButton("Oilify: " + (oilifyEnabled.value ? "On" : "Off"), w -> {\n'
    b'         oilifyEnabled.value = !oilifyEnabled.value;\n'
    b'         oilifyEnabled.modified();\n'
    b'         w.setMessage(Text.of("Oilify: " + (oilifyEnabled.value ? "On" : "Off")));\n'
    b'      }, "Applies an oil painting effect to the world using\\nan anisotropic Kuwahara filter.", () -> true));\n'
)
new = (
    b'      PhotonicsStorage.Parameter<Boolean> oilify = PhotonicsStorage.OILIFY_ENABLED;\n'
    b'      buttons.add(new ModSettingsScreen.PButton("Oilify: " + (oilify.value ? "On" : "Off"), w -> {\n'
    b'         oilify.value = !oilify.value;\n'
    b'         oilify.modified();\n'
    b'         w.setMessage(Text.of("Oilify: " + (oilify.value ? "On" : "Off")));\n'
    b'      }, "Applies an oil painting effect to the world using\\nan anisotropic Kuwahara filter.", () -> true));\n'
)
if old in content:
    content2 = content.replace(old, new, 1)
    with open(r'E:\RE\photonics\src\at\redi2go\photonic\client\ModSettingsScreen.java', 'wb') as f:
        f.write(content2)
    print('Done')
else:
    print('NOT FOUND')
    # Debug: search for the partial
    idx = content.find(b'oilifyEnabled')
    print('oilifyEnabled at:', idx)
