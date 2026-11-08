// Draws a chain prop to a transparent PNG, so every chain has an inventory picture the moment it's
// converted. Three-quarter front view, key + fill light, specular from the chain's own spec map,
// 3x3 supersampling. The in-game icon studio makes nicer ones; these are the fallback.

using System.IO.Compression;
using System.Numerics;

static class Raster
{
    public static void Icon(string path, List<P.Geo> geos, P.Img diff, P.Img spec, P.SrcShader sh, int size, float yaw = -14f, float pitch = -58f)
    {
        const int SS = 3;
        int W = size * SS;
        float cy = MathF.Cos(yaw * MathF.PI / 180), sy = MathF.Sin(yaw * MathF.PI / 180);
        float cp = MathF.Cos(pitch * MathF.PI / 180), sp = MathF.Sin(pitch * MathF.PI / 180);
        Vector3 View(Vector3 v)
        {
            var a = new Vector3(v.X * cy - v.Y * sy, v.X * sy + v.Y * cy, v.Z);       // yaw about up
            return new Vector3(a.X, a.Y * cp - a.Z * sp, a.Y * sp + a.Z * cp);         // pitch about right
        }

        // fit the projected mesh into the square
        float minX = float.MaxValue, maxX = float.MinValue, minZ = float.MaxValue, maxZ = float.MinValue;
        foreach (var g in geos) foreach (var p in g.P)
            {
                var v = View(p);
                minX = Math.Min(minX, v.X); maxX = Math.Max(maxX, v.X); minZ = Math.Min(minZ, v.Z); maxZ = Math.Max(maxZ, v.Z);
            }
        float span = Math.Max(maxX - minX, maxZ - minZ);
        if (span <= 0) return;
        float scale = W * 0.86f / span;
        float ox = W / 2f - (minX + maxX) / 2 * scale, oz = W / 2f + (minZ + maxZ) / 2 * scale;

        var col = new float[W * W * 3];
        var depth = new float[W * W];
        var hit = new bool[W * W];
        Array.Fill(depth, float.MinValue);

        var L1 = Vector3.Normalize(new Vector3(-0.45f, 0.75f, 0.6f));
        var L2 = Vector3.Normalize(new Vector3(0.7f, 0.45f, -0.05f));
        var V = Vector3.UnitY;
        var H1 = Vector3.Normalize(L1 + V);
        float specPow = Math.Clamp(sh.Falloff, 12f, 160f);
        float specMul = Math.Clamp(sh.SpecInt, 0.25f, 1.5f) * 1.5f;

        foreach (var g in geos)
        {
            int n = g.P.Count;
            var sx = new float[n]; var sz = new float[n]; var sd = new float[n]; var nn = new Vector3[n];
            for (int i = 0; i < n; i++)
            {
                var v = View(g.P[i]);
                sx[i] = ox + v.X * scale; sz[i] = oz - v.Z * scale; sd[i] = v.Y;
                nn[i] = View(g.N[i]);
            }
            for (int t = 0; t + 2 < g.I.Count; t += 3)
            {
                int a = g.I[t], b = g.I[t + 1], c = g.I[t + 2];
                float x0 = sx[a], y0 = sz[a], x1 = sx[b], y1 = sz[b], x2 = sx[c], y2 = sz[c];
                float area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0);
                if (MathF.Abs(area) < 1e-6f) continue;
                int bx0 = Math.Max(0, (int)MathF.Floor(Math.Min(x0, Math.Min(x1, x2))));
                int bx1 = Math.Min(W - 1, (int)MathF.Ceiling(Math.Max(x0, Math.Max(x1, x2))));
                int by0 = Math.Max(0, (int)MathF.Floor(Math.Min(y0, Math.Min(y1, y2))));
                int by1 = Math.Min(W - 1, (int)MathF.Ceiling(Math.Max(y0, Math.Max(y1, y2))));
                for (int py = by0; py <= by1; py++)
                {
                    float fy = py + 0.5f;
                    for (int px = bx0; px <= bx1; px++)
                    {
                        float fx = px + 0.5f;
                        float w0 = ((x1 - fx) * (y2 - fy) - (x2 - fx) * (y1 - fy)) / area;
                        float w1 = ((x2 - fx) * (y0 - fy) - (x0 - fx) * (y2 - fy)) / area;
                        float w2 = 1 - w0 - w1;
                        if (w0 < 0 || w1 < 0 || w2 < 0) continue;
                        float d = w0 * sd[a] + w1 * sd[b] + w2 * sd[c];
                        int k = py * W + px;
                        if (d <= depth[k]) continue;

                        var uv = g.UV[a] * w0 + g.UV[b] * w1 + g.UV[c] * w2;
                        var N = Vector3.Normalize(nn[a] * w0 + nn[b] * w1 + nn[c] * w2 + new Vector3(0, 1e-5f, 0));
                        if (Vector3.Dot(N, V) < 0) N = -N;
                        var alb = Sample(diff, uv);
                        if (alb.W < 0.35f) continue;
                        float si = spec != null ? Sample(spec, uv).X : 0.6f;
                        float lit = 0.36f + 0.72f * Math.Max(0, Vector3.Dot(N, L1)) + 0.26f * Math.Max(0, Vector3.Dot(N, L2));
                        float s = MathF.Pow(Math.Max(0, Vector3.Dot(N, H1)), specPow) * specMul * (0.25f + si);
                        float rim = MathF.Pow(1 - Math.Max(0, Vector3.Dot(N, V)), 3) * 0.18f;
                        depth[k] = d; hit[k] = true;
                        col[k * 3] = alb.X * lit + s + rim;
                        col[k * 3 + 1] = alb.Y * lit + s + rim;
                        col[k * 3 + 2] = alb.Z * lit + s + rim;
                    }
                }
            }
        }

