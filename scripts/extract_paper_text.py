import sys
import zipfile
from xml.etree import ElementTree as ET

sys.stdout.reconfigure(encoding="utf-8")

path = r"E:\RE\photonics\reference\repos\liu2025splatting_paper.docx"
with zipfile.ZipFile(path) as z:
    xml = z.read("word/document.xml")
root = ET.fromstring(xml)
ns = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
texts = []
for p in root.findall('.//w:p', ns):
    t = ''.join(node.text or '' for node in p.findall('.//w:t', ns)).strip()
    if t:
        texts.append(t)
for i, t in enumerate(texts[:260], 1):
    print(f"{i}: {t}")
