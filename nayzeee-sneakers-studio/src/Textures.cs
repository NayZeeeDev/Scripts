using System.IO.Compression;
using CodeWalker.GameFiles;
using CodeWalker.Utils;

namespace NayzeeeSneakerStudio;

/// <summary>An RGBA8 image, rows top to bottom.</summary>
sealed class Rgba
{
    public int W, H;
    public byte[] Px;
    public Rgba(int w, int h, byte[] px) { W = w; H = h; Px = px; }

    /// <summary>Bilinear sample at UV (wrapping), returns 0..1 floats.</summary>
    public void Sample(float u, float v, out float r, out float g, out float b, out float a)
    {
        u -= MathF.Floor(u); v -= MathF.Floor(v);
        float x = u * W - 0.5f, y = v * H - 0.5f;
        int x0 = (int)MathF.Floor(x), y0 = (int)MathF.Floor(y);
        float fx = x - x0, fy = y - y0;
        int X(int i) => ((i % W) + W) % W;
        int Y(int i) => ((i % H) + H) % H;
        int i00 = (Y(y0) * W + X(x0)) * 4, i10 = (Y(y0) * W + X(x0 + 1)) * 4;
        int i01 = (Y(y0 + 1) * W + X(x0)) * 4, i11 = (Y(y0 + 1) * W + X(x0 + 1)) * 4;
        float L(int o) => ((Px[i00 + o] * (1 - fx) + Px[i10 + o] * fx) * (1 - fy) + (Px[i01 + o] * (1 - fx) + Px[i11 + o] * fx) * fy) / 255f;
        r = L(0); g = L(1); b = L(2); a = L(3);
    }

    public (byte r, byte g, byte b, byte a) At(float u, float v)
    {
        u -= MathF.Floor(u); v -= MathF.Floor(v);
        int x = Math.Min(W - 1, (int)(u * W)), y = Math.Min(H - 1, (int)(v * H));
        int o = (y * W + x) * 4;
        return (Px[o], Px[o + 1], Px[o + 2], Px[o + 3]);
    }

    public Rgba Half()
    {
        int w = Math.Max(1, W / 2), h = Math.Max(1, H / 2);
        var o = new byte[w * h * 4];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                for (int c = 0; c < 4; c++)
                {
                    int s = 0, n = 0;
                    for (int dy = 0; dy < 2; dy++)
                        for (int dx = 0; dx < 2; dx++)
                        {
                            int sx = Math.Min(W - 1, x * 2 + dx), sy = Math.Min(H - 1, y * 2 + dy);
                            s += Px[(sy * W + sx) * 4 + c]; n++;
                        }
                    o[(y * w + x) * 4 + c] = (byte)((s + n / 2) / n);
                }
        return new Rgba(w, h, o);
    }
}

static class Textures
{
    static int BlockBytes(TextureFormat f) => f switch
    {
        TextureFormat.D3DFMT_DXT1 or TextureFormat.D3DFMT_ATI1 => 8,
        TextureFormat.D3DFMT_DXT3 or TextureFormat.D3DFMT_DXT5 or TextureFormat.D3DFMT_ATI2 or TextureFormat.D3DFMT_BC7 => 16,
        _ => 0,
    };

    static int LevelSize(Texture t, int level)
    {
        int w = Math.Max(1, t.Width >> level), h = Math.Max(1, t.Height >> level);
        var fmt = DDSIO.GetDXGIFormat(t.Format);
        DDSIO.DXTex.ComputePitch(fmt, w, h, out _, out int slice, 0);
        return slice;
    }

    static int LevelOffset(Texture t, int level)
    {
        int o = 0;
        for (int i = 0; i < level; i++) o += LevelSize(t, i);
        return o;
    }

    /// <summary>RGBA8 pixels of one mip level. Null if the format can't be read.</summary>
    public static Rgba? Pixels(Texture t, int level = 0)
    {
        if (t?.Data?.FullData == null) return null;
        level = Math.Clamp(level, 0, Math.Max(0, t.Levels - 1));
        int w = Math.Max(1, t.Width >> level), h = Math.Max(1, t.Height >> level);
        try
        {
            if (t.Format == TextureFormat.D3DFMT_BC7)
                return new Rgba(w, h, Bc7.Decode(t.Data.FullData, LevelOffset(t, level), w, h));
            var px = DDSIO.GetPixels(t, level);
            if (px == null || px.Length < w * h * 4) return null;
            // CodeWalker hands back BGRA
            for (int i = 0; i < w * h * 4; i += 4) (px[i], px[i + 2]) = (px[i + 2], px[i]);
            return new Rgba(w, h, px);
        }
        catch { return null; }
    }

    /// <summary>Smallest mip level whose largest side is still >= `size` (or 0).</summary>
    public static int LevelFor(Texture t, int size)
    {
        int level = 0;
        while (level + 1 < t.Levels && Math.Max(t.Width >> (level + 1), t.Height >> (level + 1)) >= size) level++;
        return level;
    }

