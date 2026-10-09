using System.Numerics;

namespace NayzeeeSneakerStudio;

/// <summary>Something to draw: a mesh, a texture per material and where it sits.</summary>
sealed class RenderItem
{
    public Mesh Mesh = null!;
    public Rgba?[] Textures = Array.Empty<Rgba?>();
    public Matrix4x4 World = Matrix4x4.Identity;
}

/// <summary>
/// A small software renderer for inventory icons and previews: perspective-correct textures,
/// two soft lights, transparent background, framed to fit and supersampled.
/// </summary>
static class Renderer
{
    static float ToLin(float c) => MathF.Pow(c, 2.2f);
    static float ToSrgb(float c) => MathF.Pow(Math.Clamp(c, 0f, 1f), 1f / 2.2f);

    /// <summary>
    /// Renders the items seen from direction `dir` (pointing from the camera towards the object),
    /// framed tightly, `size` pixels square.
    /// </summary>
    public static Rgba Icon(IList<RenderItem> items, Vector3 dir, int size = 256, float fovDeg = 30f, float margin = 0.07f)
    {
        // bounding sphere of everything
        var lo = new Vector3(float.MaxValue); var hi = new Vector3(float.MinValue);
        foreach (var it in items)
            foreach (var p in it.Mesh.P) { var w = Vector3.Transform(p, it.World); lo = Vector3.Min(lo, w); hi = Vector3.Max(hi, w); }
        var centre = (lo + hi) / 2;
        float radius = (hi - lo).Length() / 2;
        float fov = fovDeg * MathF.PI / 180f;
        float dist = radius / MathF.Sin(fov / 2) * 1.02f;
        dir = Vector3.Normalize(dir);
        var cam = centre - dir * dist;

        int big = size * 3;
        var raw = Draw(items, cam, centre, fov, big, big);

        // crop to what was drawn, square, with a margin, then average down to `size`
        int x0 = big, y0 = big, x1 = -1, y1 = -1;
        for (int y = 0; y < big; y++)
            for (int x = 0; x < big; x++)
                if (raw[(y * big + x) * 4 + 3] > 0.5f) { x0 = Math.Min(x0, x); x1 = Math.Max(x1, x); y0 = Math.Min(y0, y); y1 = Math.Max(y1, y); }
        if (x1 < 0) return new Rgba(size, size, new byte[size * size * 4]);
        float cx = (x0 + x1) / 2f, cy = (y0 + y1) / 2f;
        float side = MathF.Max(x1 - x0, y1 - y0) * (1 + margin * 2);
        return Resample(raw, big, big, cx - side / 2, cy - side / 2, side, size);
    }

    static Rgba Resample(float[] src, int w, int h, float sx, float sy, float side, int size)
    {
        var o = new byte[size * size * 4];
        float step = side / size;
        int sub = Math.Max(1, (int)MathF.Ceiling(step));
        for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
            {
                float r = 0, g = 0, b = 0, a = 0; int n = 0;
                for (int j = 0; j < sub; j++)
                    for (int i = 0; i < sub; i++)
                    {
                        int px = (int)(sx + (x + (i + 0.5f) / sub) * step), py = (int)(sy + (y + (j + 0.5f) / sub) * step);
                        n++;
                        if (px < 0 || py < 0 || px >= w || py >= h) continue;
                        int k = (py * w + px) * 4;
                        float al = src[k + 3];
                        r += src[k] * al; g += src[k + 1] * al; b += src[k + 2] * al; a += al;
                    }
                int q = (y * size + x) * 4;
                if (a > 0)
                {
                    o[q] = (byte)(ToSrgb(r / a) * 255 + 0.5f);
                    o[q + 1] = (byte)(ToSrgb(g / a) * 255 + 0.5f);
                    o[q + 2] = (byte)(ToSrgb(b / a) * 255 + 0.5f);
                }
                o[q + 3] = (byte)Math.Clamp(a / n * 255 + 0.5f, 0, 255);
            }
        return new Rgba(size, size, o);
    }

    /// <summary>Linear RGB + coverage per pixel.</summary>
    static float[] Draw(IList<RenderItem> items, Vector3 cam, Vector3 target, float fov, int w, int h)
    {
        var view = Matrix4x4.CreateLookAt(cam, target, Vector3.UnitZ);
        var proj = Matrix4x4.CreatePerspectiveFieldOfView(fov, (float)w / h, 0.01f, 100f);
        var vp = view * proj;
        var color = new float[w * h * 4];
        var depth = Enumerable.Repeat(float.MaxValue, w * h).ToArray();

        var key = Vector3.Normalize(new Vector3(-0.55f, -0.75f, 0.9f));
        var fill = Vector3.Normalize(new Vector3(0.8f, -0.2f, 0.35f));
        var rim = Vector3.Normalize(new Vector3(0.1f, 0.9f, 0.6f));

        foreach (var it in items)
        {
            var m = it.Mesh;
            int n = m.P.Count;
            var wp = new Vector3[n]; var wn = new Vector3[n]; var cs = new Vector4[n];
            for (int i = 0; i < n; i++)
            {
                wp[i] = Vector3.Transform(m.P[i], it.World);
                var nn = Vector3.TransformNormal(m.N[i], it.World);
                wn[i] = nn.LengthSquared() > 0 ? Vector3.Normalize(nn) : Vector3.UnitZ;
                cs[i] = Vector4.Transform(new Vector4(wp[i], 1), vp);
            }
            for (int t = 0; t < m.Tris; t++)
            {
                int ia = m.I[t * 3], ib = m.I[t * 3 + 1], ic = m.I[t * 3 + 2];
                var A = cs[ia]; var B = cs[ib]; var C = cs[ic];
                if (A.W < 0.01f || B.W < 0.01f || C.W < 0.01f) continue;
                var tex = it.Textures.Length > m.M[t] ? it.Textures[m.M[t]] : null;
                Raster(A, B, C, ia, ib, ic, m, wp, wn, tex, cam, key, fill, rim, color, depth, w, h);
            }
        }
        return color;
    }

