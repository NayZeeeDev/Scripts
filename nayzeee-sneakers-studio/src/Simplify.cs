using System.Numerics;

namespace NayzeeeSneakerStudio;

/// <summary>
/// Quadric edge-collapse mesh reduction, after "Fast Quadric Mesh Simplification" by Sven Forstmann
/// (MIT). Open edges stay where they are, and clothing meshes are split along their UV seams, so
/// seams are open edges too: the texture layout never smears.
/// </summary>
static class Simplify
{
    struct Q
    {
        public double M0, M1, M2, M3, M4, M5, M6, M7, M8, M9;
        public Q(double a, double b, double c, double d)
        {
            M0 = a * a; M1 = a * b; M2 = a * c; M3 = a * d; M4 = b * b; M5 = b * c; M6 = b * d; M7 = c * c; M8 = c * d; M9 = d * d;
        }
        public static Q operator +(Q x, Q y) => new()
        {
            M0 = x.M0 + y.M0, M1 = x.M1 + y.M1, M2 = x.M2 + y.M2, M3 = x.M3 + y.M3, M4 = x.M4 + y.M4,
            M5 = x.M5 + y.M5, M6 = x.M6 + y.M6, M7 = x.M7 + y.M7, M8 = x.M8 + y.M8, M9 = x.M9 + y.M9,
        };
        public double this[int i] => i switch
        {
            0 => M0, 1 => M1, 2 => M2, 3 => M3, 4 => M4, 5 => M5, 6 => M6, 7 => M7, 8 => M8, _ => M9,
        };
        public double Det(int a11, int a12, int a13, int a21, int a22, int a23, int a31, int a32, int a33) =>
            this[a11] * this[a22] * this[a33] + this[a13] * this[a21] * this[a32] + this[a12] * this[a23] * this[a31]
            - this[a13] * this[a22] * this[a31] - this[a11] * this[a23] * this[a32] - this[a12] * this[a21] * this[a33];
    }

    sealed class Tri { public int[] V = new int[3]; public double[] Err = new double[4]; public bool Deleted, Dirty; public Vector3 N; public int Mat; }
    sealed class Vert { public Vector3 P, Nrm; public Vector2 Uv; public Q Q; public int TStart, TCount; public bool Border; }
    struct Ref { public int Tid, TVertex; }

    static double VertexError(Q q, double x, double y, double z) =>
        q.M0 * x * x + 2 * q.M1 * x * y + 2 * q.M2 * x * z + 2 * q.M3 * x + q.M4 * y * y
        + 2 * q.M5 * y * z + 2 * q.M6 * y + q.M7 * z * z + 2 * q.M8 * z + q.M9;

