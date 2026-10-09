import struct, numpy as np
def read_dxt5(path):
    b = open(path, 'rb').read()
    h = struct.unpack_from('<I', b, 12)[0]; w = struct.unpack_from('<I', b, 16)[0]
    n = (h // 4) * (w // 4)
    blk = np.frombuffer(b, np.uint8, n * 16, 128).reshape(n, 16)
    c0 = blk[:, 8].astype(np.uint32) | (blk[:, 9].astype(np.uint32) << 8)
    c1 = blk[:, 10].astype(np.uint32) | (blk[:, 11].astype(np.uint32) << 8)
    bits = blk[:, 12].astype(np.uint32) | (blk[:, 13].astype(np.uint32) << 8) | (blk[:, 14].astype(np.uint32) << 16) | (blk[:, 15].astype(np.uint32) << 24)
    def rgb(c): return np.stack([((c >> 11) & 31) * 255 // 31, ((c >> 5) & 63) * 255 // 63, (c & 31) * 255 // 31], 1).astype(np.int32)
    p0, p1 = rgb(c0), rgb(c1)
    pal = np.stack([p0, p1, (2 * p0 + p1) // 3, (p0 + 2 * p1) // 3], 1)  # n,4,3
    idx = np.stack([(bits >> (2 * i)) & 3 for i in range(16)], 1)  # n,16
    px = pal[np.arange(n)[:, None], idx]  # n,16,3
    img = px.reshape(h // 4, w // 4, 4, 4, 3).transpose(0, 2, 1, 3, 4).reshape(h, w, 3)
    return img.astype(np.uint8)
