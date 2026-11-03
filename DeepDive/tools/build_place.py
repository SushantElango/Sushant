"""Builds DeepDive.rbxlx (a Roblox place file) from the scripts in src/.

Usage:  python3 tools/build_place.py
Then open DeepDive.rbxlx in Roblox Studio (File > Open from File).
"""
import os
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")

LAYOUT = [
    ("ReplicatedStorage", None, [("ModuleScript", "DeepDiveConfig", "ReplicatedStorage/DeepDiveConfig.lua")]),
    ("ServerScriptService", None, [
        ("ModuleScript", "WorldBuilder", "ServerScriptService/WorldBuilder.lua"),
        ("ModuleScript", "SubBuilder", "ServerScriptService/SubBuilder.lua"),
        ("ModuleScript", "PlayerData", "ServerScriptService/PlayerData.lua"),
        ("ModuleScript", "Monsters", "ServerScriptService/Monsters.lua"),
        ("Script", "GameServer", "ServerScriptService/GameServer.lua"),
    ]),
    ("StarterPlayer", "StarterPlayerScripts", [("LocalScript", "GameClient", "StarterPlayerScripts/GameClient.lua")]),
]

ref = 0
def nextref():
    global ref
    ref += 1
    return f"RBX{ref:08d}"

def cdata(text):
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"

def script_item(cls, name, path):
    with open(os.path.join(SRC, path), encoding="utf-8") as f:
        source = f.read()
    return (f'<Item class="{cls}" referent="{nextref()}"><Properties>'
            f'<string name="Name">{escape(name)}</string>'
            f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>'
            f'</Properties></Item>')

def service(cls, children):
    return (f'<Item class="{cls}" referent="{nextref()}"><Properties>'
            f'<string name="Name">{cls}</string></Properties>{"".join(children)}</Item>')

parts = [service("Workspace", [])]
for svc, sub, scripts in LAYOUT:
    items = [script_item(*s) for s in scripts]
    if sub:
        items = [service(sub, items)]
    parts.append(service(svc, items))

xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
       'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
       'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
       + "".join(parts) + "</roblox>")
out = os.path.join(ROOT, "DeepDive.rbxlx")
with open(out, "w", encoding="utf-8") as f:
    f.write(xml)
print("wrote", out, len(xml), "bytes")
