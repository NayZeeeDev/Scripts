"""Regenerate data/shaders_gen9.json from CodeWalker's ShadersGen9Conversion.xml.

    python3 tools/extract_shader_names.py <path>/CodeWalker.Core/ShadersGen9Conversion.xml

The JSON lists, for every GTA V shader, its .sps file name and the legal
parameter names (legacy names = the "old" attribute, plus gen9 names).
lib/validate.py uses it to check every ShaderFX written into a .ydr.xml.
Source: CodeWalker by dexyfex (MIT licence).
"""
import json
import os
import sys
import xml.etree.ElementTree as ET


def main(src: str) -> None:
    root = ET.parse(src).getroot()
    out = {}
    for item in root.findall("Item"):
        name = item.findtext("Name")
        params = item.find("Parameters")
        textures, vectors = set(), set()
        for p in (params if params is not None else []):
            kind = p.get("type")
            if kind == "Sampler":
                continue                      # sampler states, not ShaderFX parameters
            for key in ("old", "name"):
                v = p.get(key)
                if v:
                    (textures if kind == "Texture" else vectors).add(v)
        out[name] = {"file": item.findtext("FileName"), "textures": sorted(textures, key=str.lower),
                     "params": sorted(vectors, key=str.lower)}
    dst = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "shaders_gen9.json")
    with open(dst, "w", encoding="utf-8") as f:
        f.write('{"source": "CodeWalker.Core/ShadersGen9Conversion.xml (CodeWalker by dexyfex, MIT licence)",\n')
        f.write(' "shaders": {\n')
        rows = [f"  {json.dumps(k)}: {json.dumps(v, sort_keys=True)}" for k, v in sorted(out.items())]
        f.write(",\n".join(rows))
        f.write("\n }\n}\n")
    print(f"wrote {dst} ({len(out)} shaders)")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
