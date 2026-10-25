"""
Renames the bzzz_money duffel props and the wash-money clip so they can live
inside nayzeee-backpack-props without clashing with an installed bzzz_money resource
(bzzz: loading the same .ytyp twice breaks the props).

Every new name has the SAME length as the old one, so the resource layout of
each file is untouched: only the name hashes and name strings change, then the
data is re-deflated under the original RSC7 header.

    python3 tools/rename_bzzz.py <path to bzzz_money> <output stream dir>

Props by BzZz - https://bzzz.tebex.io - included with permission.
"""
import os, struct, sys, zlib

def joaat(s):
    h = 0
    for c in s.lower().encode():
        h = (h + c) & 0xffffffff
        h = (h + (h << 10)) & 0xffffffff
        h ^= (h >> 6)
    h = (h + (h << 3)) & 0xffffffff
    h ^= (h >> 11)
    h = (h + (h << 15)) & 0xffffffff
    return h

PREFIX_OLD, PREFIX_NEW = 'bzzz_money_', 'nzunused_x_'   # props we don't ship

NAMES = {
    'bzzz_money_bag_a':     'nayzeee_duffel_a',      # open duffel, empty
    'bzzz_money_bag_b':     'nayzeee_duffel_b',      # open duffel, stuffed with cash
    'bzzz_money_machine_a': 'nayzeee_duffel_txd_a',  # shared texture dictionary
    'bzzz_money_machine':   'nayzeee_duffel_typ',    # the ytyp itself
    'bzzz_money_washmoney': 'nayzeee_grab_cash_01',  # ped clip: grab cash from a bag on the floor
}

def other_names(root):
    out = {}
    for f in os.listdir(os.path.join(root, 'stream', 'ydr')):
        n = os.path.splitext(f)[0]
        if n not in NAMES:
            out[n] = PREFIX_NEW + n[len(PREFIX_OLD):]
    out['bzzz_money_washing'] = PREFIX_NEW + 'washing'   # clip dict referenced by the washer props
    return out

def read(path):
    d = open(path, 'rb').read()
    assert d[:4] == b'RSC7', path
    return d[:16], zlib.decompressobj(-15).decompress(d[16:])

def write(path, header, raw):
    c = zlib.compressobj(9, zlib.DEFLATED, -15)
    open(path, 'wb').write(header + c.compress(raw) + c.flush())

def rename(raw, mapping):
    for old, new in sorted(mapping.items(), key=lambda kv: -len(kv[0])):
        assert len(old) == len(new), (old, new)
        raw = raw.replace(struct.pack('<I', joaat(old)), struct.pack('<I', joaat(new)))
        # whole strings only (NUL / '.' / '/' bounded), longest first
        for end in (b'\x00', b'.'):
            raw = raw.replace(old.encode() + end, new.encode() + end)
    return raw

def main(root, out):
    mapping = dict(NAMES)
    mapping.update(other_names(root))
    os.makedirs(os.path.join(out, 'duffel'), exist_ok=True)
    os.makedirs(os.path.join(out, 'anims'), exist_ok=True)

    jobs = [
        ('stream/bzzz_money_machine.ytyp',      'duffel/nayzeee_duffel_typ.ytyp'),
        ('stream/bzzz_money_machine_a.ytd',     'duffel/nayzeee_duffel_txd_a.ytd'),
        ('stream/ydr/bzzz_money_bag_a.ydr',     'duffel/nayzeee_duffel_a.ydr'),
        ('stream/ydr/bzzz_money_bag_b.ydr',     'duffel/nayzeee_duffel_b.ydr'),
        ('stream/ycd/bzzz_money_washmoney.ycd', 'anims/nayzeee_grab_cash_01.ycd'),
    ]
    for src, dst in jobs:
        header, raw = read(os.path.join(root, src))
        new = rename(raw, mapping)
        assert len(new) == len(raw)
        target = os.path.join(out, dst)
        write(target, header, new)
        # round trip: decompresses to exactly what we meant to write
        _, check = read(target)
        assert check == new, dst
        left = [o for o in mapping if struct.pack('<I', joaat(o)) in check]
        assert not left, (dst, left)
        print(f'{dst:40s} ok ({len(raw)} bytes)')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