    static void Raster(Vector4 A, Vector4 B, Vector4 C, int ia, int ib, int ic, Mesh m, Vector3[] wp, Vector3[] wn, Rgba? tex,
        Vector3 cam, Vector3 key, Vector3 fill, Vector3 rim, float[] color, float[] depth, int w, int h)
    {
        Vector3 S(Vector4 v) => new((v.X / v.W * 0.5f + 0.5f) * w, (1 - (v.Y / v.W * 0.5f + 0.5f)) * h, v.Z / v.W);
        var a = S(A); var b = S(B); var c = S(C);
        float area = (b.X - a.X) * (c.Y - a.Y) - (b.Y - a.Y) * (c.X - a.X);
        if (MathF.Abs(area) < 1e-9f) return;
        int minX = Math.Max(0, (int)MathF.Floor(MathF.Min(a.X, MathF.Min(b.X, c.X))));
        int maxX = Math.Min(w - 1, (int)MathF.Ceiling(MathF.Max(a.X, MathF.Max(b.X, c.X))));
        int minY = Math.Max(0, (int)MathF.Floor(MathF.Min(a.Y, MathF.Min(b.Y, c.Y))));
        int maxY = Math.Min(h - 1, (int)MathF.Ceiling(MathF.Max(a.Y, MathF.Max(b.Y, c.Y))));
        if (minX > maxX || minY > maxY) return;
        float iwa = 1 / A.W, iwb = 1 / B.W, iwc = 1 / C.W;
        var ta = m.T[ia]; var tb = m.T[ib]; var tc = m.T[ic];
        for (int y = minY; y <= maxY; y++)
            for (int x = minX; x <= maxX; x++)
            {
                float px = x + 0.5f, py = y + 0.5f;
                float w0 = ((b.X - px) * (c.Y - py) - (b.Y - py) * (c.X - px)) / area;
                float w1 = ((c.X - px) * (a.Y - py) - (c.Y - py) * (a.X - px)) / area;
                float w2 = 1 - w0 - w1;
                if (w0 < 0 || w1 < 0 || w2 < 0) continue;
                float z = w0 * a.Z + w1 * b.Z + w2 * c.Z;
                int k = y * w + x;
                if (z >= depth[k]) continue;
                // perspective-correct weights
                float p0 = w0 * iwa, p1 = w1 * iwb, p2 = w2 * iwc, ps = p0 + p1 + p2;
                p0 /= ps; p1 /= ps; p2 /= ps;
                var uv = ta * p0 + tb * p1 + tc * p2;
                float r = 0.62f, g = 0.62f, bl = 0.62f, al = 1;
                if (tex != null) { tex.Sample(uv.X, uv.Y, out r, out g, out bl, out al); r = ToLin(r); g = ToLin(g); bl = ToLin(bl); }
                else { r = g = bl = ToLin(0.62f); }
                var pos = wp[ia] * p0 + wp[ib] * p1 + wp[ic] * p2;
                var nrm = Vector3.Normalize(wn[ia] * p0 + wn[ib] * p1 + wn[ic] * p2);
                var toCam = Vector3.Normalize(cam - pos);
                if (Vector3.Dot(nrm, toCam) < 0) nrm = -nrm;   // inside of the shoe / box: light it too
                float lk = MathF.Max(0, Vector3.Dot(nrm, key)), lf = MathF.Max(0, Vector3.Dot(nrm, fill));
                float lr = MathF.Pow(1 - MathF.Max(0, Vector3.Dot(nrm, toCam)), 3) * MathF.Max(0, Vector3.Dot(nrm, rim) + 0.3f);
                var half = Vector3.Normalize(key + toCam);
                float spec = MathF.Pow(MathF.Max(0, Vector3.Dot(nrm, half)), 40) * 0.12f;
                float light = 0.32f + 1.05f * lk + 0.35f * lf + 0.35f * lr;
                depth[k] = z;
                color[k * 4] = r * light + spec;
                color[k * 4 + 1] = g * light + spec;
                color[k * 4 + 2] = bl * light + spec;
                color[k * 4 + 3] = 1;
            }
    }
}
