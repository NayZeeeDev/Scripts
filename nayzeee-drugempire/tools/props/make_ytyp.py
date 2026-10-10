"""Writes nz_drugempire.ytyp.xml (CodeWalker format) from the bounds printed by build_props.py."""
import math
import sys

BOUNDS = {
    "nz_growtent":      ((-0.456, -0.515, 0.0), (0.456, 0.452, 1.902)),
    "nz_packbench":     ((-0.8, -0.375, 0.0), (0.8, 0.375, 1.8)),
    "nz_packbench_lid": ((-0.235, -0.765, -0.04), (0.235, 0.002, 0.0)),
    "nz_zipbag":        ((-0.05, -0.07, 0.0), (0.05, 0.07, 0.016)),
    "nz_jar":           ((-0.04, -0.04, 0.0), (0.04, 0.04, 0.093)),
    "nz_jar_lid":       ((-0.042, -0.042, 0.0), (0.042, 0.042, 0.016)),
}

items = []
for name, (lo, hi) in BOUNDS.items():
    c = [(a + b) / 2 for a, b in zip(lo, hi)]
    r = math.dist(lo, hi) / 2
    items.append(f"""    <Item type="CBaseArchetypeDef">
      <lodDist value="80.00000000"/>
      <flags value="32"/>
      <specialAttribute value="0"/>
      <bbMin x="{lo[0]:.6f}" y="{lo[1]:.6f}" z="{lo[2]:.6f}"/>
      <bbMax x="{hi[0]:.6f}" y="{hi[1]:.6f}" z="{hi[2]:.6f}"/>
      <bsCentre x="{c[0]:.6f}" y="{c[1]:.6f}" z="{c[2]:.6f}"/>
      <bsRadius value="{r:.6f}"/>
      <hdTextureDist value="40.00000000"/>
      <name>{name}</name>
      <textureDictionary>{name}</textureDictionary>
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
  <name>nz_drugempire</name>
  <dependencies/>
  <compositeEntityTypes/>
</CMapTypes>
"""
open(sys.argv[1], "w").write(xml)
print("wrote", sys.argv[1])
