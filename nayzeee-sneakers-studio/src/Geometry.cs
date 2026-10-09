using System.Globalization;
using System.Numerics;
using CodeWalker.GameFiles;

namespace NayzeeeSneakerStudio;

/// <summary>One material of the worn shoe: which texture it shows and how.</summary>
sealed class Material
{
    public string Diffuse = "";        // texture name the shader asks for
    public Texture? Embedded;          // found inside the .ydd itself (same for every colourway)
    public bool Cutout;                // alpha-tested / decal shader: see-through texels are holes
    public bool Decal;                 // decal shader: keeps its own texture, the colourway doesn't replace it
}

/// <summary>Triangle soup with a material per triangle. GTA axes: Z up, +Y forward, metres.</summary>
sealed class Mesh
{
    public List<Vector3> P = new(), N = new();
    public List<Vector2> T = new();
    public List<int> I = new();      // 3 per triangle
    public List<int> M = new();      // material per triangle
    public List<Material> Mats = new();

    public int Tris => I.Count / 3;

    public (Vector3 lo, Vector3 hi) Bounds()
    {
        var lo = new Vector3(float.MaxValue); var hi = new Vector3(float.MinValue);
        foreach (var p in P) { lo = Vector3.Min(lo, p); hi = Vector3.Max(hi, p); }
        return (lo, hi);
    }

    /// <summary>A copy holding only the given triangles (vertices re-indexed).</summary>
    public Mesh Subset(IEnumerable<int> tris)
    {
        var o = new Mesh { Mats = Mats };
        var map = new Dictionary<int, int>();
        foreach (var t in tris)
        {
            for (int k = 0; k < 3; k++)
            {
                int v = I[t * 3 + k];
                if (!map.TryGetValue(v, out int nv))
                {
                    nv = o.P.Count; map[v] = nv;
                    o.P.Add(P[v]); o.N.Add(N[v]); o.T.Add(T[v]);
                }
                o.I.Add(nv);
            }
            o.M.Add(M[t]);
        }
        return o;
    }

    public void Append(Mesh other)
    {
        int b = P.Count;
        P.AddRange(other.P); N.AddRange(other.N); T.AddRange(other.T);
        foreach (var i in other.I) I.Add(i + b);
        M.AddRange(other.M);
    }

    public void Rotate(Matrix4x4 m)
    {
        for (int i = 0; i < P.Count; i++)
        {
            P[i] = Vector3.Transform(P[i], m);
            var n = Vector3.TransformNormal(N[i], m);
            N[i] = n.LengthSquared() > 1e-12f ? Vector3.Normalize(n) : n;
        }
    }

    public void Move(Vector3 d) { for (int i = 0; i < P.Count; i++) P[i] += d; }
    public void Scale(float s) { for (int i = 0; i < P.Count; i++) P[i] *= s; }
}

static class Geometry
{
    // ped shaders whose see-through texels are cut out on the worn shoe
    static readonly HashSet<uint> CutoutShaders = new[]
    {
        "ped_alpha", "ped_cutout", "ped_decal", "ped_default_cutout", "ped_hair_cutout_alpha",
        "ped_decal_decoration", "ped_decal_nodiff", "ped_decal_expensive", "ped_hair_spiked",
    }.SelectMany(n => new[] { JenkHash.GenHash(n), JenkHash.GenHash(n + ".sps") }).ToHashSet();

    static readonly HashSet<uint> DecalShaders = new[]
    {
        "ped_decal", "ped_decal_decoration", "ped_decal_nodiff", "ped_decal_expensive", "ped_decal_medals",
    }.SelectMany(n => new[] { JenkHash.GenHash(n), JenkHash.GenHash(n + ".sps") }).ToHashSet();

    static float[] Floats(string s) =>
        s.Split(new[] { ' ', ',' }, StringSplitOptions.RemoveEmptyEntries)
         .Select(x => float.Parse(x, CultureInfo.InvariantCulture)).ToArray();

