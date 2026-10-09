// hairkit: turns the freemode hairstyles a server streams (or a GTA install has) into props that sit on
// the Wig Snatch foam head. Built on CodeWalker.Core.
//
//   hairkit scan  --out <nzw_hairprops> [--roots-file f] [root ...]   what's new / changed / gone
//   hairkit build --out <nzw_hairprops> [--all] [--roots-file f] [root ...]
//   hairkit game  --out <nzw_hairprops> --gta <GTA V folder>          base game + DLC hair (needs GTA)
//
// Lines starting with '@' are JSON for the server script; everything else is a log line.

using System.Globalization;
using System.Numerics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Xml;
using CodeWalker.GameFiles;

static class P
{
    static readonly Regex HairFile = new(@"^mp_([mf])_freemode_01(?:_([^\^]+))?\^hair_(\d{3})_[a-z]\.ydd$", RegexOptions.IgnoreCase);
    static readonly Regex GameHair = new(@"^hair_(\d{3})_[a-z]\.ydd$", RegexOptions.IgnoreCase);
    static readonly Regex GameFolder = new(@"^mp_([mf])_freemode_01(?:_(.+))?$", RegexOptions.IgnoreCase);
    static readonly CultureInfo IC = CultureInfo.InvariantCulture;

    static int Main(string[] args)
    {
        try
        {
            if (args.Length == 0) return Usage();
            var cmd = args[0];
            string outDir = null, gta = null, rootsFile = null;
            bool all = false;
            int texSize = 256;
            var roots = new List<string>();
            for (int i = 1; i < args.Length; i++)
            {
                switch (args[i])
                {
                    case "--out": outDir = args[++i]; break;
                    case "--gta": gta = args[++i]; break;
                    case "--roots-file": rootsFile = args[++i]; break;
                    case "--all": all = true; break;
                    case "--tex": texSize = int.Parse(args[++i]); break;
                    default: roots.Add(args[i]); break;
                }
            }
            if (rootsFile != null) roots.AddRange(File.ReadAllLines(rootsFile).Select(l => l.Trim()).Where(l => l.Length > 0));
            if (outDir == null) return Usage();
            outDir = Path.GetFullPath(outDir);
            var map = HairMap.Load(outDir);

            switch (cmd)
            {
                case "scan":
                {
                    var found = FindServerHair(roots, outDir);
                    var diff = map.Diff(found, "server");
                    Emit("scan", diff.ToJson(found.Count, map));
                    return 0;
                }
                case "build":
                {
                    var found = FindServerHair(roots, outDir);
                    var diff = map.Diff(found, "server");
                    var todo = all ? found : diff.New.Concat(diff.Changed).ToList();
                    Build(outDir, map, todo, diff.Removed, texSize);
                    return 0;
                }
                case "game":
                {
                    if (gta == null) return Usage();
                    var found = FindGameHair(gta);
                    var diff = map.Diff(found.Select(f => f.Src).ToList(), "game");
                    var todo = all ? found : found.Where(f => diff.New.Contains(f.Src) || diff.Changed.Contains(f.Src)).ToList();
                    BuildGame(outDir, map, todo, texSize);
                    return 0;
                }
                default: return Usage();
            }
        }
        catch (Exception e)
        {
            Emit("error", new JsonObject { ["message"] = e.Message });
            Console.Error.WriteLine(e);
            return 1;
        }
    }

    static int Usage()
    {
        Console.WriteLine("hairkit scan|build|game --out <nzw_hairprops folder> [--all] [--tex 256] [--roots-file file] [--gta folder] [root ...]");
        return 2;
    }

    static void Emit(string kind, JsonNode data)
    {
        Console.WriteLine("@" + new JsonObject { ["kind"] = kind, ["data"] = data }.ToJsonString());
        Console.Out.Flush();
    }

    // finding hair ---------------------------------------------------------------------------------

    public class Src
    {
        public string Gender, Collection, Path, Ytd, Origin = "server";
        public int Local;
        public long Size, Mtime;
        public string Key => $"{Gender}|{Collection}|{Local}";
    }

