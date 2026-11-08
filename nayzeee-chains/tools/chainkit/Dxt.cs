// A small DXT5 (BC3) encoder with a full mip chain. Colour endpoints come from the block's principal
// axis (not just its bounding box), which keeps gold / silver gradients and diamond sparkle cleaner.

static class Dxt
{
    public static int WriteDds(string path, byte[] rgba, int w, int h)
    {
        var levels = new List<byte[]>();
        int lw = w, lh = h; var cur = rgba;
        while (true)
        {
            levels.Add(Encode(cur, lw, lh));
            if (lw <= 4 || lh <= 4) break;
            int nw = Math.Max(4, lw / 2), nh = Math.Max(4, lh / 2);
            cur = Half(cur, lw, lh, nw, nh); lw = nw; lh = nh;
        }
        using var fs = File.Create(path);
        using var bw = new BinaryWriter(fs);
        bw.Write(0x20534444u); bw.Write(124u); bw.Write(0x1u | 0x2 | 0x4 | 0x1000 | 0x20000 | 0x80000);
        bw.Write((uint)h); bw.Write((uint)w); bw.Write((uint)(Math.Max(1, (w + 3) / 4) * Math.Max(1, (h + 3) / 4) * 16)); bw.Write(0u); bw.Write((uint)levels.Count);
        for (int i = 0; i < 11; i++) bw.Write(0u);
        bw.Write(32u); bw.Write(0x4u); bw.Write(0x35545844u); for (int i = 0; i < 5; i++) bw.Write(0u);
        bw.Write(0x1000u | 0x8 | 0x400000); for (int i = 0; i < 4; i++) bw.Write(0u);
        foreach (var l in levels) bw.Write(l);
        return levels.Count;
    }

    static byte[] Half(byte[] s, int w, int h, int nw, int nh)
    {
        var d = new byte[nw * nh * 4];
        for (int y = 0; y < nh; y++)
            for (int x = 0; x < nw; x++)
            {
                int sx = Math.Min(w - 1, x * 2), sy = Math.Min(h - 1, y * 2), sx1 = Math.Min(w - 1, sx + 1), sy1 = Math.Min(h - 1, sy + 1);
                for (int c = 0; c < 4; c++)
                    d[(y * nw + x) * 4 + c] = (byte)((s[(sy * w + sx) * 4 + c] + s[(sy * w + sx1) * 4 + c] + s[(sy1 * w + sx) * 4 + c] + s[(sy1 * w + sx1) * 4 + c] + 2) / 4);
            }
        return d;
    }

    static byte[] Encode(byte[] px, int w, int h)
    {
        int bw = Math.Max(1, (w + 3) / 4), bh = Math.Max(1, (h + 3) / 4);
        var out_ = new byte[bw * bh * 16];
        var blk = new float[16 * 4];
        for (int by = 0; by < bh; by++)
            for (int bx = 0; bx < bw; bx++)
            {
                for (int i = 0; i < 16; i++)
                {
                    int x = Math.Min(w - 1, bx * 4 + i % 4), y = Math.Min(h - 1, by * 4 + i / 4);
                    for (int c = 0; c < 4; c++) blk[i * 4 + c] = px[(y * w + x) * 4 + c];
                }
                int o = (by * bw + bx) * 16;
                Alpha(blk, out_, o);
                Colour(blk, out_, o + 8);
            }
        return out_;
    }

    static void Alpha(float[] blk, byte[] o, int at)
    {
        int amin = 255, amax = 0;
        for (int i = 0; i < 16; i++) { int a = (int)blk[i * 4 + 3]; amin = Math.Min(amin, a); amax = Math.Max(amax, a); }
        o[at] = (byte)amax; o[at + 1] = (byte)amin;
        ulong bits = 0;
        for (int i = 0; i < 16; i++)
        {
            int a = (int)blk[i * 4 + 3], code;
            if (amax == amin) code = 0;
            else
            {
                int t = (int)Math.Round((amax - a) * 7.0 / (amax - amin)); // 0 = amax .. 7 = amin
                code = t == 0 ? 0 : t == 7 ? 1 : t + 1;
            }
            bits |= (ulong)code << (3 * i);
        }
        for (int i = 0; i < 6; i++) o[at + 2 + i] = (byte)(bits >> (8 * i));
    }

