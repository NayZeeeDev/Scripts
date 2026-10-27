"""
nzprops.budget - memory budget of a drawable WITHOUT converting it.

FiveM warns that assets above 16 MiB of virtual (system) or physical (graphics) memory "can and
WILL" fail to stream. The real numbers are only known once cwtool has written the RSC7 binary
(build.py decodes them from its page flags - rsc_pages()). Machines without .NET never get there, so
every build also estimates them from what it wrote:

    physical  = every texture's data block (all mips, exact DDS payload sizes) packed into pages
    virtual   = vertex + index buffers + the structures around them (estimated) packed into pages

Both are packed with a port of CodeWalker's ResourceBuilder.AssignPositions2 (legacy / gen8): pages
are power-of-two multiples of a base size, so the allocation is usually well above the raw sum.
"""
from __future__ import annotations

PAGE_LIMIT = 16 * 1048576
ALIGN = 16

# vertex strides of the layouts cwxml writes (Position, Normal, Colour0, TexCoord0 [, Tangent])
STRIDE = {"normal_spec": 52, "normal_spec_alpha": 52, "emissive": 36, "default": 36, "spec": 36}


def assign_pages(sizes, sys=False, max_pages=128):
    """Port of CodeWalker ResourceBuilder.AssignPositions2 (gen8). sizes: block lengths in bytes (for a
    system set the first one is the root block). Returns (allocated bytes, base shift, page counts)."""
    blocks = [int(s) for s in sizes if s > 0]
    if not blocks:
        return 0, 0, [0] * 5
    max_mult = 16
    max_block = max(blocks)
    min_block = min(blocks)
    base_shift = 0
    base = 0x2000
    while (base < min_block or base * max_mult < max_block) and base_shift < 0xF:
        base_shift += 1
        base = 0x2000 << base_shift
    root = blocks[0] if sys else None
    rest = sorted(blocks[1:] if sys else blocks, reverse=True)
    ordered = ([root] if root is not None else []) + rest
    while True:
        pages = [None] * 5
        largest_i, largest = 0, base
        while largest < max_block:
            largest_i += 1
            largest *= 2
        for i, size in enumerate(ordered):
            if i == 0:
                pages[largest_i] = [size]
                continue
            psi, psz = 0, base
            while size > psz and psi < largest_i:
                psi += 1
                psz *= 2
            found = False
            ti, tsz = psi, psz
            while not found and ti <= largest_i:
                lst = pages[ti]
                if lst is not None:
                    for p in range(len(lst)):
                        s = lst[p]
                        s += (ALIGN - (s % ALIGN)) % ALIGN
                        if s + size <= tsz:
                            lst[p] = s + size
                            found = True
                            break
                ti += 1
                tsz *= 2
            if not found:
                if pages[psi] is None:
                    pages[psi] = []
                pages[psi].append(size)
        counts = [len(p) if p else 0 for p in pages]
        ok = sum(counts) <= max_pages and counts[0] <= 0x7F and counts[1] <= 0x3F and counts[2] <= 0xF and counts[3] <= 3 \
            and counts[4] <= 1
        if ok or base_shift >= 0xF:
            break
        base_shift += 1
        base = 0x2000 << base_shift
    total = sum(counts[i] * base * (1 << i) for i in range(5))
    return total, base_shift, counts


def estimate(texture_bytes, geoms, n_shaders, n_shapes):
    """texture_bytes: list of texture data sizes (all mips). geoms: list of (shader, vertex count, index count)
    for every geometry of every LOD. Returns {"physical": bytes, "virtual": bytes} as allocated in pages."""
    phys, _, _ = assign_pages(texture_bytes, sys=False)
    sys_blocks = [0x150]                              # drawable root (placed first)
    sys_blocks += [0x2000]                            # shader group, model / geometry headers, names, misc
    sys_blocks += [0xA0 + 0x40] * len(texture_bytes)  # texture headers + names
    sys_blocks += [0x200] * n_shaders                 # shader params
    sys_blocks += [0x300] * max(1, n_shapes) + [0x400]  # bounds children + composite
    for shader, nv, ni in geoms:
        sys_blocks.append(nv * STRIDE.get(shader, 52))  # vertex data
        sys_blocks.append(ni * 2)                     # 16 bit indices
        sys_blocks += [0x98, 0x80, 0x60]              # geometry, vertex buffer, index buffer structures
    virt, _, _ = assign_pages(sys_blocks, sys=True)
    return {"physical": int(phys), "virtual": int(virt)}


def mib(n):
    return round(n / 1048576.0, 2)