        // downsample to the icon, alpha = coverage
        var px8 = new byte[size * size * 4];
        for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
            {
                float r = 0, gg = 0, b = 0; int cov = 0;
                for (int j = 0; j < SS; j++)
                    for (int i = 0; i < SS; i++)
                    {
                        int k = (y * SS + j) * W + x * SS + i;
                        if (!hit[k]) continue;
                        cov++; r += col[k * 3]; gg += col[k * 3 + 1]; b += col[k * 3 + 2];
                    }
                int o = (y * size + x) * 4;
                if (cov == 0) continue;
                px8[o] = Byte(r / cov); px8[o + 1] = Byte(gg / cov); px8[o + 2] = Byte(b / cov);
                px8[o + 3] = (byte)(255 * cov / (SS * SS));
            }
        Png.Write(path, px8, size, size);
    }

    static byte Byte(float v) => (byte)Math.Clamp((int)(v * 255 + 0.5f), 0, 255);

    static Vector4 Sample(P.Img img, Vector2 uv)
    {
        float u = uv.X - MathF.Floor(uv.X), v = uv.Y - MathF.Floor(uv.Y);
        int x = Math.Clamp((int)(u * img.W), 0, img.W - 1), y = Math.Clamp((int)(v * img.H), 0, img.H - 1);
        int o = (y * img.W + x) * 4;
        return new Vector4(img.Rgba[o] / 255f, img.Rgba[o + 1] / 255f, img.Rgba[o + 2] / 255f, img.Rgba[o + 3] / 255f);
    }
}

static class Png
{
    static readonly uint[] Crc = MakeCrc();

    static uint[] MakeCrc()
    {
        var t = new uint[256];
        for (uint n = 0; n < 256; n++)
        {
            uint c = n;
            for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
            t[n] = c;
        }
        return t;
    }

    static void Chunk(Stream s, string type, byte[] data)
    {
        var len = BitConverter.GetBytes((uint)data.Length); if (BitConverter.IsLittleEndian) Array.Reverse(len);
        s.Write(len);
        var tb = System.Text.Encoding.ASCII.GetBytes(type);
        s.Write(tb); s.Write(data);
        uint c = 0xFFFFFFFFu;
        foreach (var b in tb) c = Crc[(c ^ b) & 0xFF] ^ (c >> 8);
        foreach (var b in data) c = Crc[(c ^ b) & 0xFF] ^ (c >> 8);
        var cb = BitConverter.GetBytes(c ^ 0xFFFFFFFFu); if (BitConverter.IsLittleEndian) Array.Reverse(cb);
        s.Write(cb);
    }

    public static void Write(string path, byte[] rgba, int w, int h)
    {
        using var fs = File.Create(path);
        fs.Write(new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A });
        var ihdr = new byte[13];
        ihdr[0] = (byte)(w >> 24); ihdr[1] = (byte)(w >> 16); ihdr[2] = (byte)(w >> 8); ihdr[3] = (byte)w;
        ihdr[4] = (byte)(h >> 24); ihdr[5] = (byte)(h >> 16); ihdr[6] = (byte)(h >> 8); ihdr[7] = (byte)h;
        ihdr[8] = 8; ihdr[9] = 6; // 8-bit RGBA
        Chunk(fs, "IHDR", ihdr);
        using var ms = new MemoryStream();
        using (var z = new ZLibStream(ms, CompressionLevel.SmallestSize, true))
        {
            for (int y = 0; y < h; y++)
            {
                z.WriteByte(0);
                z.Write(rgba, y * w * 4, w * 4);
            }
        }
        Chunk(fs, "IDAT", ms.ToArray());
        Chunk(fs, "IEND", Array.Empty<byte>());
    }
}
