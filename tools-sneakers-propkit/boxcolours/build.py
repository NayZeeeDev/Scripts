import os, re, sys
from PIL import Image
sys.path.insert(0, '/home/user/Scripts/tools-sneakers-propkit/propkit')
from propkit import dds_dxt5

SP, OUT = sys.argv[1], sys.argv[2]
SIZE = 512
arche_items = []
for n in ('nzs_box', 'nzs_box_heel', 'nzs_box_boot'):
    pkg = f'{SP}/boxes/pkg/{n}'
    base_xml = open(f'{pkg}/{n}.ydr.xml').read()
    lid_xml = open(f'{pkg}/{n}_lid.ydr.xml').read()
    ytyp = open(f'{pkg}/{n}.ytyp.xml').read()
    items = re.findall(r'<Item type="CBaseArchetypeDef">.*?</Item>', ytyp, re.S)
    for c in sorted(os.listdir(f'{SP}/boxcol/out/{n}')):
        c = c[:-4]
        img = Image.open(f'{SP}/boxcol/out/{n}/{c}.png').convert('RGBA').resize((SIZE, SIZE), Image.LANCZOS)
        dds, mips = dds_dxt5(img)
        tex = f'{n}_{c}_atlas'
        for src, model in ((base_xml, f'{n}_{c}'), (lid_xml, f'{n}_{c}_lid')):
            x = src.replace(f'{n}_atlas', tex)
            x = re.sub(r'<Name>' + re.escape(n) + r'(_lid)?</Name>', lambda m: f'<Name>{model}</Name>', x, count=1)
            x = x.replace('<Width value="1024" />', f'<Width value="{SIZE}" />').replace('<Height value="1024" />', f'<Height value="{SIZE}" />')
            x = re.sub(r'<MipLevels value="\d+" />', f'<MipLevels value="{mips}" />', x)
            os.makedirs(f'{OUT}/{model}', exist_ok=True)
            open(f'{OUT}/{model}/{tex}.dds', 'wb').write(dds)
            open(f'{OUT}/{model}.ydr.xml', 'w', newline='\n').write(x)
        for it in items:
            nm = re.search(r'<name>(.*?)</name>', it).group(1)
            new = nm.replace(n, f'{n}_{c}', 1)
            arche_items.append(it.replace(f'<name>{nm}</name>', f'<name>{new}</name>').replace(f'<assetName>{nm}</assetName>', f'<assetName>{new}</assetName>'))
ytyp_xml = ('<?xml version="1.0" encoding="UTF-8"?>\n<CMapTypes>\n  <extensions/>\n  <archetypes>\n    '
            + '\n    '.join(arche_items) + '\n  </archetypes>\n  <name>nzs_box_colours</name>\n  <dependencies/>\n  <compositeEntityTypes/>\n</CMapTypes>\n')
open(f'{OUT}/nzs_box_colours.ytyp.xml', 'w', newline='\n').write(ytyp_xml)
print(len(arche_items), 'archetypes')
