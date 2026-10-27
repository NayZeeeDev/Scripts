"""
Prop definitions. tools/props/build.py imports every module in this package; each registers its props
with @prop(...) / register(...) (plain props) or @radio(...) (radio_kit: complete radio + body + parts).
Modules whose name starts with '_' (examples) load only with build.py --examples. Shared code:
common.py, parts.py, screens.py (generic), radio_common.py, radio_screens.py, radio_kit.py (radios).
"""