    /// <summary>
    /// A .dds for a prop, no bigger than maxSize. Block-compressed textures keep their
    /// own encoding: the top mips are just dropped, so nothing is re-compressed.
    /// Anything else is decoded and written as A8R8G8B8 with a fresh mip chain.
    /// </summary>
    public static byte[] PropDds(Texture t, int maxSize, out TextureFormat format, out int w, out int h, out int levels)
    {
        int skip = 0;
        while (skip + 1 < t.Levels && Math.Max(t.Width >> skip, t.Height >> skip) > maxSize) skip++;
        if (BlockBytes(t.Format) > 0 && t.Data?.FullData != null)
        {
            w = Math.Max(1, t.Width >> skip); h = Math.Max(1, t.Height >> skip);
            // keep levels down to 4x4 so every level is a whole block
            int keep = 0;
            while (skip + keep < t.Levels && Math.Min(t.Width >> (skip + keep), t.Height >> (skip + keep)) >= 4) keep++;
            keep = Math.Max(1, keep);
            int start = LevelOffset(t, skip), len = 0;
            for (int i = 0; i < keep; i++) len += LevelSize(t, skip + i);
            if (start + len <= t.Data.FullData.Length)
            {
                var data = new byte[len];
                Buffer.BlockCopy(t.Data.FullData, start, data, 0, len);
                var fmt = DDSIO.GetDXGIFormat(t.Format);
                DDSIO.DXTex.ComputePitch(fmt, w, h, out _, out int slice, 0);
                var nt = new Texture
                {
                    Width = (ushort)w, Height = (ushort)h, Depth = 1, Levels = (byte)keep, Format = t.Format,
                    Stride = (ushort)(slice / h), Data = new TextureData { FullData = data },
                };
                format = t.Format; levels = keep;
                return DDSIO.GetDDSFile(nt);
            }
        }
        var img = Pixels(t, skip) ?? throw new Exception($"can't read texture {t.Name} ({t.Format})");
        while (Math.Max(img.W, img.H) > maxSize) img = img.Half();
        return Uncompressed(img, out format, out w, out h, out levels);
    }

    /// <summary>A8R8G8B8 .dds with a full mip chain.</summary>
    public static byte[] Uncompressed(Rgba img, out TextureFormat format, out int w, out int h, out int levels)
    {
        format = TextureFormat.D3DFMT_A8R8G8B8;
        w = img.W; h = img.H;
        var chain = new List<byte[]>();
        var cur = img;
        while (true)
        {
            var bgra = new byte[cur.Px.Length];
            for (int i = 0; i < bgra.Length; i += 4)
            { bgra[i] = cur.Px[i + 2]; bgra[i + 1] = cur.Px[i + 1]; bgra[i + 2] = cur.Px[i]; bgra[i + 3] = cur.Px[i + 3]; }
            chain.Add(bgra);
            if (cur.W <= 4 || cur.H <= 4) break;
            cur = cur.Half();
        }
        levels = chain.Count;
        var all = chain.SelectMany(c => c).ToArray();
        var nt = new Texture
        {
            Width = (ushort)w, Height = (ushort)h, Depth = 1, Levels = (byte)levels, Format = format,
            Stride = (ushort)(w * 4), Data = new TextureData { FullData = all },
        };
        return DDSIO.GetDDSFile(nt);
    }

    // ------------------------------------------------------------------ PNG

    static readonly uint[] CrcTable = Enumerable.Range(0, 256).Select(n =>
    {
        uint c = (uint)n;
        for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
        return c;
    }).ToArray();

    static uint Crc(byte[] data, int start, int len)
    {
        uint c = 0xFFFFFFFFu;
        for (int i = start; i < start + len; i++) c = CrcTable[(c ^ data[i]) & 0xFF] ^ (c >> 8);
        return c ^ 0xFFFFFFFFu;
    }

    public static byte[] Png(Rgba img)
    {
        using var ms = new MemoryStream();
        ms.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 });
        void Chunk(string type, byte[] data)
        {
            var buf = new byte[4 + data.Length];
            System.Text.Encoding.ASCII.GetBytes(type).CopyTo(buf, 0);
            data.CopyTo(buf, 4);
            var len = BitConverter.GetBytes(data.Length); Array.Reverse(len);
            ms.Write(len);
            ms.Write(buf);
            var crc = BitConverter.GetBytes(Crc(buf, 0, buf.Length)); Array.Reverse(crc);
            ms.Write(crc);
        }
        var ihdr = new byte[13];
        var wb = BitConverter.GetBytes(img.W); Array.Reverse(wb); wb.CopyTo(ihdr, 0);
        var hb = BitConverter.GetBytes(img.H); Array.Reverse(hb); hb.CopyTo(ihdr, 4);
        ihdr[8] = 8; ihdr[9] = 6;   // 8-bit RGBA
        Chunk("IHDR", ihdr);
        var raw = new byte[img.H * (img.W * 4 + 1)];
        for (int y = 0; y < img.H; y++)
        {
            raw[y * (img.W * 4 + 1)] = 0;
            Buffer.BlockCopy(img.Px, y * img.W * 4, raw, y * (img.W * 4 + 1) + 1, img.W * 4);
        }
        using (var z = new MemoryStream())
        {
            using (var zs = new ZLibStream(z, CompressionLevel.Optimal, true)) zs.Write(raw);
            Chunk("IDAT", z.ToArray());
        }
        Chunk("IEND", Array.Empty<byte>());
        return ms.ToArray();
    }
}