    static int CountTris(DrawableModel[]? models) =>
        models == null ? 0 : models.Sum(m => m.Geometries?.Sum(g => (g.IndexBuffer?.Indices?.Length ?? 0) / 3) ?? 0);

    /// <summary>
    /// Reads the worn shoe out of a clothing drawable: the most detailed LOD with at most
    /// maxTris triangles (the lightest one if they're all bigger).
    /// </summary>
    public static Mesh Read(Drawable d, out string lod, int maxTris = 30000)
    {
        var dm = d.DrawableModels;
        var lods = new (string name, DrawableModel[]? models)[]
            { ("high", dm?.High), ("medium", dm?.Med), ("low", dm?.Low), ("very low", dm?.VLow) };
        var have = lods.Where(l => CountTris(l.models) > 0).ToList();
        if (have.Count == 0) throw new Exception("the .ydd has no meshes");
        var pick = have.FirstOrDefault(l => CountTris(l.models) <= maxTris);
        if (pick.models == null) pick = have.Last();
        lod = pick.name;

        var mesh = new Mesh();
        var shaders = d.ShaderGroup?.Shaders?.data_items ?? Array.Empty<ShaderFX>();
        var embedded = d.ShaderGroup?.TextureDictionary?.Textures?.data_items ?? Array.Empty<Texture>();
        var matOf = new Dictionary<int, int>();

        foreach (var model in pick.models!)
            foreach (var g in model.Geometries ?? Array.Empty<DrawableGeometry>())
            {
                var vd = g.VertexData;
                var idx = g.IndexBuffer?.Indices;
                if (vd == null || idx == null || vd.VertexCount == 0) continue;
                uint flags = vd.Info.Flags;
                bool hasN = ((flags >> 3) & 1) != 0, hasT = ((flags >> 6) & 1) != 0;
                if (((flags >> 0) & 1) == 0) continue;

                if (!matOf.TryGetValue(g.ShaderID, out int mat))
                {
                    var m = new Material();
                    if (g.ShaderID < shaders.Length)
                    {
                        var s = shaders[g.ShaderID];
                        m.Cutout = CutoutShaders.Contains(s.Name.Hash) || CutoutShaders.Contains(s.FileName.Hash);
                        m.Decal = DecalShaders.Contains(s.Name.Hash) || DecalShaders.Contains(s.FileName.Hash);
                        var pl = s.ParametersList;
                        for (int i = 0; i < (pl?.Parameters?.Length ?? 0); i++)
                            if (pl!.Hashes[i].ToString().Equals("DiffuseSampler", StringComparison.OrdinalIgnoreCase)
                                && pl.Parameters[i].Data is TextureBase tb)
                                m.Diffuse = tb.Name ?? "";
                    }
                    m.Embedded = embedded.FirstOrDefault(t => string.Equals(t.Name, m.Diffuse, StringComparison.OrdinalIgnoreCase));
                    mat = mesh.Mats.Count; mesh.Mats.Add(m); matOf[g.ShaderID] = mat;
                }

                int b = mesh.P.Count;
                for (int v = 0; v < vd.VertexCount; v++)
                {
                    var p = Floats(vd.GetString(v, 0, " "));
                    mesh.P.Add(new Vector3(p[0], p[1], p[2]));
                    if (hasN) { var n = Floats(vd.GetString(v, 3, " ")); mesh.N.Add(Vector3.Normalize(new Vector3(n[0], n[1], n[2]))); }
                    else mesh.N.Add(Vector3.UnitZ);
                    if (hasT) { var t = Floats(vd.GetString(v, 6, " ")); mesh.T.Add(new Vector2(t[0], t[1])); }
                    else mesh.T.Add(Vector2.Zero);
                }
                for (int i = 0; i + 2 < idx.Length; i += 3)
                {
                    int a = idx[i], c1 = idx[i + 1], c2 = idx[i + 2];
                    if (a >= vd.VertexCount || c1 >= vd.VertexCount || c2 >= vd.VertexCount) continue;
                    if (a == c1 || c1 == c2 || a == c2) continue;
                    mesh.I.Add(b + a); mesh.I.Add(b + c1); mesh.I.Add(b + c2);
                    mesh.M.Add(mat);
                }
                if (!hasN) RecomputeNormals(mesh, b);
            }
        if (mesh.Tris == 0) throw new Exception("the .ydd has no triangles");
        return mesh;
    }