    /// <summary>Returns a copy of `m` reduced to about `target` triangles (or as close as it safely gets).</summary>
    public static Mesh Run(Mesh m, int target, double aggressiveness = 7)
    {
        // weld vertices that are the same point with the same UV (many clothing exports split every
        // triangle); vertices on a UV seam differ in UV, so seams stay open edges
        var verts = new List<Vert>();
        var weld = new Dictionary<(int, int, int, int, int), int>();
        var remap = new int[m.P.Count];
        for (int i = 0; i < m.P.Count; i++)
        {
            var key = ((int)MathF.Round(m.P[i].X * 2e4f), (int)MathF.Round(m.P[i].Y * 2e4f), (int)MathF.Round(m.P[i].Z * 2e4f),
                       (int)MathF.Round(m.T[i].X * 4096f), (int)MathF.Round(m.T[i].Y * 4096f));
            if (!weld.TryGetValue(key, out int w))
            {
                w = verts.Count; weld[key] = w;
                verts.Add(new Vert { P = m.P[i], Nrm = m.N[i], Uv = m.T[i] });
            }
            else verts[w].Nrm += m.N[i];
            remap[i] = w;
        }
        foreach (var v in verts) if (v.Nrm.LengthSquared() > 1e-12f) v.Nrm = Vector3.Normalize(v.Nrm);
        var tris = new List<Tri>();
        for (int t = 0; t < m.Tris; t++)
        {
            int a = remap[m.I[t * 3]], b = remap[m.I[t * 3 + 1]], c = remap[m.I[t * 3 + 2]];
            if (a == b || b == c || a == c) continue;
            tris.Add(new Tri { V = new[] { a, b, c }, Mat = m.M[t] });
        }
        var refs = new List<Ref>();
        int deletedTris = 0, startCount = tris.Count;
        var del0 = new List<bool>(); var del1 = new List<bool>();

        double CalcError(int a, int b, out Vector3 result, out double edgeT)
        {
            var q = verts[a].Q + verts[b].Q;
            bool border = verts[a].Border && verts[b].Border;
            double det = q.Det(0, 1, 2, 1, 4, 5, 2, 5, 7);
            var p1 = verts[a].P; var p2 = verts[b].P;
            double err;
            if (det != 0 && !border)
            {
                result = new Vector3(
                    (float)(-1 / det * q.Det(1, 2, 3, 4, 5, 6, 5, 7, 8)),
                    (float)(1 / det * q.Det(0, 2, 3, 1, 5, 6, 2, 7, 8)),
                    (float)(-1 / det * q.Det(0, 1, 3, 1, 4, 6, 2, 5, 8)));
                err = VertexError(q, result.X, result.Y, result.Z);
            }
            else
            {
                var p3 = (p1 + p2) / 2;
                double e1 = VertexError(q, p1.X, p1.Y, p1.Z), e2 = VertexError(q, p2.X, p2.Y, p2.Z), e3 = VertexError(q, p3.X, p3.Y, p3.Z);
                err = Math.Min(e1, Math.Min(e2, e3));
                result = err == e1 ? p1 : err == e2 ? p2 : p3;
            }
            var d = p2 - p1;
            float len = d.LengthSquared();
            edgeT = len > 1e-20f ? Math.Clamp(Vector3.Dot(result - p1, d) / len, 0, 1) : 0;
            return err;
        }

        bool Flipped(Vector3 p, int i1, Vert v0, List<bool> deleted)
        {
            for (int k = 0; k < v0.TCount; k++)
            {
                var r = refs[v0.TStart + k];
                var t = tris[r.Tid];
                if (t.Deleted) continue;
                int s = r.TVertex;
                int id1 = t.V[(s + 1) % 3], id2 = t.V[(s + 2) % 3];
                if (id1 == i1 || id2 == i1) { deleted[k] = true; continue; }
                var d1 = Vector3.Normalize(verts[id1].P - p);
                var d2 = Vector3.Normalize(verts[id2].P - p);
                if (MathF.Abs(Vector3.Dot(d1, d2)) > 0.999f) return true;
                var n = Vector3.Normalize(Vector3.Cross(d1, d2));
                deleted[k] = false;
                if (Vector3.Dot(n, t.N) < 0.2f) return true;
            }
            return false;
        }

        void UpdateTriangles(int i0, Vert v, List<bool> deleted)
        {
            for (int k = 0; k < v.TCount; k++)
            {
                var r = refs[v.TStart + k];
                var t = tris[r.Tid];
                if (t.Deleted) continue;
                if (deleted[k]) { t.Deleted = true; deletedTris++; continue; }
                t.V[r.TVertex] = i0;
                t.Dirty = true;
                for (int j = 0; j < 3; j++) t.Err[j] = CalcError(t.V[j], t.V[(j + 1) % 3], out _, out _);
                t.Err[3] = Math.Min(t.Err[0], Math.Min(t.Err[1], t.Err[2]));
                refs.Add(r);
            }
        }

        void UpdateMesh(int iteration)
        {
            if (iteration > 0) tris.RemoveAll(t => t.Deleted);
            foreach (var v in verts) { v.TStart = 0; v.TCount = 0; }
            foreach (var t in tris) for (int j = 0; j < 3; j++) verts[t.V[j]].TCount++;
            int ts = 0;
            foreach (var v in verts) { v.TStart = ts; ts += v.TCount; v.TCount = 0; }
            refs.Clear();
            for (int i = 0; i < ts; i++) refs.Add(default);
            for (int i = 0; i < tris.Count; i++)
                for (int j = 0; j < 3; j++)
                {
                    var v = verts[tris[i].V[j]];
                    refs[v.TStart + v.TCount] = new Ref { Tid = i, TVertex = j };
                    v.TCount++;
                }
            if (iteration != 0) return;

            // open edges: an edge used by only one triangle
            var edgeUse = new Dictionary<(int, int), int>();
            foreach (var t in tris)
                for (int j = 0; j < 3; j++)
                {
                    int a = t.V[j], b = t.V[(j + 1) % 3];
                    var key = a < b ? (a, b) : (b, a);
                    edgeUse[key] = edgeUse.GetValueOrDefault(key) + 1;
                }
            foreach (var (k, n) in edgeUse)
                if (n == 1) { verts[k.Item1].Border = true; verts[k.Item2].Border = true; }

            foreach (var v in verts) v.Q = default;
            foreach (var t in tris)
            {
                var p0 = verts[t.V[0]].P;
                var n = Vector3.Cross(verts[t.V[1]].P - p0, verts[t.V[2]].P - p0);
                n = n.LengthSquared() > 1e-30f ? Vector3.Normalize(n) : Vector3.UnitZ;
                t.N = n;
                var q = new Q(n.X, n.Y, n.Z, -Vector3.Dot(n, p0));
                for (int j = 0; j < 3; j++) verts[t.V[j]].Q = verts[t.V[j]].Q + q;
            }
            foreach (var t in tris)
            {
                for (int j = 0; j < 3; j++) t.Err[j] = CalcError(t.V[j], t.V[(j + 1) % 3], out _, out _);
                t.Err[3] = Math.Min(t.Err[0], Math.Min(t.Err[1], t.Err[2]));
            }
        }

        for (int iteration = 0; iteration < 100; iteration++)
        {
            if (startCount - deletedTris <= target) break;
            if (iteration % 5 == 0) UpdateMesh(iteration);
            foreach (var t in tris) t.Dirty = false;
            double threshold = 1e-9 * Math.Pow(iteration + 3, aggressiveness);
            for (int ti = 0; ti < tris.Count; ti++)
            {
                var t = tris[ti];
                if (t.Err[3] > threshold || t.Deleted || t.Dirty) continue;
                for (int j = 0; j < 3; j++)
                {
                    if (t.Err[j] >= threshold) continue;
                    int i0 = t.V[j], i1 = t.V[(j + 1) % 3];
                    var v0 = verts[i0]; var v1 = verts[i1];
                    if (v0.Border || v1.Border) continue;   // open edges and UV seams stay put
                    CalcError(i0, i1, out var p, out var et);
                    while (del0.Count < v0.TCount) del0.Add(false);
                    while (del1.Count < v1.TCount) del1.Add(false);
                    if (Flipped(p, i1, v0, del0)) continue;
                    if (Flipped(p, i0, v1, del1)) continue;
                    v0.Uv = Vector2.Lerp(v0.Uv, v1.Uv, (float)et);
                    var nn = Vector3.Lerp(v0.Nrm, v1.Nrm, (float)et);
                    v0.Nrm = nn.LengthSquared() > 1e-12f ? Vector3.Normalize(nn) : v0.Nrm;
                    v0.P = p;
                    v0.Q = v1.Q + v0.Q;
                    int tstart = refs.Count;
                    UpdateTriangles(i0, v0, del0);
                    UpdateTriangles(i0, v1, del1);
                    int tcount = refs.Count - tstart;
                    if (tcount <= v0.TCount)
                    {
                        for (int k = 0; k < tcount; k++) refs[v0.TStart + k] = refs[tstart + k];
                    }
                    else v0.TStart = tstart;
                    v0.TCount = tcount;
                    break;
                }
                if (startCount - deletedTris <= target) break;
            }
        }

        // compact
        var o = new Mesh { Mats = m.Mats };
        var map = new Dictionary<int, int>();
        foreach (var t in tris)
        {
            if (t.Deleted) continue;
            for (int j = 0; j < 3; j++)
            {
                if (!map.TryGetValue(t.V[j], out int nv))
                {
                    nv = o.P.Count; map[t.V[j]] = nv;
                    var v = verts[t.V[j]];
                    o.P.Add(v.P); o.N.Add(v.Nrm); o.T.Add(v.Uv);
                }
                o.I.Add(nv);
            }
            o.M.Add(t.Mat);
        }
        return o;
    }
}
