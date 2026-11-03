"""Builds the two copy-paste scripts and the Roblox place file from src/.

  dist/DeepDive_Server.lua  -> paste into a Script in ServerScriptService
  dist/DeepDive_Client.lua  -> paste into a LocalScript in StarterPlayer > StarterPlayerScripts
  DeepDive.rbxlx            -> or just open this place in Roblox Studio

Usage:  python3 tools/build_place.py
"""
import os
import re
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
DIST = os.path.join(ROOT, "dist")

def read(rel):
    with open(os.path.join(SRC, rel), encoding="utf-8") as f:
        return f.read()

CONFIG_REQUIRE = 'local Config = require(ReplicatedStorage:WaitForChild("DeepDiveConfig"))'

def module_block(var, rel):
    src = read(rel).replace(CONFIG_REQUIRE, "local Config = DeepDiveConfig")
    return f"local {var} = (function()\n{src.rstrip()}\nend)()\n"

SERVER_HEADER = """--[[
	DEEP DIVE - SERVER SCRIPT
	=========================
	WHERE: Explorer > ServerScriptService > (+) Script   (a normal Script)
	Paste this WHOLE file into it. Also make the LocalScript from
	DeepDive_Client.lua (StarterPlayer > StarterPlayerScripts).

	All game settings (prices, health, speeds, loot...) are in the
	"CONFIG" section right below. Search for "Config." to find a setting.
]]

"""

def build_server():
    out = [SERVER_HEADER]
    out.append("------------------------------------------------------------------------\n-- CONFIG\n------------------------------------------------------------------------\n")
    out.append("local DeepDiveConfig = (function()\n" + read("ReplicatedStorage/DeepDiveConfig.lua").rstrip() + "\nend)()\n\n")
    for var, rel in [("WorldBuilderModule", "ServerScriptService/WorldBuilder.lua"),
                     ("SubBuilderModule", "ServerScriptService/SubBuilder.lua"),
                     ("PlayerDataModule", "ServerScriptService/PlayerData.lua"),
                     ("MonstersModule", "ServerScriptService/Monsters.lua")]:
        out.append(module_block(var, rel) + "\n")
    game = read("ServerScriptService/GameServer.lua")
    repl = {
        CONFIG_REQUIRE: "local Config = DeepDiveConfig",
        'local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))': "local WorldBuilder = WorldBuilderModule",
        'local SubBuilder = require(script.Parent:WaitForChild("SubBuilder"))': "local SubBuilder = SubBuilderModule",
        'local PlayerData = require(script.Parent:WaitForChild("PlayerData"))': "local PlayerData = PlayerDataModule",
        'local Monsters = require(script.Parent:WaitForChild("Monsters"))': "local Monsters = MonstersModule",
    }
    for a, b in repl.items():
        assert game.count(a) == 1, a
        game = game.replace(a, b)
    out.append(game)
    return "".join(out)

CLIENT_HEADER = """--[[
	DEEP DIVE - CLIENT SCRIPT
	=========================
	WHERE: Explorer > StarterPlayer > StarterPlayerScripts > (+) LocalScript
	Paste this WHOLE file into it. (The server Script from
	DeepDive_Server.lua must be in ServerScriptService.)
]]

"""

def build_client():
    config_src = read("ReplicatedStorage/DeepDiveConfig.lua")
    helpers = []
    for name in ["GetZone", "FormatNumber", "FindPaint", "FindLightColor"]:
        m = re.search(r"function Config\." + name + r"\(.*?\n\s*end\n", config_src, re.S)
        # grab up to the function's closing 'end' at column 0
        start = config_src.index("function Config." + name + "(")
        end = config_src.index("\nend\n", start) + len("\nend\n")
        helpers.append(config_src[start:end])
    fetch = ('-- Settings come from the server script (one place to change them)\n'
             'local Config = ReplicatedStorage:WaitForChild("DeepDiveRemotes"):WaitForChild("GetConfig"):InvokeServer()\n'
             + "\n".join(helpers))
    client = read("StarterPlayerScripts/GameClient.lua")
    assert client.count(CONFIG_REQUIRE) == 1
    client = client.replace(CONFIG_REQUIRE, fetch)
    return CLIENT_HEADER + client

ref = 0
def nextref():
    global ref
    ref += 1
    return f"RBX{ref:08d}"

def cdata(text):
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"

def script_item(cls, name, source):
    return (f'<Item class="{cls}" referent="{nextref()}"><Properties>'
            f'<string name="Name">{escape(name)}</string>'
            f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>'
            f'</Properties></Item>')

def service(cls, children):
    return (f'<Item class="{cls}" referent="{nextref()}"><Properties>'
            f'<string name="Name">{cls}</string></Properties>{"".join(children)}</Item>')

server = build_server()
client = build_client()
os.makedirs(DIST, exist_ok=True)
for name, text in [("DeepDive_Server.lua", server), ("DeepDive_Client.lua", client)]:
    with open(os.path.join(DIST, name), "w", encoding="utf-8") as f:
        f.write(text)
    print("wrote dist/" + name, text.count("\n"), "lines")

xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
       'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
       'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
       + service("Workspace", [])
       # Future lighting = realistic shadows and glowing lights (scripts can't set this)
       + ('<Item class="Lighting" referent="RBXLIGHT"><Properties>'
          '<string name="Name">Lighting</string>'
          '<token name="Technology">4</token>'
          '<bool name="GlobalShadows">true</bool>'
          '<float name="EnvironmentDiffuseScale">1</float>'
          '<float name="EnvironmentSpecularScale">1</float>'
          '</Properties></Item>')
       + ('<Item class="ReplicatedStorage" referent="RBXRS"><Properties><string name="Name">ReplicatedStorage</string></Properties>'
          '<Item class="Folder" referent="RBXMODELS"><Properties><string name="Name">DeepDiveModels</string></Properties>'
          '<Item class="StringValue" referent="RBXREADME"><Properties><string name="Name">READ_ME</string>'
          '<string name="Value">' + escape(
              "Drag free models from the Toolbox into this folder and rename them: "
              "Submarine, BiterFish, Jellyfish, Eel, Shop, Warehouse, House, Lighthouse, PalmTree, Crane, Boat. "
              "For music, drag Sound objects here named SurfaceMusic and DeepMusic. "
              "The game uses whatever it finds here instead of the built-in shapes.") + '</string>'
          '</Properties></Item></Item></Item>')
       + service("ServerScriptService", [script_item("Script", "DeepDiveServer", server)])
       + service("StarterPlayer", [service("StarterPlayerScripts", [script_item("LocalScript", "DeepDiveClient", client)])])
       + "</roblox>")
with open(os.path.join(ROOT, "DeepDive.rbxlx"), "w", encoding="utf-8") as f:
    f.write(xml)
print("wrote DeepDive.rbxlx")