    static void RecomputeNormals(Mesh m, int from)
    {
        var acc = new Vector3[m.P.Count];
        for (int t = 0; t < m.Tris; t++)
        {
            int a = m.I[t * 3], b = m.I[t * 3 + 1], c = m.I[t * 3 + 2];
            if (a < from) continue;
            var n = Vector3.Cross(m.P[b] - m.P[a], m.P[c] - m.P[a]);
            acc[a] += n; acc[b] += n; acc[c] += n;
        }
        for (int i = from; i < m.P.Count; i++)
            m.N[i] = acc[i].LengthSquared() > 1e-20f ? Vector3.Normalize(acc[i]) : Vector3.UnitZ;
    }

    // ------------------------------------------------------------ cleaning

    static bool IsSkin(byte r8, byte g8, byte b8)
    {
        float r = r8 / 255f, g = g8 / 255f, b = b8 / 255f;
        float max = MathF.Max(r, MathF.Max(g, b)), min = MathF.Min(r, MathF.Min(g, b));
        float v = max, s = max <= 0 ? 0 : (max - min) / max;
        float h = 0;
        if (max > min)
        {
            if (max == r) h = ((g - b) / (max - min)) % 6f;
            else if (max == g) h = (b - r) / (max - min) + 2f;
            else h = (r - g) / (max - min) + 4f;
            h *= 60f; if (h < 0) h += 360f;
        }
        return (h <= 40 || h >= 350) && s >= 0.22f && s <= 0.7f && v >= 0.3f && r > g && g > b && (r - b) > 0.12f;
    }

    /// <summary>
    /// Drops triangles a prop shouldn't draw: the wearer's bare skin (skin-tone drawables, i.e. open-toe
    /// heels and sandals) and texels cut out by alpha on the worn shoe. Whole pieces of mesh that are mostly
    /// dropped go too, so no stray bits of foot are left. textures[mat] = reference colourway, or null.
    /// </summary>
    public static Mesh Clean(Mesh m, Rgba?[] textures, bool skin, out int dropped)
    {
        int nt = m.Tris;
        var keep = new bool[nt];
        for (int t = 0; t < nt; t++)
        {
            keep[t] = true;
            var mat = m.Mats[m.M[t]];
            var tex = textures[m.M[t]];
            if (tex == null || (!skin && !mat.Cutout)) continue;
            var a = m.T[m.I[t * 3]]; var b = m.T[m.I[t * 3 + 1]]; var c = m.T[m.I[t * 3 + 2]];
            var pts = new[] { (a + b + c) / 3, (a * 2 + b + c) / 4, (a + b * 2 + c) / 4, (a + b + c * 2) / 4 };
            int votes = 0;
            foreach (var p in pts)
            {
                var px = tex.At(p.X, p.Y);
                if ((skin && IsSkin(px.r, px.g, px.b)) || (mat.Cutout && px.a < 128)) votes++;
            }
            keep[t] = votes * 2 < pts.Length;
        }
        // connected pieces (vertices welded by position)
        var weld = new Dictionary<(int, int, int), int>();
        var root = new int[m.P.Count];
        for (int i = 0; i < m.P.Count; i++)
        {
            var key = ((int)MathF.Round(m.P[i].X * 1e5f), (int)MathF.Round(m.P[i].Y * 1e5f), (int)MathF.Round(m.P[i].Z * 1e5f));
            if (!weld.TryGetValue(key, out int w)) { w = i; weld[key] = i; }
            root[i] = w;
        }
        var parent = Enumerable.Range(0, m.P.Count).ToArray();
        int Find(int x) { while (parent[x] != x) { parent[x] = parent[parent[x]]; x = parent[x]; } return x; }
        for (int t = 0; t < nt; t++)
        {
            int a = Find(root[m.I[t * 3]]), b = Find(root[m.I[t * 3 + 1]]), c = Find(root[m.I[t * 3 + 2]]);
            parent[b] = a; parent[Find(c)] = a;
        }
        var comp = new int[nt];
        var total = new Dictionary<int, int>(); var bad = new Dictionary<int, int>();
        for (int t = 0; t < nt; t++)
        {
            comp[t] = Find(root[m.I[t * 3]]);
            total[comp[t]] = total.GetValueOrDefault(comp[t]) + 1;
            if (!keep[t]) bad[comp[t]] = bad.GetValueOrDefault(comp[t]) + 1;
        }
        for (int t = 0; t < nt; t++)
            if (bad.GetValueOrDefault(comp[t]) >= 0.35 * total[comp[t]]) keep[t] = false;
        dropped = keep.Count(k => !k);
        if (dropped == nt) { dropped = 0; return m; }   // never throw the whole shoe away
        return m.Subset(Enumerable.Range(0, nt).Where(t => keep[t]));
    }

