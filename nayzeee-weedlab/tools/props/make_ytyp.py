"""Writes nzw_weedlab.ytyp.xml (CodeWalker format) from bounds.json (build_props.py).

    python make_ytyp.py <build dir>

Every archetype uses the shared texture dictionary nzw_weedlab.ytd.
"""
import json
import math
import os
import sys

BUILD = os.path.abspath(sys.argv[1])
data = json.load(open(os.path.join(BUILD, "bounds.json")))

items = []
for name, b in sorted(data["bounds"].items()):
    lo, hi = b["min"], b["max"]
    c = [(a + z) / 2 for a, z in zip(lo, hi)]
    r = max(0.05, math.dist(lo, hi) / 2)
    items.append(f"""    <Item type="CBaseArchetypeDef">
      <lodDist value="{b['lod']:.8f}"/>
      <flags value="32"/>
      <specialAttribute value="0"/>
      <bbMin x="{lo[0]:.6f}" y="{lo[1]:.6f}" z="{lo[2]:.6f}"/>
      <bbMax x="{hi[0]:.6f}" y="{hi[1]:.6f}" z="{hi[2]:.6f}"/>
      <bsCentre x="{c[0]:.6f}" y="{c[1]:.6f}" z="{c[2]:.6f}"/>
      <bsRadius value="{r:.6f}"/>
      <hdTextureDist value="{min(60.0, b['lod']):.8f}"/>
      <name>{name}</name>
      <textureDictionary>nzw_weedlab</textureDictionary>
      <clipDictionary/>
      <drawableDictionary/>
      <physicsDictionary/>
      <assetType>ASSET_TYPE_DRAWABLE</assetType>
      <assetName>{name}</assetName>
      <extensions/>
    </Item>""")

xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<CMapTypes>
  <extensions/>
  <archetypes>
{chr(10).join(items)}
  </archetypes>
  <name>nzw_weedlab</name>
  <dependencies/>
  <compositeEntityTypes/>
</CMapTypes>
"""
out = os.path.join(BUILD, "xml", "nzw_weedlab.ytyp.xml")
open(out, "w").write(xml)
print("wrote", out, len(items), "archetypes")
