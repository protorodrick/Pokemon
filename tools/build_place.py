#!/usr/bin/env python3
"""Builds the Tidewild project into ready-to-open Roblox files, with no Rojo or plugins needed.

    python3 tools/build_place.py

Outputs (in ./build):
  Tidewild.rbxlx            - double-click to open in Roblox Studio, then press Play.
  Tidewild_Installer.luau   - alternative: paste into Studio's Command Bar to install into any open place.

The tree mirrors default.project.json:
  src/shared  -> ReplicatedStorage.Shared              (ModuleScripts)
  src/server  -> ServerScriptService.Server            (Script; children from folder)
  src/client  -> StarterPlayer.StarterPlayerScripts.Client (LocalScript; children from folder)
"""
import os
import sys
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
OUT = os.path.join(ROOT, "build")


class Node:
    def __init__(self, cls, name, source=None, props=None):
        self.cls, self.name, self.source = cls, name, source
        self.props = props or []  # list of (xmlType, name, value)
        self.children = []


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def strip_ext(fname):
    for ext in (".server.luau", ".client.luau", ".luau", ".lua"):
        if fname.endswith(ext):
            return fname[: -len(ext)], ext
    return None, None


def script_class(ext):
    return {".server.luau": "Script", ".client.luau": "LocalScript"}.get(ext, "ModuleScript")


def load_dir(path, name):
    """Rojo semantics: a folder with init.* becomes that script; otherwise a Folder."""
    entries = sorted(os.listdir(path))
    init = next((e for e in entries if strip_ext(e)[0] == "init"), None)
    if init:
        node = Node(script_class(strip_ext(init)[1]), name, read(os.path.join(path, init)))
    else:
        node = Node("Folder", name)
    for e in entries:
        full = os.path.join(path, e)
        if e == init:
            continue
        if os.path.isdir(full):
            node.children.append(load_dir(full, e))
        else:
            base, ext = strip_ext(e)
            if base:
                node.children.append(Node(script_class(ext), base, read(full)))
    return node


def build_tree():
    rs = Node("ReplicatedStorage", "ReplicatedStorage")
    rs.children.append(load_dir(os.path.join(SRC, "shared"), "Shared"))
    sss = Node("ServerScriptService", "ServerScriptService")
    sss.children.append(load_dir(os.path.join(SRC, "server"), "Server"))
    sp = Node("StarterPlayer", "StarterPlayer")
    sps = Node("StarterPlayerScripts", "StarterPlayerScripts")
    sps.children.append(load_dir(os.path.join(SRC, "client"), "Client"))
    sp.children.append(sps)
    ws = Node("Workspace", "Workspace", props=[("bool", "StreamingEnabled", "true")])
    lighting = Node(
        "Lighting",
        "Lighting",
        props=[
            ("float", "ClockTime", "14"),
            ("float", "Brightness", "2.5"),
            ("bool", "GlobalShadows", "true"),
            ("token", "Technology", "4"),  # Enum.Technology.Future
        ],
    )
    return [ws, lighting, rs, sss, sp]


# ---------------------------------------------------------------- .rbxlx
def cdata(text):
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def emit_xml(node, out, counter, depth):
    counter[0] += 1
    pad = "  " * depth
    out.append(f'{pad}<Item class="{node.cls}" referent="RBX{counter[0]:08X}">')
    out.append(f"{pad}  <Properties>")
    out.append(f'{pad}    <string name="Name">{escape(node.name)}</string>')
    for typ, pname, val in node.props:
        out.append(f'{pad}    <{typ} name="{pname}">{escape(val)}</{typ}>')
    if node.source is not None:
        out.append(f'{pad}    <ProtectedString name="Source">{cdata(node.source)}</ProtectedString>')
    out.append(f"{pad}  </Properties>")
    for c in node.children:
        emit_xml(c, out, counter, depth + 1)
    out.append(f"{pad}</Item>")


def write_rbxlx(tree, path):
    out = ['<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" version="4">']
    counter = [0]
    for n in tree:
        emit_xml(n, out, counter, 1)
    out.append("</roblox>")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")


# ---------------------------------------------------------------- Command Bar installer
def long_string(text):
    level = 0
    while ("]" + "=" * level + "]") in text:
        level += 1
    eq = "=" * level
    # A leading newline after [==[ is dropped by Lua, so add one to preserve content exactly.
    return f"[{eq}[\n{text}]{eq}]"


def emit_lua(node, parent_expr, out, counter):
    counter[0] += 1
    var = f"n{counter[0]}"
    out.append(f'local {var} = make("{node.cls}", "{node.name}", {parent_expr})')
    if node.source is not None:
        out.append(f"{var}.Source = {long_string(node.source)}")
    for c in node.children:
        emit_lua(c, var, out, counter)


def write_installer(tree, path):
    out = [
        "-- Tidewild one-paste installer. Paste ALL of this into Roblox Studio's Command Bar",
        "-- (View > Command Bar) and press Enter. Re-running replaces the previous install.",
        "local function make(cls, name, parent)",
        "\tlocal existing = parent:FindFirstChild(name)",
        "\tif existing and existing.ClassName == cls and (cls == 'Folder' or cls == 'StarterPlayerScripts') then return existing end",
        "\tif existing then existing:Destroy() end",
        "\tlocal i = Instance.new(cls)",
        "\ti.Name = name",
        "\ti.Parent = parent",
        "\treturn i",
        "end",
        "pcall(function() workspace.StreamingEnabled = true end)",
        "local L = game:GetService('Lighting')",
        "L.ClockTime = 14; L.Brightness = 2.5; L.GlobalShadows = true",
        "pcall(function() L.Technology = Enum.Technology.Future end)",
        "local base = workspace:FindFirstChild('Baseplate'); if base then base:Destroy() end",
    ]
    counter = [0]
    services = {"ReplicatedStorage", "ServerScriptService", "StarterPlayer"}
    for n in tree:
        if n.cls not in services:
            continue
        for c in n.children:
            if c.cls == "StarterPlayerScripts":
                for cc in c.children:
                    emit_lua(cc, "game:GetService('StarterPlayer'):WaitForChild('StarterPlayerScripts')", out, counter)
            else:
                emit_lua(c, f"game:GetService('{n.cls}')", out, counter)
    out.append("print('[Tidewild] Installed! Press Play (F5) to start.')")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")


def main():
    os.makedirs(OUT, exist_ok=True)
    tree = build_tree()
    write_rbxlx(tree, os.path.join(OUT, "Tidewild.rbxlx"))
    write_installer(tree, os.path.join(OUT, "Tidewild_Installer.luau"))
    count = [0]

    def walk(n):
        if n.source is not None:
            count[0] += 1
        for c in n.children:
            walk(c)

    for n in tree:
        walk(n)
    print(f"Built {count[0]} scripts -> build/Tidewild.rbxlx and build/Tidewild_Installer.luau")


if __name__ == "__main__":
    sys.exit(main())