    // ------------------------------------------------------------ packing

    /// <summary>Triangles of the -X shoe and the +X shoe (by triangle centre).</summary>
    public static (Mesh left, Mesh right) Split(Mesh m)
    {
        var (lo, hi) = m.Bounds();
        float mid = (lo.X + hi.X) / 2;
        var l = new List<int>(); var r = new List<int>();
        for (int t = 0; t < m.Tris; t++)
        {
            float cx = (m.P[m.I[t * 3]].X + m.P[m.I[t * 3 + 1]].X + m.P[m.I[t * 3 + 2]].X) / 3;
            (cx < mid ? l : r).Add(t);
        }
        return (m.Subset(l), m.Subset(r));
    }

    static Matrix4x4 RotZ(float deg) => Matrix4x4.CreateRotationZ(deg * MathF.PI / 180f);
    static Matrix4x4 RotY(float deg) => Matrix4x4.CreateRotationY(deg * MathF.PI / 180f);

    static List<Vector3> SurfacePoints(Mesh m)
    {
        var pts = new List<Vector3>(m.P);
        for (int t = 0; t < m.Tris; t++)
        {
            var a = m.P[m.I[t * 3]]; var b = m.P[m.I[t * 3 + 1]]; var c = m.P[m.I[t * 3 + 2]];
            pts.Add((a + b + c) / 3); pts.Add((a + b) / 2); pts.Add((b + c) / 2); pts.Add((c + a) / 2);
        }
        return pts;
    }