    static void Colour(float[] blk, byte[] o, int at)
    {
        // mean + principal axis (power iteration on the covariance)
        float mr = 0, mg = 0, mb = 0;
        for (int i = 0; i < 16; i++) { mr += blk[i * 4]; mg += blk[i * 4 + 1]; mb += blk[i * 4 + 2]; }
        mr /= 16; mg /= 16; mb /= 16;
        float rr = 0, rg = 0, rb = 0, gg = 0, gb = 0, bb = 0;
        for (int i = 0; i < 16; i++)
        {
            float r = blk[i * 4] - mr, g = blk[i * 4 + 1] - mg, b = blk[i * 4 + 2] - mb;
            rr += r * r; rg += r * g; rb += r * b; gg += g * g; gb += g * b; bb += b * b;
        }
        float ax = 1, ay = 1, az = 1;
        for (int k = 0; k < 8; k++)
        {
            float nx = rr * ax + rg * ay + rb * az, ny = rg * ax + gg * ay + gb * az, nz = rb * ax + gb * ay + bb * az;
            float l = MathF.Sqrt(nx * nx + ny * ny + nz * nz);
            if (l < 1e-6f) { ax = 0.577f; ay = 0.577f; az = 0.577f; break; }
            ax = nx / l; ay = ny / l; az = nz / l;
        }
        float lo = float.MaxValue, hi = float.MinValue;
        for (int i = 0; i < 16; i++)
        {
            float p = (blk[i * 4] - mr) * ax + (blk[i * 4 + 1] - mg) * ay + (blk[i * 4 + 2] - mb) * az;
            lo = Math.Min(lo, p); hi = Math.Max(hi, p);
        }
        float[] e0 = { mr + ax * hi, mg + ay * hi, mb + az * hi };
        float[] e1 = { mr + ax * lo, mg + ay * lo, mb + az * lo };

        var idx = new int[16];
        ushort c0 = To565(e0), c1 = To565(e1);
        Assign(blk, c0, c1, idx);

        // one least-squares refit of the endpoints for the chosen indices
        float[] wa = { 1f, 0f, 2f / 3f, 1f / 3f };
        float aa = 0, ab = 0, bb2 = 0; var ax_ = new float[3]; var bx_ = new float[3];
        for (int i = 0; i < 16; i++)
        {
            float a = wa[idx[i]], b = 1 - a;
            aa += a * a; ab += a * b; bb2 += b * b;
            for (int c = 0; c < 3; c++) { ax_[c] += a * blk[i * 4 + c]; bx_[c] += b * blk[i * 4 + c]; }
        }
        float det = aa * bb2 - ab * ab;
        if (Math.Abs(det) > 1e-4f)
        {
            var n0 = new float[3]; var n1 = new float[3];
            for (int c = 0; c < 3; c++)
            {
                n0[c] = Math.Clamp((ax_[c] * bb2 - bx_[c] * ab) / det, 0, 255);
                n1[c] = Math.Clamp((bx_[c] * aa - ax_[c] * ab) / det, 0, 255);
            }
            ushort d0 = To565(n0), d1 = To565(n1);
            var idx2 = new int[16];
            if (Err(blk, d0, d1, idx2) < Err(blk, c0, c1, idx)) { c0 = d0; c1 = d1; idx = idx2; }
        }

        if (c0 < c1)
        {
            (c0, c1) = (c1, c0);
            for (int i = 0; i < 16; i++) idx[i] = idx[i] switch { 0 => 1, 1 => 0, 2 => 3, _ => 2 };
        }
        uint bits = 0;
        for (int i = 0; i < 16; i++) bits |= (uint)(c0 == c1 ? 0 : idx[i]) << (2 * i);
        o[at] = (byte)c0; o[at + 1] = (byte)(c0 >> 8); o[at + 2] = (byte)c1; o[at + 3] = (byte)(c1 >> 8);
        for (int i = 0; i < 4; i++) o[at + 4 + i] = (byte)(bits >> (8 * i));
    }

    static float Err(float[] blk, ushort c0, ushort c1, int[] idx) => Assign(blk, c0, c1, idx);

    static float Assign(float[] blk, ushort c0, ushort c1, int[] idx)
    {
        var p0 = From565(c0); var p1 = From565(c1);
        var pal = new float[4][]
        {
            p0, p1,
            new[] { (2 * p0[0] + p1[0]) / 3, (2 * p0[1] + p1[1]) / 3, (2 * p0[2] + p1[2]) / 3 },
            new[] { (p0[0] + 2 * p1[0]) / 3, (p0[1] + 2 * p1[1]) / 3, (p0[2] + 2 * p1[2]) / 3 },
        };
        float total = 0;
        for (int i = 0; i < 16; i++)
        {
            int best = 0; float bd = float.MaxValue;
            for (int k = 0; k < 4; k++)
            {
                float dr = blk[i * 4] - pal[k][0], dg = blk[i * 4 + 1] - pal[k][1], db = blk[i * 4 + 2] - pal[k][2];
                float dd = dr * dr * 0.3f + dg * dg * 0.59f + db * db * 0.11f;
                if (dd < bd) { bd = dd; best = k; }
            }
            idx[i] = best; total += bd;
        }
        return total;
    }

    static ushort To565(float[] c)
    {
        int r = (int)Math.Clamp(MathF.Round(c[0] * 31 / 255f), 0, 31);
        int g = (int)Math.Clamp(MathF.Round(c[1] * 63 / 255f), 0, 63);
        int b = (int)Math.Clamp(MathF.Round(c[2] * 31 / 255f), 0, 31);
        return (ushort)(r << 11 | g << 5 | b);
    }
    static float[] From565(ushort v) => new float[] { ((v >> 11) & 31) * 255f / 31f, ((v >> 5) & 63) * 255f / 63f, (v & 31) * 255f / 31f };
}