    static List<Src> FindServerHair(List<string> roots, string outDir)
    {
        var ydds = new List<string>();
        var ytds = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var r in roots.Distinct())
        {
            if (!Directory.Exists(r)) continue;
            if (Path.GetFullPath(r).StartsWith(outDir, StringComparison.OrdinalIgnoreCase)) continue;
            IEnumerable<string> files;
            try { files = Directory.EnumerateFiles(r, "*", SearchOption.AllDirectories); } catch { continue; }
            foreach (var f in files)
            {
                var n = Path.GetFileName(f);
                if (n.EndsWith(".ydd", StringComparison.OrdinalIgnoreCase) && n.Contains("^hair_", StringComparison.OrdinalIgnoreCase)) ydds.Add(f);
                else if (n.EndsWith(".ytd", StringComparison.OrdinalIgnoreCase) && n.Contains("^hair_diff_", StringComparison.OrdinalIgnoreCase)) ytds.TryAdd(n, f);
            }
        }
        var outList = new Dictionary<string, Src>();
        foreach (var f in ydds)
        {
            var m = HairFile.Match(Path.GetFileName(f));
            if (!m.Success) continue;
            var fi = new FileInfo(f);
            var s = new Src
            {
                Gender = m.Groups[1].Value.ToLowerInvariant(),
                Collection = m.Groups[2].Success ? m.Groups[2].Value.ToLowerInvariant() : "",
                Local = int.Parse(m.Groups[3].Value, IC),
                Path = f, Size = fi.Length, Mtime = new DateTimeOffset(fi.LastWriteTimeUtc).ToUnixTimeSeconds(),
            };
            var prefix = Path.GetFileName(f).Substring(0, Path.GetFileName(f).IndexOf('^'));
            var want = $"{prefix}^hair_diff_{m.Groups[3].Value}_a_";
            s.Ytd = ytds.FirstOrDefault(kv => kv.Key.StartsWith(want, StringComparison.OrdinalIgnoreCase)).Value;
            outList[s.Key] = s; // a later resource overrides an earlier one, like streaming does
        }
        return outList.Values.OrderBy(s => s.Key).ToList();
    }

    class GameSrc { public Src Src; public RpfFileEntry Ydd, Ytd; }

    static RpfManager rpfMan;

    static List<GameSrc> FindGameHair(string gta)
    {
        Console.WriteLine("loading GTA keys from " + gta);
        GTA5Keys.LoadFromPath(gta, null);
        rpfMan = new RpfManager();
        rpfMan.Init(gta, s => { }, e => Console.WriteLine("rpf: " + e), false, false);
        var list = new List<GameSrc>();
        var ytds = new Dictionary<string, RpfFileEntry>(StringComparer.OrdinalIgnoreCase);
        var ydds = new List<RpfFileEntry>();
        foreach (var rpf in rpfMan.AllRpfs)
        {
            if (rpf.AllEntries == null) continue;
            foreach (var e in rpf.AllEntries)
            {
                if (e is not RpfFileEntry fe || e.Parent == null) continue;
                var folder = e.Parent.Name ?? "";
                if (!GameFolder.IsMatch(folder)) continue;
                if (GameHair.IsMatch(e.Name)) ydds.Add(fe);
                else if (e.Name.StartsWith("hair_diff_", StringComparison.OrdinalIgnoreCase) && e.Name.EndsWith(".ytd", StringComparison.OrdinalIgnoreCase))
                    ytds.TryAdd(e.Parent.Path + "/" + e.Name, fe);
            }
        }
        var byKey = new Dictionary<string, GameSrc>();
        foreach (var fe in ydds)
        {
            var fm = GameFolder.Match(fe.Parent.Name);
            var hm = GameHair.Match(fe.Name);
            var s = new Src
            {
                Origin = "game", Gender = fm.Groups[1].Value.ToLowerInvariant(),
                Collection = fm.Groups[2].Success ? fm.Groups[2].Value.ToLowerInvariant() : "",
                Local = int.Parse(hm.Groups[1].Value, IC), Path = fe.Path, Size = fe.GetFileSize(), Mtime = 0,
            };
            var want = fe.Parent.Path + "/hair_diff_" + hm.Groups[1].Value + "_a_";
            var ytd = ytds.FirstOrDefault(kv => kv.Key.StartsWith(want, StringComparison.OrdinalIgnoreCase)).Value;
            byKey[s.Key] = new GameSrc { Src = s, Ydd = fe, Ytd = ytd };
        }
        Console.WriteLine($"found {byKey.Count} hairstyles in the game files");
        return byKey.Values.OrderBy(g => g.Src.Key).ToList();
    }

    // building -------------------------------------------------------------------------------------

    static void Build(string outDir, HairMap map, List<Src> todo, List<Src> removed, int texSize)
    {
        Directory.CreateDirectory(Path.Combine(outDir, "stream"));
        int i = 0, ok = 0;
        foreach (var s in todo)
        {
            i++;
            Emit("progress", new JsonObject { ["i"] = i, ["n"] = todo.Count, ["key"] = s.Key });
            try
            {
                var ydd = new YddFile(); ydd.Load(File.ReadAllBytes(s.Path));
                YtdFile ytd = null;
                if (s.Ytd != null) { ytd = new YtdFile(); ytd.Load(File.ReadAllBytes(s.Ytd)); }
                if (Convert(outDir, map, s, ydd, ytd, texSize)) ok++;
            }
            catch (Exception e) { Console.WriteLine($"skip {s.Key}: {e.Message}"); }
        }
        foreach (var s in removed) map.Remove(outDir, s.Key);
        Finish(outDir, map, ok, todo.Count, removed.Count);
    }

    static void BuildGame(string outDir, HairMap map, List<GameSrc> todo, int texSize)
    {
        Directory.CreateDirectory(Path.Combine(outDir, "stream"));
        int i = 0, ok = 0;
        foreach (var g in todo)
        {
            i++;
            Emit("progress", new JsonObject { ["i"] = i, ["n"] = todo.Count, ["key"] = g.Src.Key });
            try
            {
                var ydd = rpfMan.GetFile<YddFile>(g.Ydd);
                var ytd = g.Ytd != null ? rpfMan.GetFile<YtdFile>(g.Ytd) : null;
                if (ydd != null && Convert(outDir, map, g.Src, ydd, ytd, texSize)) ok++;
            }
            catch (Exception e) { Console.WriteLine($"skip {g.Src.Key}: {e.Message}"); }
        }
        Finish(outDir, map, ok, todo.Count, 0);
    }

    static void Finish(string outDir, HairMap map, int ok, int total, int removed)
    {
        WriteYtyp(outDir, map);
        map.Save(outDir);
        var manifest = Path.Combine(outDir, "fxmanifest.lua");
        if (!File.Exists(manifest))
        {
            File.WriteAllText(manifest, "fx_version 'cerulean'\ngame 'gta5'\n\ndescription 'Hairstyle props for nayzeee-wigsnatch (made by the Wig Studio)'\n\n" +
                "this_is_a_map 'yes'\ndata_file 'DLC_ITYP_REQUEST' 'stream/nzw_hair.ytyp'\nfiles { 'hairmap.json' }\n");
        }
        Emit("done", new JsonObject { ["built"] = ok, ["tried"] = total, ["removed"] = removed, ["props"] = map.Entries.Count });
    }

    static string PropName(Src s)
    {
        var coll = s.Collection == "" ? "base" : JenkHash.GenHash(s.Collection).ToString("x8");
        return $"nzw_{s.Gender}_{coll}_{s.Local}";
    }

    // the conversion -------------------------------------------------------------------------------

    static readonly Dictionary<string, int> Sizes = new()
    {
        ["Position"] = 3, ["BlendWeights"] = 4, ["BlendIndices"] = 4, ["Normal"] = 3, ["Colour0"] = 4, ["Colour1"] = 4, ["Tangent"] = 4,
        ["TexCoord0"] = 2, ["TexCoord1"] = 2, ["TexCoord2"] = 2, ["TexCoord3"] = 2, ["TexCoord4"] = 2, ["TexCoord5"] = 2, ["TexCoord6"] = 2, ["TexCoord7"] = 2,
    };

    class Geo { public List<Vector3> P = new(), N = new(); public List<Vector2> UV = new(); public List<int> I = new(); }

    static bool Convert(string outDir, HairMap map, Src s, YddFile ydd, YtdFile ytd, int texSize)
    {
        var name = PropName(s);
        var tmp = Path.Combine(Path.GetTempPath(), "hairkit_" + Guid.NewGuid().ToString("n"));
        Directory.CreateDirectory(tmp);
        try
        {
            var xml = YddXml.GetXml(ydd, tmp);
            int hi0 = xml.IndexOf("<DrawableModelsHigh>", StringComparison.Ordinal);
            if (hi0 < 0) { Console.WriteLine($"skip {s.Key}: no high detail model"); return false; }
            int hi1 = xml.IndexOf("</DrawableModelsHigh>", hi0, StringComparison.Ordinal);
            var geos = ParseGeometries(xml.Substring(hi0, hi1 - hi0));
            if (geos.Count == 0 || geos.All(g => g.P.Count == 0)) { Console.WriteLine($"skip {s.Key}: empty"); return false; }
            var head = HeadBone(xml, geos, s.Gender);
            foreach (var g in geos) for (int k = 0; k < g.P.Count; k++) g.P[k] -= head;

            // texture: the hair's diffuse from its .ytd, else a diffuse embedded in the .ydd
            var tex = PickDiffuse(ytd, ydd);
            if (tex == null) { Console.WriteLine($"skip {s.Key}: no diffuse texture"); return false; }
            var (rgba, w, h) = Pixels(tex);
            int tw = Pow2(w, texSize), th = Pow2(h, texSize);
            rgba = Resize(rgba, w, h, tw, th);
            bool alpha = UsesAlpha(rgba);
            TintIfGrey(rgba);
            var texName = name + "_d";
            int mips = Dxt.WriteDds(Path.Combine(tmp, texName + ".dds"), rgba, tw, th);

            // see-through hair cards: cutout shader, and the back faces too
            var outGeos = new List<Geo>();
            foreach (var g in geos)
            {
                if (alpha)
                {
                    int n = g.P.Count;
                    var dbl = new Geo();
                    dbl.P.AddRange(g.P); dbl.N.AddRange(g.N); dbl.UV.AddRange(g.UV); dbl.I.AddRange(g.I);
                    dbl.P.AddRange(g.P); dbl.N.AddRange(g.N.Select(v => -v)); dbl.UV.AddRange(g.UV);
                    for (int k = 0; k < g.I.Count; k += 3) { dbl.I.Add(g.I[k] + n); dbl.I.Add(g.I[k + 2] + n); dbl.I.Add(g.I[k + 1] + n); }
                    outGeos.AddRange(Split(dbl));
                }
                else outGeos.AddRange(Split(g));
            }

            var ydrXml = YdrXml(name, outGeos, texName, tw, th, mips, alpha ? "cutout" : "default", alpha ? 3 : 0);
            var ydr = XmlYdr.GetYdr(ydrXml, tmp);
            var data = ydr.Save();
            var back = new YdrFile(); back.Load(data);  // must load back
            if (back.Drawable == null) throw new Exception("compiled prop did not load back");
            File.WriteAllBytes(Path.Combine(outDir, "stream", name + ".ydr"), data);

            var all = outGeos.SelectMany(g => g.P).ToList();
            var mn = all.Aggregate(Vector3.Min); var mx = all.Aggregate(Vector3.Max);
            map.Set(s, name, mn, mx, outGeos.Sum(g => g.I.Count / 3), alpha);
            Console.WriteLine($"ok {s.Key} -> {name} ({all.Count} verts, {data.Length / 1024} KB{(alpha ? ", cutout" : "")})");
            return true;
        }
        finally { try { Directory.Delete(tmp, true); } catch { } }
    }

    static float F(string v) => float.Parse(v, NumberStyles.Float, IC);

    static List<Geo> ParseGeometries(string hi)
    {
        var list = new List<Geo>();
        var rx = new Regex(@"<VertexBuffer>(.*?)</VertexBuffer>\s*<IndexBuffer>\s*<Data>(.*?)</Data>", RegexOptions.Singleline);
        foreach (Match m in rx.Matches(hi))
        {
            var vb = m.Groups[1].Value;
            int l0 = vb.IndexOf("<Layout", StringComparison.Ordinal), l1 = vb.IndexOf("</Layout>", StringComparison.Ordinal);
            var sems = Regex.Matches(vb.Substring(l0, l1 - l0), @"<(\w+) />").Select(x => x.Groups[1].Value).ToList();
            var off = new Dictionary<string, int>(); int cols = 0;
            foreach (var sem in sems) { off[sem] = cols; cols += Sizes.TryGetValue(sem, out var z) ? z : 0; }
            var data = Regex.Match(vb, @"<Data>(.*?)</Data>", RegexOptions.Singleline).Groups[1].Value;
            var g = new Geo();
            foreach (var line in data.Split('\n'))
            {
                var t = line.Split((char[])null, StringSplitOptions.RemoveEmptyEntries);
                if (t.Length < cols) continue;
                int p = off["Position"];
                g.P.Add(new Vector3(F(t[p]), F(t[p + 1]), F(t[p + 2])));
                if (off.TryGetValue("Normal", out var n)) g.N.Add(Vector3.Normalize(new Vector3(F(t[n]), F(t[n + 1]), F(t[n + 2])) + new Vector3(0, 0, 1e-6f)));
                else g.N.Add(Vector3.UnitZ);
                if (off.TryGetValue("TexCoord0", out var u)) g.UV.Add(new Vector2(F(t[u]), F(t[u + 1]))); else g.UV.Add(Vector2.Zero);
            }
            foreach (var v in m.Groups[2].Value.Split((char[])null, StringSplitOptions.RemoveEmptyEntries)) g.I.Add(int.Parse(v, IC));
            list.Add(g);
        }
        return list;
    }

    // SKEL_Head in model space from the drawable's skeleton; without one, estimated from the hair's top
    static Vector3 HeadBone(string xml, List<Geo> geos, string gender)
    {
        int s0 = xml.IndexOf("<Skeleton>", StringComparison.Ordinal);
        if (s0 >= 0)
        {
            var sk = xml.Substring(s0, xml.IndexOf("</Skeleton>", s0, StringComparison.Ordinal) - s0);
            var bones = new Dictionary<int, (string name, int par, Vector3 t, Quaternion q)>();
            foreach (Match m in Regex.Matches(sk, @"<Item>\s*<Name>(.*?)</Name>(.*?)</Item>", RegexOptions.Singleline))
            {
                string body = m.Groups[2].Value;
                Dictionary<string, string> A(string tag)
                {
                    var mm = Regex.Match(body, "<" + tag + " ([^/]*)/>");
                    return mm.Success ? Regex.Matches(mm.Groups[1].Value, "(\\w+)=\"([^\"]*)\"").ToDictionary(x => x.Groups[1].Value, x => x.Groups[2].Value) : new();
                }
                var idx = A("Index"); var par = A("ParentIndex"); var tr = A("Translation"); var ro = A("Rotation");
                if (!idx.ContainsKey("value")) continue;
                float G(Dictionary<string, string> d, string k) => d.TryGetValue(k, out var v) ? F(v) : 0f;
                var q = ro.Count > 0 ? new Quaternion(G(ro, "x"), G(ro, "y"), G(ro, "z"), G(ro, "w")) : Quaternion.Identity;
                bones[int.Parse(idx["value"], IC)] = (m.Groups[1].Value, par.ContainsKey("value") ? int.Parse(par["value"], IC) : -1,
                    new Vector3(G(tr, "x"), G(tr, "y"), G(tr, "z")), Quaternion.Normalize(q));
            }
            var cache = new Dictionary<int, (Quaternion r, Vector3 t)>();
            (Quaternion r, Vector3 t) World(int i)
            {
                if (cache.TryGetValue(i, out var c)) return c;
                var b = bones[i];
                (Quaternion, Vector3) res = b.par < 0 || !bones.ContainsKey(b.par) ? (b.q, b.t)
                    : (Quaternion.Normalize(World(b.par).r * b.q), Vector3.Transform(b.t, World(b.par).r) + World(b.par).t);
                cache[i] = res;
                return res;
            }
            foreach (var kv in bones) if (kv.Value.name == "SKEL_Head") return World(kv.Key).t;
        }
        float top = geos.SelectMany(g => g.P).Max(p => p.Z);
        return new Vector3(0f, 0.003f, top - 0.185f);
    }

    static CodeWalker.GameFiles.Texture PickDiffuse(YtdFile ytd, YddFile ydd)
    {
        bool Ok(CodeWalker.GameFiles.Texture t) => t != null && !Regex.IsMatch(t.Name ?? "", "normal|spec|_n$|_s$", RegexOptions.IgnoreCase);
        var a = ytd?.TextureDict?.Textures?.data_items?.FirstOrDefault(Ok);
        if (a != null) return a;
        foreach (var d in ydd.Drawables ?? Array.Empty<Drawable>())
        {
            var t = d.ShaderGroup?.TextureDictionary?.Textures?.data_items?.FirstOrDefault(Ok);
            if (t != null) return t;
        }
        return null;
    }

    static (byte[] rgba, int w, int h) Pixels(CodeWalker.GameFiles.Texture t)
    {
        var bgra = CodeWalker.Utils.DDSIO.GetPixels(t, 0);
        var rgba = new byte[t.Width * t.Height * 4];
        for (int i = 0; i < rgba.Length; i += 4) { rgba[i] = bgra[i + 2]; rgba[i + 1] = bgra[i + 1]; rgba[i + 2] = bgra[i]; rgba[i + 3] = bgra[i + 3]; }
        return (rgba, t.Width, t.Height);
    }

    // nearest power of two, 32 .. max
    static int Pow2(int v, int max) => Math.Clamp(1 << (int)Math.Round(Math.Log2(Math.Max(4, v))), 32, max);

    static byte[] Resize(byte[] src, int w, int h, int nw, int nh)
    {
        if (w == nw && h == nh) return src;
        var dst = new byte[nw * nh * 4];
        for (int y = 0; y < nh; y++)
        {
            float sy = Math.Clamp((y + 0.5f) * h / nh - 0.5f, 0, h - 1);
            int y0 = (int)sy, y1 = Math.Min(h - 1, y0 + 1); float fy = sy - y0;
            for (int x = 0; x < nw; x++)
            {
                float sx = Math.Clamp((x + 0.5f) * w / nw - 0.5f, 0, w - 1);
                int x0 = (int)sx, x1 = Math.Min(w - 1, x0 + 1); float fx = sx - x0;
                for (int c = 0; c < 4; c++)
                {
                    float a = src[(y0 * w + x0) * 4 + c] * (1 - fx) + src[(y0 * w + x1) * 4 + c] * fx;
                    float b = src[(y1 * w + x0) * 4 + c] * (1 - fx) + src[(y1 * w + x1) * 4 + c] * fx;
                    dst[(y * nw + x) * 4 + c] = (byte)Math.Clamp(a * (1 - fy) + b * fy + 0.5f, 0, 255);
                }
            }
        }
        return dst;
    }

    static bool UsesAlpha(byte[] rgba)
    {
        int low = 0, n = rgba.Length / 4;
        for (int i = 3; i < rgba.Length; i += 4) if (rgba[i] < 200) low++;
        return low > n * 0.04;
    }

    // GTA tints freemode hair in the shader; a prop can't, so grey hair textures get a natural dark brown
    static readonly Vector3 Tint = new(0.42f, 0.30f, 0.22f);
    static void TintIfGrey(byte[] rgba)
    {
        double sat = 0; int n = 0;
        for (int i = 0; i < rgba.Length; i += 4)
        {
            if (rgba[i + 3] < 128) continue;
            int mx = Math.Max(rgba[i], Math.Max(rgba[i + 1], rgba[i + 2])), mn = Math.Min(rgba[i], Math.Min(rgba[i + 1], rgba[i + 2]));
            sat += mx == 0 ? 0 : (mx - mn) / (double)mx; n++;
        }
        if (n == 0 || sat / n > 0.12) return;
        for (int i = 0; i < rgba.Length; i += 4)
        {
            float l = (rgba[i] + rgba[i + 1] + rgba[i + 2]) / 765f;
            rgba[i] = (byte)Math.Clamp(l * Tint.X * 255 * 1.5f, 0, 255);
            rgba[i + 1] = (byte)Math.Clamp(l * Tint.Y * 255 * 1.5f, 0, 255);
            rgba[i + 2] = (byte)Math.Clamp(l * Tint.Z * 255 * 1.5f, 0, 255);
        }
    }

    static IEnumerable<Geo> Split(Geo g)
    {
        if (g.P.Count <= 65000) { yield return g; yield break; }
        var cur = new Geo(); var remap = new Dictionary<int, int>();
        for (int k = 0; k < g.I.Count; k += 3)
        {
            if (cur.P.Count > 64990) { yield return cur; cur = new Geo(); remap.Clear(); }
            for (int j = 0; j < 3; j++)
            {
                int v = g.I[k + j];
                if (!remap.TryGetValue(v, out var nv)) { nv = cur.P.Count; remap[v] = nv; cur.P.Add(g.P[v]); cur.N.Add(g.N[v]); cur.UV.Add(g.UV[v]); }
                cur.I.Add(nv);
            }
        }
        if (cur.I.Count > 0) yield return cur;
    }

    static string N(float v)
    {
        var s = v.ToString("0.######", IC);
        return s == "-0" ? "0" : s;
    }
    static string V3(string tag, Vector3 v, bool w = false) => $"<{tag} x=\"{N(v.X)}\" y=\"{N(v.Y)}\" z=\"{N(v.Z)}\"{(w ? " w=\"0\"" : "")} />";

    static string YdrXml(string name, List<Geo> geos, string tex, int tw, int th, int mips, string shader, int bucket)
    {
        var all = geos.SelectMany(g => g.P).ToList();
        var mn = all.Aggregate(Vector3.Min); var mx = all.Aggregate(Vector3.Max);
        var c = (mn + mx) / 2; float r = all.Max(p => Vector3.Distance(p, c));
        var sb = new StringBuilder();
        sb.Append($"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Drawable>\n <Name>{name}</Name>\n {V3("BoundingSphereCenter", c)}\n <BoundingSphereRadius value=\"{N(r)}\" />\n");
        sb.Append($" {V3("BoundingBoxMin", mn)}\n {V3("BoundingBoxMax", mx)}\n");
        sb.Append(" <LodDistHigh value=\"9998\" />\n <LodDistMed value=\"9998\" />\n <LodDistLow value=\"9998\" />\n <LodDistVlow value=\"9998\" />\n");
        sb.Append(" <FlagsHigh value=\"1\" />\n <FlagsMed value=\"0\" />\n <FlagsLow value=\"0\" />\n <FlagsVlow value=\"0\" />\n");
        sb.Append($" <ShaderGroup>\n  <TextureDictionary>\n   <Item>\n    <Name>{tex}</Name>\n    <Unk32 value=\"128\" />\n    <Usage>DIFFUSE</Usage>\n    <UsageFlags>UNK24</UsageFlags>\n    <ExtraFlags value=\"0\" />\n");
        sb.Append($"    <Width value=\"{tw}\" />\n    <Height value=\"{th}\" />\n    <MipLevels value=\"{mips}\" />\n    <Format>D3DFMT_DXT5</Format>\n    <FileName>{tex}.dds</FileName>\n   </Item>\n  </TextureDictionary>\n");
        sb.Append($"  <Shaders>\n   <Item>\n    <Name>{shader}</Name>\n    <FileName>{shader}.sps</FileName>\n    <RenderBucket value=\"{bucket}\" />\n    <Parameters>\n");
        sb.Append($"     <Item name=\"DiffuseSampler\" type=\"Texture\">\n      <Name>{tex}</Name>\n     </Item>\n");
        sb.Append("     <Item name=\"matMaterialColorScale\" type=\"Vector\" x=\"1\" y=\"0\" z=\"0\" w=\"1\" />\n     <Item name=\"HardAlphaBlend\" type=\"Vector\" x=\"1\" y=\"0\" z=\"0\" w=\"0\" />\n");
        sb.Append("     <Item name=\"useTessellation\" type=\"Vector\" x=\"0\" y=\"0\" z=\"0\" w=\"0\" />\n     <Item name=\"wetnessMultiplier\" type=\"Vector\" x=\"1\" y=\"0\" z=\"0\" w=\"0\" />\n");
        sb.Append("     <Item name=\"globalAnimUV0\" type=\"Vector\" x=\"1\" y=\"0\" z=\"0\" w=\"0\" />\n     <Item name=\"globalAnimUV1\" type=\"Vector\" x=\"0\" y=\"1\" z=\"0\" w=\"0\" />\n");
        sb.Append("    </Parameters>\n   </Item>\n  </Shaders>\n </ShaderGroup>\n <DrawableModelsHigh>\n  <Item>\n   <RenderMask value=\"255\" />\n   <Flags value=\"0\" />\n   <HasSkin value=\"0\" />\n   <BoneIndex value=\"0\" />\n   <Unknown1 value=\"0\" />\n   <Geometries>\n");
        foreach (var g in geos)
        {
            var gmn = g.P.Aggregate(Vector3.Min); var gmx = g.P.Aggregate(Vector3.Max);
            sb.Append($"    <Item>\n     <ShaderIndex value=\"0\" />\n     {V3("BoundingBoxMin", gmn, true)}\n     {V3("BoundingBoxMax", gmx, true)}\n");
            sb.Append("     <VertexBuffer>\n      <Flags value=\"0\" />\n      <Layout type=\"GTAV1\">\n       <Position />\n       <Normal />\n       <Colour0 />\n       <TexCoord0 />\n      </Layout>\n      <Data>\n");
            for (int k = 0; k < g.P.Count; k++)
            {
                var p = g.P[k]; var n = g.N[k]; var uv = g.UV[k];
                sb.Append($"       {N(p.X)} {N(p.Y)} {N(p.Z)}   {N(n.X)} {N(n.Y)} {N(n.Z)}   255 255 255 255   {N(uv.X)} {N(uv.Y)}\n");
            }
            sb.Append("      </Data>\n     </VertexBuffer>\n     <IndexBuffer>\n      <Data>\n");
            for (int k = 0; k < g.I.Count; k += 24) sb.Append("       " + string.Join(' ', g.I.Skip(k).Take(24)) + "\n");
            sb.Append("      </Data>\n     </IndexBuffer>\n    </Item>\n");
        }
        sb.Append("   </Geometries>\n  </Item>\n </DrawableModelsHigh>\n <Lights />\n</Drawable>\n");
        return sb.ToString();
    }

    static void WriteYtyp(string outDir, HairMap map)
    {
        var items = new StringBuilder();
        foreach (var e in map.Entries.Values.OrderBy(e => e["prop"].GetValue<string>()))
        {
            var mn = new Vector3(e["min"][0].GetValue<float>(), e["min"][1].GetValue<float>(), e["min"][2].GetValue<float>());
            var mx = new Vector3(e["max"][0].GetValue<float>(), e["max"][1].GetValue<float>(), e["max"][2].GetValue<float>());
            var c = (mn + mx) / 2; var r = Vector3.Distance(mn, mx) / 2;
            var name = e["prop"].GetValue<string>();
            items.Append($"  <Item type=\"CBaseArchetypeDef\">\n   <lodDist value=\"40\" />\n   <flags value=\"32\" />\n   <specialAttribute value=\"0\" />\n");
            items.Append($"   <bbMin x=\"{N(mn.X)}\" y=\"{N(mn.Y)}\" z=\"{N(mn.Z)}\" />\n   <bbMax x=\"{N(mx.X)}\" y=\"{N(mx.Y)}\" z=\"{N(mx.Z)}\" />\n");
            items.Append($"   <bsCentre x=\"{N(c.X)}\" y=\"{N(c.Y)}\" z=\"{N(c.Z)}\" />\n   <bsRadius value=\"{N(r)}\" />\n   <hdTextureDist value=\"20\" />\n");
            items.Append($"   <name>{name}</name>\n   <textureDictionary />\n   <clipDictionary />\n   <drawableDictionary />\n   <physicsDictionary />\n");
            items.Append($"   <assetType>ASSET_TYPE_DRAWABLE</assetType>\n   <assetName>{name}</assetName>\n   <extensions />\n  </Item>\n");
        }
        var xml = $"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<CMapTypes>\n <extensions />\n <archetypes>\n{items}</archetypes>\n <name>nzw_hair</name>\n <dependencies />\n <compositeEntityTypes itemType=\"CCompositeEntityType\" />\n</CMapTypes>\n";
        var doc = new XmlDocument(); doc.LoadXml(xml);
        var data = XmlMeta.GetData(doc, MetaFormat.RSC, outDir);
        var back = new YtypFile(); back.Load(data);
        File.WriteAllBytes(Path.Combine(outDir, "stream", "nzw_hair.ytyp"), data);
    }

    // hairmap.json: which prop belongs to which hairstyle, and what it was made from -------------

    class HairMap
    {
        public Dictionary<string, JsonObject> Entries = new();

        public static HairMap Load(string dir)
        {
            var m = new HairMap();
            var f = Path.Combine(dir, "hairmap.json");
            if (!File.Exists(f)) return m;
            try
            {
                var root = JsonNode.Parse(File.ReadAllText(f))?["props"]?.AsObject();
                if (root != null) foreach (var kv in root) m.Entries[kv.Key] = kv.Value.AsObject();
            }
            catch { }
            return m;
        }

        public void Save(string dir)
        {
            var props = new JsonObject();
            foreach (var kv in Entries.OrderBy(k => k.Key)) props[kv.Key] = JsonNode.Parse(kv.Value.ToJsonString());
            var root = new JsonObject { ["version"] = 1, ["built"] = DateTimeOffset.UtcNow.ToUnixTimeSeconds(), ["props"] = props };
            File.WriteAllText(Path.Combine(dir, "hairmap.json"), root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        }

        public void Set(Src s, string prop, Vector3 mn, Vector3 mx, int tris, bool cutout)
        {
            Entries[s.Key] = new JsonObject
            {
                ["prop"] = prop, ["m"] = s.Gender, ["collection"] = s.Collection, ["local"] = s.Local, ["origin"] = s.Origin,
                ["src"] = s.Path, ["size"] = s.Size, ["mtime"] = s.Mtime, ["tris"] = tris, ["cutout"] = cutout,
                ["min"] = new JsonArray(mn.X, mn.Y, mn.Z), ["max"] = new JsonArray(mx.X, mx.Y, mx.Z),
            };
        }

        public void Remove(string dir, string key)
        {
            if (!Entries.TryGetValue(key, out var e)) return;
            try { File.Delete(Path.Combine(dir, "stream", e["prop"].GetValue<string>() + ".ydr")); } catch { }
            Entries.Remove(key);
        }

        public class DiffResult
        {
            public List<Src> New = new(), Changed = new(), Removed = new();
            public JsonObject ToJson(int found, HairMap map) => new()
            {
                ["found"] = found, ["props"] = map.Entries.Count,
                ["new"] = new JsonArray(New.Select(s => (JsonNode)s.Key).ToArray()),
                ["changed"] = new JsonArray(Changed.Select(s => (JsonNode)s.Key).ToArray()),
                ["removed"] = new JsonArray(Removed.Select(s => (JsonNode)s.Key).ToArray()),
            };
        }

        public DiffResult Diff(List<Src> found, string origin)
        {
            var d = new DiffResult();
            var seen = new HashSet<string>();
            foreach (var s in found)
            {
                seen.Add(s.Key);
                if (!Entries.TryGetValue(s.Key, out var e)) d.New.Add(s);
                else if (e["origin"]?.GetValue<string>() == origin &&
                         (e["size"]?.GetValue<long>() != s.Size || e["mtime"]?.GetValue<long>() != s.Mtime || e["src"]?.GetValue<string>() != s.Path)) d.Changed.Add(s);
            }
            foreach (var kv in Entries)
                if (!seen.Contains(kv.Key) && kv.Value["origin"]?.GetValue<string>() == origin)
                    d.Removed.Add(new Src { Gender = kv.Value["m"].GetValue<string>(), Collection = kv.Value["collection"].GetValue<string>(), Local = kv.Value["local"].GetValue<int>() });
            return d;
        }
    }
}

