#!/usr/bin/env python3
"""Builds a Rojo-style project into ready-to-open Roblox files, with no Rojo or plugins needed.

    python3 tools/build_place.py                 # builds the project at the repo root (Tidewild)
    python3 tools/build_place.py particle-orb    # builds another project folder

Reads <project>/default.project.json (the subset of the Rojo format used here: $className, $path,
$properties, nested children) and writes to <project>/build:
  <Name>.rbxlx             - double-click to open in Roblox Studio, then press Play.
  <Name>_Installer.luau    - alternative: paste into Studio's Command Bar to install into any open place.

$path rules match Rojo: a folder with init.server.luau / init.client.luau / init.luau becomes that
script with the rest of the folder as children; *.server.luau -> Script, *.client.luau -> LocalScript,
other *.luau -> ModuleScript; folders without an init -> Folder.
"""
import json
import os
import sys
from xml.sax.saxutils import escape

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Enum properties that may appear in $properties as plain strings.
ENUMS = {
    "Technology": ("Technology", {"Legacy": 0, "Voxel": 1, "Compatibility": 2, "ShadowMap": 3, "Future": 4}),
}
# Services nested inside other services (installer must reach them with WaitForChild).
NESTED_SERVICES = {"StarterPlayerScripts", "StarterCharacterScripts"}


class Node:
    def __init__(self, cls, name, source=None, props=None):
        self.cls, self.name, self.source = cls, name, source
        self.props = props or {}
        self.children = []


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def strip_ext(fname):
    for ext in (".server.luau", ".client.luau", ".luau", ".server.lua", ".client.lua", ".lua"):
        if fname.endswith(ext):
            return fname[: -len(ext)], ext
    return None, None


def script_class(ext):
    if ext.startswith(".server"):
        return "Script"
    if ext.startswith(".client"):
        return "LocalScript"
    return "ModuleScript"


def load_path(path, name):
    if os.path.isfile(path):
        _, ext = strip_ext(os.path.basename(path))
        return Node(script_class(ext), name, read(path))
    entries = sorted(os.listdir(path))
    init = next((e for e in entries if strip_ext(e)[0] == "init"), None)
    node = Node(script_class(strip_ext(init)[1]), name, read(os.path.join(path, init))) if init else Node("Folder", name)
    for e in entries:
        full = os.path.join(path, e)
        if e == init:
            continue
        if os.path.isdir(full):
            node.children.append(load_path(full, e))
        else:
            base, _ = strip_ext(e)
            if base:
                node.children.append(load_path(full, base))
    return node


def load_spec(name, spec, base):
    if "$path" in spec:
        node = load_path(os.path.join(base, spec["$path"]), name)
        if "$className" in spec and node.cls == "Folder":
            node.cls = spec["$className"]
    else:
        node = Node(spec.get("$className", name), name)  # services infer class from name, like Rojo
    node.props.update(spec.get("$properties", {}))
    for key, child in spec.items():
        if not key.startswith("$"):
            node.children.append(load_spec(key, child, base))
    return node


# ---------------------------------------------------------------- .rbxlx
def cdata(text):
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def xml_prop(name, value):
    if isinstance(value, bool):
        return f'<bool name="{name}">{"true" if value else "false"}</bool>'
    if isinstance(value, (int, float)):
        return f'<float name="{name}">{value}</float>'
    if isinstance(value, str) and name in ENUMS:
        return f'<token name="{name}">{ENUMS[name][1][value]}</token>'
    if isinstance(value, dict) and "Color3" in value:
        r, g, b = value["Color3"]
        return f'<Color3 name="{name}"><R>{r}</R><G>{g}</G><B>{b}</B></Color3>'
    if isinstance(value, str):
        return f'<string name="{name}">{escape(value)}</string>'
    raise ValueError(f"Unsupported property {name}={value!r}")