    /// <summary>
    /// Turns a worn pair (ped space, standing) into a boxed pair with the origin at the bottom centre.
    ///   side = false  both shoes upright along X, heel-to-toe (a sneaker box)
    ///   side = true   both lying on their side, one turned end for end so they nest (a heel / boot box)
    /// </summary>
    public static Mesh Arrange(Mesh pair, bool side, out Vector3 size)
    {
        var (left, right) = Split(pair);
        var parts = new[] { left, right };
        for (int k = 0; k < 2; k++)
        {
            var p = parts[k];
            if (p.Tris == 0) continue;
            if (side)
            {
                p.Rotate(RotY(k == 0 ? -90f : 90f));
                if (k == 1) p.Rotate(RotZ(180f));
                var (lo, _) = p.Bounds();
                p.Move(new Vector3(0, 0, -lo.Z));
            }
            else
            {
                p.Rotate(RotZ(k == 0 ? -90f : 90f));
            }
            var (l2, h2) = p.Bounds();
            p.Move(new Vector3(-(l2.X + h2.X) / 2, 0, 0));
        }
        if (parts[0].Tris == 0 || parts[1].Tris == 0)
        {
            var only = parts[0].Tris > 0 ? parts[0] : parts[1];
            return Finish(only, out size);
        }

        // slide shoe B along -Y until it clears shoe A in every slice along X; for side-laid pairs
        // also try sliding B along X, so a foot can tuck in beside the other's shaft
        const float W = 0.005f, Gap = 0.004f;
        var pa = SurfacePoints(parts[0]); var pb = SurfacePoints(parts[1]);
        float x0 = MathF.Min(pa.Min(p => p.X), pb.Min(p => p.X)) - 0.2f;
        float x1 = MathF.Max(pa.Max(p => p.X), pb.Max(p => p.X)) + 0.2f;
        int bins = (int)MathF.Ceiling((x1 - x0) / W) + 1;
        var aMin = Enumerable.Repeat(float.MaxValue, bins).ToArray();
        var bMax = Enumerable.Repeat(float.MinValue, bins).ToArray();
        foreach (var p in pa) { int i = (int)((p.X - x0) / W); aMin[i] = MathF.Min(aMin[i], p.Y); }
        foreach (var p in pb) { int i = (int)((p.X - x0) / W); bMax[i] = MathF.Max(bMax[i], p.Y); }
        float Win(float[] arr, int i, bool max)
        {
            float v = max ? float.MinValue : float.MaxValue;
            for (int j = i - 1; j <= i + 1; j++)
                if (j >= 0 && j < arr.Length) v = max ? MathF.Max(v, arr[j]) : MathF.Min(v, arr[j]);
            return v;
        }
        var aW = Enumerable.Range(0, bins).Select(i => Win(aMin, i, false)).ToArray();
        var bW = Enumerable.Range(0, bins).Select(i => Win(bMax, i, true)).ToArray();

        float bestScore = float.MaxValue, bestDx = 0, bestNeed = 0;
        int maxShift = side ? 30 : 0;   // +-15 cm in 5 mm steps
        var aLo = pa.Aggregate(new Vector3(float.MaxValue), Vector3.Min); var aHi = pa.Aggregate(new Vector3(float.MinValue), Vector3.Max);
        var bLo = pb.Aggregate(new Vector3(float.MaxValue), Vector3.Min); var bHi = pb.Aggregate(new Vector3(float.MinValue), Vector3.Max);
        for (int s = -maxShift; s <= maxShift; s += 2)
        {
            float need = float.MinValue;
            for (int i = 0; i < bins; i++)
            {
                int j = i - s;   // B shifted right by s bins: B's bin j lands on A's bin i
                if (j < 0 || j >= bins) continue;
                if (aW[i] == float.MaxValue || bW[j] == float.MinValue) continue;
                need = MathF.Max(need, bW[j] - aW[i]);
            }
            if (need == float.MinValue) continue;
            float dx = s * W, dy = -(need + Gap);
            var lo = Vector3.Min(aLo, bLo + new Vector3(dx, dy, 0)); var hi = Vector3.Max(aHi, bHi + new Vector3(dx, dy, 0));
            var ext = hi - lo;
            float score = ext.X * ext.Y + 0.5f * MathF.Pow(MathF.Max(ext.X, ext.Y), 2);
            if (score < bestScore) { bestScore = score; bestDx = dx; bestNeed = need; }
        }
        parts[1].Move(new Vector3(bestDx, -(bestNeed + Gap), 0));
        var all = new Mesh { Mats = pair.Mats };
        all.Append(parts[0]); all.Append(parts[1]);
        return Finish(all, out size);
    }

    static Mesh Finish(Mesh m, out Vector3 size)
    {
        var (lo, hi) = m.Bounds();
        m.Move(new Vector3(-(lo.X + hi.X) / 2, -(lo.Y + hi.Y) / 2, -lo.Z));
        size = hi - lo;
        return m;
    }

    /// <summary>The worn pair standing, origin at the bottom centre (for previews).</summary>
    public static Mesh Standing(Mesh pair)
    {
        var m = new Mesh { Mats = pair.Mats };
        m.Append(pair);
        return Finish(m, out _);
    }
}