// a small DXT5 (BC3) encoder with a full mip chain
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
                for (int c = 0; c < 4; c++)
                {
                    int sx = Math.Min(w - 1, x * 2), sy = Math.Min(h - 1, y * 2), sx1 = Math.Min(w - 1, sx + 1), sy1 = Math.Min(h - 1, sy + 1);
                    d[(y * nw + x) * 4 + c] = (byte)((s[(sy * w + sx) * 4 + c] + s[(sy * w + sx1) * 4 + c] + s[(sy1 * w + sx) * 4 + c] + s[(sy1 * w + sx1) * 4 + c] + 2) / 4);
                }
        return d;
    }

    static byte[] Encode(byte[] px, int w, int h)
    {
        int bw = Math.Max(1, (w + 3) / 4), bh = Math.Max(1, (h + 3) / 4);
        var out_ = new byte[bw * bh * 16];
        var blk = new int[16 * 4];
        for (int by = 0; by < bh; by++)
            for (int bx = 0; bx < bw; bx++)
            {
                for (int i = 0; i < 16; i++)
                {
                    int x = Math.Min(w - 1, bx * 4 + i % 4), y = Math.Min(h - 1, by * 4 + i / 4);
                    for (int c = 0; c < 4; c++) blk[i * 4 + c] = px[(y * w + x) * 4 + c];
                }
                int o = (by * bw + bx) * 16;
                // alpha: 8 levels between min and max
                int amin = 255, amax = 0;
                for (int i = 0; i < 16; i++) { amin = Math.Min(amin, blk[i * 4 + 3]); amax = Math.Max(amax, blk[i * 4 + 3]); }
                out_[o] = (byte)amax; out_[o + 1] = (byte)amin;
                ulong abits = 0;
                for (int i = 0; i < 16; i++)
                {
                    int a = blk[i * 4 + 3], code;
                    if (amax == amin) code = 0;
                    else
                    {
                        int t = (int)Math.Round((amax - a) * 7.0 / (amax - amin)); // 0 = amax .. 7 = amin
                        code = t == 0 ? 0 : t == 7 ? 1 : t + 1;
                    }
                    abits |= (ulong)code << (3 * i);
                }
                for (int i = 0; i < 6; i++) out_[o + 2 + i] = (byte)(abits >> (8 * i));
                // colour: endpoints from the bounding box, 4 levels
                int[] mn = { 255, 255, 255 }, mx = { 0, 0, 0 };
                for (int i = 0; i < 16; i++) for (int c = 0; c < 3; c++) { mn[c] = Math.Min(mn[c], blk[i * 4 + c]); mx[c] = Math.Max(mx[c], blk[i * 4 + c]); }
                ushort c0 = To565(mx), c1 = To565(mn);
                if (c0 < c1) { (c0, c1) = (c1, c0); }
                var p0 = From565(c0); var p1 = From565(c1);
                var pal = new int[4][] { p0, p1, Lerp(p0, p1, 1, 3), Lerp(p0, p1, 2, 3) };
                uint cbits = 0;
                for (int i = 0; i < 16; i++)
                {
                    int best = 0, bd = int.MaxValue;
                    for (int k = 0; k < 4; k++)
                    {
                        int dr = blk[i * 4] - pal[k][0], dg = blk[i * 4 + 1] - pal[k][1], db = blk[i * 4 + 2] - pal[k][2];
                        int dd = dr * dr + dg * dg + db * db;
                        if (dd < bd) { bd = dd; best = k; }
                    }
                    if (c0 == c1) best = 0;
                    cbits |= (uint)best << (2 * i);
                }
                out_[o + 8] = (byte)c0; out_[o + 9] = (byte)(c0 >> 8); out_[o + 10] = (byte)c1; out_[o + 11] = (byte)(c1 >> 8);
                for (int i = 0; i < 4; i++) out_[o + 12 + i] = (byte)(cbits >> (8 * i));
            }
        return out_;
    }

    static ushort To565(int[] c) => (ushort)(((c[0] * 31 + 127) / 255) << 11 | ((c[1] * 63 + 127) / 255) << 5 | ((c[2] * 31 + 127) / 255));
    static int[] From565(ushort v) => new[] { ((v >> 11) & 31) * 255 / 31, ((v >> 5) & 63) * 255 / 63, (v & 31) * 255 / 31 };
    static int[] Lerp(int[] a, int[] b, int n, int d) => new[] { (a[0] * (d - n) + b[0] * n) / d, (a[1] * (d - n) + b[1] * n) / d, (a[2] * (d - n) + b[2] * n) / d };
}