def emit_xml(node, out, counter, depth):
    counter[0] += 1
    pad = "  " * depth
    out.append(f'{pad}<Item class="{node.cls}" referent="RBX{counter[0]:08X}">')
    out.append(f"{pad}  <Properties>")
    out.append(f'{pad}    <string name="Name">{escape(node.name)}</string>')
    for pname, val in node.props.items():
        out.append(f"{pad}    {xml_prop(pname, val)}")
    if node.source is not None:
        out.append(f'{pad}    <ProtectedString name="Source">{cdata(node.source)}</ProtectedString>')
    out.append(f"{pad}  </Properties>")
    for c in node.children:
        emit_xml(c, out, counter, depth + 1)
    out.append(f"{pad}</Item>")


def write_rbxlx(services, path):
    out = ['<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" version="4">']
    counter = [0]
    for n in services:
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
    return f"[{eq}[\n{text}]{eq}]"  # Lua drops the first newline, so content is preserved exactly


def lua_value(name, value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str) and name in ENUMS:
        return f"Enum.{ENUMS[name][0]}.{value}"
    if isinstance(value, dict) and "Color3" in value:
        return "Color3.new({}, {}, {})".format(*value["Color3"])
    return json.dumps(value)


def emit_lua(node, parent_expr, out, counter):
    counter[0] += 1
    var = f"n{counter[0]}"
    out.append(f'local {var} = make("{node.cls}", "{node.name}", {parent_expr})')
    for pname, val in node.props.items():
        out.append(f"pcall(function() {var}.{pname} = {lua_value(pname, val)} end)")
    if node.source is not None:
        out.append(f"{var}.Source = {long_string(node.source)}")
    for c in node.children:
        emit_lua(c, var, out, counter)


def emit_service(node, expr, out, counter):
    for pname, val in node.props.items():
        out.append(f"pcall(function() {expr}.{pname} = {lua_value(pname, val)} end)")
    for c in node.children:
        if c.cls in NESTED_SERVICES:
            emit_service(c, f"{expr}:WaitForChild('{c.cls}')", out, counter)
        else:
            emit_lua(c, expr, out, counter)


def write_installer(name, services, path):
    out = [
        f"-- {name} one-paste installer. Paste ALL of this into Roblox Studio's Command Bar",
        "-- (View > Command Bar) and press Enter. Re-running replaces the previous install.",
        "local function make(cls, name, parent)",
        "\tlocal existing = parent:FindFirstChild(name)",
        "\tif existing and existing.ClassName == cls and cls == 'Folder' then return existing end",
        "\tif existing then existing:Destroy() end",
        "\tlocal i = Instance.new(cls)",
        "\ti.Name = name",
        "\ti.Parent = parent",
        "\treturn i",
        "end",
        "local base = workspace:FindFirstChild('Baseplate'); if base then base:Destroy() end",
    ]
    counter = [0]
    for n in services:
        emit_service(n, f"game:GetService('{n.cls}')", out, counter)
    out.append(f"print('[{name}] Installed! Press Play (F5) to start.')")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")


def count_scripts(nodes):
    return sum((1 if n.source is not None else 0) + count_scripts(n.children) for n in nodes)


def main():
    project_dir = os.path.abspath(os.path.join(REPO, sys.argv[1])) if len(sys.argv) > 1 else REPO
    project = json.loads(read(os.path.join(project_dir, "default.project.json")))
    name = project["name"]
    tree = project["tree"]
    services = [load_spec(k, v, project_dir) for k, v in tree.items() if not k.startswith("$")]
    out_dir = os.path.join(project_dir, "build")
    os.makedirs(out_dir, exist_ok=True)
    write_rbxlx(services, os.path.join(out_dir, f"{name}.rbxlx"))
    write_installer(name, services, os.path.join(out_dir, f"{name}_Installer.luau"))
    rel = os.path.relpath(out_dir, REPO)
    print(f"Built {count_scripts(services)} scripts -> {rel}/{name}.rbxlx and {rel}/{name}_Installer.luau")


if __name__ == "__main__":
    sys.exit(main())
