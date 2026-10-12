# Builds NAYZEEE_PASTE_PACK: the 12 files the Tebex editor lists, with every module.*.twig include inlined,
# plus the schema. Nothing has to be added as a new file in the editor.
import re, os, shutil
SRC='/home/user/Scripts/nayzeee-tebex-template/'
OUT='/tmp/claude-0/-home-user-Scripts/6339b1b5-b4b9-5ef5-bf6c-cc14b3507ccf/scratchpad/NAYZEEE_PASTE_PACK/'
shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT+'category'); os.makedirs(OUT+'cms'); os.makedirs(OUT+'scheme')
mods={f: open(SRC+f).read() for f in os.listdir(SRC) if f.startswith('module.') and f.endswith('.twig')}
def inline(text, depth=0):
    def rep(m):
        name=m.group(1)
        if name in mods:
            body=mods[name]
            body=re.sub(r'\{#.*?#\}', '', body, count=1, flags=re.S).strip('\n')  # drop the file header comment
            return '\n{# ── inlined from ' + name + ' ── #}\n' + inline(body, depth+1) + '\n{# ── end ' + name + ' ── #}\n'
        return m.group(0)
    return re.sub(r"\{%\s*include\s+'(module\.[a-z0-9-]+\.twig)'\s*(?:ignore missing)?\s*%\}", rep, text)
files={'layout.html':'layout.html','index.html':'index.html','category.html':'category.html','package.html':'package.html','checkout.html':'checkout.html',
       'cms-page.html':'cms/page.html','username.html':'username.html','options.html':'options.html','category/tiered.html':'category/tiered.html',
       'module.featuredpackage.html':'module.featuredpackage.html','module.payments.html':'module.payments.html','module.giftcardbalance.html':'module.giftcardbalance.html'}
for src,dst in files.items():
    t=inline(open(SRC+src).read())
    left=re.findall(r"include\s+'(module\.[a-z0-9-]+\.twig)'", t)
    assert not left, (src,left)
    open(OUT+dst,'w').write(t)
    print(f'{dst:32s} {len(t)//1024:4d} KB')
shutil.copy(SRC+'scheme/EN.json', OUT+'scheme/EN.json')
for l in ['DE','FR','NL']: shutil.copy(SRC+f'scheme/{l}.json', OUT+f'scheme/{l}.json')
open(OUT+'INSTALL.txt','w').write("""NAYZEEE TEMPLATE - PASTE INSTALL (Tebex classic Webstore editor)

The Tebex editor has no zip upload. You paste files. Every extra module is already folded into these files,
so you only touch the files the editor already lists. Nothing needs to be created.

1. In the editor click "Change Schema". Select all (Ctrl+A), delete, paste the whole of scheme/EN.json. Save.
   (DE.json / FR.json / NL.json are the same settings with translated labels - pick one language.)
2. For each file below: click it in the editor's file list, Ctrl+A, delete, paste the file from this pack, then
   use "Save As Draft".

   CLICK IN EDITOR                  PASTE FROM THIS PACK
   layout.html                      layout.html
   index.html                       index.html
   category.html                    category.html
   package.html                     package.html
   checkout.html                    checkout.html
   cms/page.html                    cms/page.html
   username.html                    username.html
   options.html                     options.html
   category/tiered.html             category/tiered.html
   module.featuredpackage.html      module.featuredpackage.html
   module.payments.html             module.payments.html
   module.giftcardbalance.html      module.giftcardbalance.html

   Files the editor lists that are NOT in this pack (module.communitygoal.html, module.goal.html,
   module.serverstatus.html, sidebar.twig, package-entry.twig ...) can stay as they are. The template never uses them.

3. Open the Save As Draft dropdown and Publish. Then back in Appearance > Change Template, Activate NAYZEEE.
4. Template settings: the tabs 01-06 come from the schema. Fill accent colours, Discord/docs links, the release
   package ID, bestseller/new IDs, the Heartbeat key and the subscription package IDs. Publish again.

Tip from Tebex: an emptied field keeps its old value. To clear one, type a single space.
""")
print('ok')
