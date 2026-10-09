// chainkit: turns chain clothing (a .ydd and its texture .ytd files) into props for nayzeee-chainsnatch.
// Built on CodeWalker.Core, the same way as the Wig Snatch hairkit.
//
//   chainkit scan  --out <props> [--drop dir]... [--roots-file f] [root ...]   what's new / changed / gone
//   chainkit build --out <props> [--all] [--tex 1024] [--icons 256] [--lod 60] [--drop dir]... [--roots-file f] [root ...]
//   chainkit icons --out <props> [--icons 256]                                  redraw the preview icons only
//
// Two kinds of source:
//   --drop dir   a folder of downloaded chains, one sub folder each ("Diamond Cuban Chain/teef_000_u.ydd" plus its
//                teef_diff_000_a_*.ytd, _b_, ...). The folder name becomes the chain's label.
//   root ...     server resources: every mp_[m|f]_freemode_01[_pack]^teef_###_u.ydd (and its ^teef_diff_ files).
//                These keep their gender / pack / number, so a chain someone wears as clothing can be snatched too.
//
// Every texture letter (a, b, c ...) becomes its own prop: props can't swap textures the way clothing does.
// Lines starting with '@' are JSON for the server script; everything else is a log line.

using System.Globalization;
using System.IO.Compression;
using System.Numerics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Xml;
using CodeWalker.GameFiles;

static class P
{
    static readonly Regex ServerYdd = new(@"^mp_([mf])_freemode_01(?:_([^\^]+))?\^([a-z]+)_(\d{3})_[a-z]+\.ydd$", RegexOptions.IgnoreCase);
    static readonly Regex AnyYdd = new(@"^(?:.*\^)?([a-z]+)_(\d{3})_[a-z]+\.ydd$", RegexOptions.IgnoreCase);
    static readonly Regex DiffYtd = new(@"^(?:(.*)\^)?([a-z]+)_diff_(\d{3})_([a-z])(?:_[^.]*)?\.ytd(?:\.ytd)?$", RegexOptions.IgnoreCase);
    static readonly CultureInfo IC = CultureInfo.InvariantCulture;

    static int texMax = 1024, iconSize = 256, lodDist = 60;
    static HashSet<string> comps = new(StringComparer.OrdinalIgnoreCase) { "teef" };

    static int Main(string[] args)
    {
        try
        {
            if (args.Length == 0) return Usage();
            var cmd = args[0];
            string outDir = null, rootsFile = null;
            bool all = false;
            var roots = new List<string>();
            var drops = new List<string>();
            for (int i = 1; i < args.Length; i++)
            {
                switch (args[i])
                {
                    case "--out": outDir = args[++i]; break;
                    case "--drop": drops.Add(args[++i]); break;
                    case "--roots-file": rootsFile = args[++i]; break;
                    case "--all": all = true; break;
                    case "--tex": texMax = int.Parse(args[++i], IC); break;
                    case "--icons": iconSize = int.Parse(args[++i], IC); break;
                    case "--lod": lodDist = int.Parse(args[++i], IC); break;
                    case "--comps": comps = new(args[++i].Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries), StringComparer.OrdinalIgnoreCase); break;
                    default: roots.Add(args[i]); break;
                }
            }
            if (rootsFile != null)
            {
                foreach (var l in File.ReadAllLines(rootsFile).Select(l => l.Trim()).Where(l => l.Length > 0))
                {
                    if (l.StartsWith("drop:", StringComparison.Ordinal)) drops.Add(l.Substring(5));
                    else roots.Add(l);
                }
            }
            if (outDir == null) return Usage();
            outDir = Path.GetFullPath(outDir);
            texMax = Math.Clamp(texMax, 64, 2048);
            iconSize = Math.Clamp(iconSize, 0, 1024);
            var map = ChainMap.Load(outDir);
            map.Bind(outDir);

            switch (cmd)
            {
                case "scan":
                {
                    var found = Find(drops, roots, outDir);
                    var diff = map.Diff(found);
                    Emit("scan", diff.ToJson(found, map));
                    return 0;
                }
                case "build":
                {
                    var found = Find(drops, roots, outDir);
                    var diff = map.Diff(found);
                    var todo = all ? found : diff.New.Concat(diff.Changed).ToList();
                    Build(outDir, map, todo, diff.Removed);
                    return 0;
                }
                case "icons":
                {
                    RedrawIcons(outDir, map);
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
        Console.WriteLine("chainkit scan|build|icons --out <props folder> [--all] [--tex 1024] [--icons 256] [--lod 60] [--comps teef] [--drop folder]... [--roots-file file] [root ...]");
        return 2;
    }

    static void Emit(string kind, JsonNode data)
    {
        Console.WriteLine("@" + new JsonObject { ["kind"] = kind, ["data"] = data }.ToJsonString());
        Console.Out.Flush();
    }

    // finding chains -------------------------------------------------------------------------------

    public class Src
    {
        public string Key, Label, Gender = "u", Collection = "", Comp, Origin, Ydd, Folder;
        public int Local;
        public List<(char letter, string path)> Ytds = new();
        public string Sig;
    }

    static string Slug(string s)
    {
        var t = Regex.Replace(s.ToLowerInvariant(), "[^a-z0-9]+", "_").Trim('_');
        return t.Length == 0 ? "chain" : t;
    }

    static string FileSig(string path)
    {
        var fi = new FileInfo(path);
        return $"{fi.Length}:{new DateTimeOffset(fi.LastWriteTimeUtc).ToUnixTimeSeconds()}";
    }

    static string Pretty(string s)
    {
        s = Regex.Replace(s, "[_\\-]+", " ").Trim();
        return CultureInfo.InvariantCulture.TextInfo.ToTitleCase(s);
    }

    static List<Src> Find(List<string> drops, List<string> roots, string outDir)
    {
        var list = new Dictionary<string, Src>();

        // drop folders: whatever .ydd is in there, its textures next to it
        foreach (var drop in drops.Distinct())
        {
            if (!Directory.Exists(drop)) continue;
            var dropFull = Path.GetFullPath(drop);
            var ydds = Directory.EnumerateFiles(dropFull, "*.ydd", SearchOption.AllDirectories).OrderBy(f => f, StringComparer.OrdinalIgnoreCase).ToList();
            var perFolder = ydds.GroupBy(f => Path.GetDirectoryName(f)).ToDictionary(g => g.Key, g => g.Count());
            foreach (var f in ydds)
            {
                var dir = Path.GetDirectoryName(f);
                var rel = Path.GetRelativePath(dropFull, dir);
                var name = Path.GetFileName(f);
                var m = AnyYdd.Match(name);
                var comp = m.Success ? m.Groups[1].Value.ToLowerInvariant() : "x";
                var num = m.Success ? int.Parse(m.Groups[2].Value, IC) : 0;
                var folderName = rel == "." ? Path.GetFileNameWithoutExtension(name) : Path.GetFileName(dir);
                var s = new Src
                {
                    Origin = "drop", Comp = comp, Local = num, Ydd = f, Folder = rel,
                    Key = $"drop|{Slug(rel == "." ? Path.GetFileNameWithoutExtension(name) : rel)}|{comp}_{num:000}",
                    Label = perFolder[dir] > 1 || rel == "." ? $"{Pretty(folderName)} {num}" : folderName.Trim(),
                };
                var ytds = Directory.EnumerateFiles(dir, "*", SearchOption.TopDirectoryOnly)
                    .Where(p => p.EndsWith(".ytd", StringComparison.OrdinalIgnoreCase)).ToList();
                foreach (var y in ytds)
                {
                    var ym = DiffYtd.Match(Path.GetFileName(y));
                    if (!ym.Success) continue;
                    if (m.Success && (!ym.Groups[2].Value.Equals(comp, StringComparison.OrdinalIgnoreCase) || int.Parse(ym.Groups[3].Value, IC) != num)) continue;
                    var letter = char.ToLowerInvariant(ym.Groups[4].Value[0]);
                    if (s.Ytds.All(t => t.letter != letter)) s.Ytds.Add((letter, y));
                }
                // a ydd with an odd name: take every texture file in its folder, in name order
                if (!m.Success && s.Ytds.Count == 0)
                {
                    char c = 'a';
                    foreach (var y in ytds.OrderBy(p => p, StringComparer.OrdinalIgnoreCase)) s.Ytds.Add((c++, y));
                }
                s.Ytds.Sort((a, b) => a.letter.CompareTo(b.letter));
                s.Sig = FileSig(f) + ";" + string.Join(";", s.Ytds.Select(t => t.letter + "=" + FileSig(t.path)));
                list[s.Key] = s;
            }
        }

        // server resources: freemode clothing files
        var sydds = new List<string>();
        var sytds = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        foreach (var r in roots.Distinct())
        {
            if (!Directory.Exists(r)) continue;
            if (Path.GetFullPath(r).StartsWith(outDir, StringComparison.OrdinalIgnoreCase)) continue;
            IEnumerable<string> files;
            try { files = Directory.EnumerateFiles(r, "*", SearchOption.AllDirectories); } catch { continue; }
            foreach (var f in files)
            {
                var n = Path.GetFileName(f);
                if (!n.Contains('^')) continue;
                if (n.EndsWith(".ydd", StringComparison.OrdinalIgnoreCase)) sydds.Add(f);
                else if (n.EndsWith(".ytd", StringComparison.OrdinalIgnoreCase))
                {
                    var prefix = n.Substring(0, n.IndexOf('^'));
                    if (!sytds.TryGetValue(prefix, out var l)) sytds[prefix] = l = new List<string>();
                    l.Add(f);
                }
            }
        }
        foreach (var f in sydds)
        {
            var n = Path.GetFileName(f);
            var m = ServerYdd.Match(n);
            if (!m.Success || !comps.Contains(m.Groups[3].Value)) continue;
            var prefix = n.Substring(0, n.IndexOf('^'));
            var s = new Src
            {
                Origin = "server", Gender = m.Groups[1].Value.ToLowerInvariant(),
                Collection = m.Groups[2].Success ? m.Groups[2].Value.ToLowerInvariant() : "",
                Comp = m.Groups[3].Value.ToLowerInvariant(), Local = int.Parse(m.Groups[4].Value, IC), Ydd = f,
            };
            s.Key = $"{s.Gender}|{s.Collection}|{s.Local}";
            s.Label = $"{(s.Collection == "" ? "Chain" : Pretty(s.Collection))} {s.Local}";
            foreach (var y in sytds.TryGetValue(prefix, out var l) ? l : new List<string>())
            {
                var ym = DiffYtd.Match(Path.GetFileName(y));
                if (!ym.Success || !ym.Groups[2].Value.Equals(s.Comp, StringComparison.OrdinalIgnoreCase) || int.Parse(ym.Groups[3].Value, IC) != s.Local) continue;
                var letter = char.ToLowerInvariant(ym.Groups[4].Value[0]);
                if (s.Ytds.All(t => t.letter != letter)) s.Ytds.Add((letter, y));
            }
            s.Ytds.Sort((a, b) => a.letter.CompareTo(b.letter));
            s.Sig = FileSig(f) + ";" + string.Join(";", s.Ytds.Select(t => t.letter + "=" + FileSig(t.path)));
            list[s.Key] = s; // a later resource overrides an earlier one, like streaming does
        }
        return list.Values.OrderBy(s => s.Key, StringComparer.Ordinal).ToList();
    }

    static string PropId(Src s)
    {
        if (s.Origin == "server")
        {
            var coll = s.Collection == "" ? "base" : JenkHash.GenHash(s.Collection).ToString("x8");
            return $"nzc_{s.Gender}{coll}_{s.Local}";
        }
        return $"nzc_d{JenkHash.GenHash(s.Key):x8}";
    }

    // building -------------------------------------------------------------------------------------

    static void Build(string outDir, ChainMap map, List<Src> todo, List<string> removed)
    {
        Directory.CreateDirectory(Path.Combine(outDir, "stream"));
        int i = 0, ok = 0;
        foreach (var s in todo)
        {
            i++;
            Emit("progress", new JsonObject { ["i"] = i, ["n"] = todo.Count, ["key"] = s.Key, ["label"] = s.Label });
            try
            {
                if (Convert(outDir, map, s)) ok++;
            }
            catch (Exception e) { Console.WriteLine($"skip {s.Key}: {e.Message}"); }
        }
        foreach (var k in removed) map.Remove(outDir, k);
        WriteYtyp(outDir, map);
        map.Save(outDir);
        var manifest = Path.Combine(outDir, "fxmanifest.lua");
        if (!File.Exists(manifest))
        {
            File.WriteAllText(manifest, "fx_version 'cerulean'\ngame 'gta5'\n\ndescription 'Chain props for nayzeee-chainsnatch (made by chainkit, do not edit)'\n\n" +
                "this_is_a_map 'yes'\ndata_file 'DLC_ITYP_REQUEST' 'stream/nzc_chains.ytyp'\nfiles { 'chainmap.json', 'icons/*.png' }\n");
        }
        Emit("done", new JsonObject { ["built"] = ok, ["tried"] = todo.Count, ["removed"] = removed.Count, ["chains"] = map.Entries.Count });
    }

    // drawable parsing -------------------------------------------------------------------------------

    static readonly Dictionary<string, int> Sizes = new()
    {
        ["Position"] = 3, ["BlendWeights"] = 4, ["BlendIndices"] = 4, ["Normal"] = 3, ["Colour0"] = 4, ["Colour1"] = 4, ["Tangent"] = 4,
        ["TexCoord0"] = 2, ["TexCoord1"] = 2, ["TexCoord2"] = 2, ["TexCoord3"] = 2, ["TexCoord4"] = 2, ["TexCoord5"] = 2, ["TexCoord6"] = 2, ["TexCoord7"] = 2,
    };

    public class Geo
    {
        public int Shader;
        public List<Vector3> P = new(), N = new();
        public List<Vector2> UV = new();
        public List<Vector4> T = new();
        public List<int> I = new();
        public bool HasTangent;
    }

    public class SrcShader
    {
        public string Diffuse, Bump, Spec;
        public float SpecInt = 0.6f, Falloff = 60f, Fresnel = 0.95f, Bumpiness = 1f;
        public Vector3 SpecMask = new(1, 0, 0);
    }

    static float F(string v) => float.Parse(v, NumberStyles.Float, IC);

    // the first drawable of the dictionary, as XML
    static string FirstItem(string xml)
    {
        int a = xml.IndexOf("\n <Item>", StringComparison.Ordinal);
        if (a < 0) return xml;
        int b = xml.IndexOf("\n <Item>", a + 8, StringComparison.Ordinal);
        if (b < 0) b = xml.Length;
        return xml.Substring(a, b - a);
    }

    static List<SrcShader> ParseShaders(string item)
    {
        var list = new List<SrcShader>();
        int s0 = item.IndexOf("<Shaders>", StringComparison.Ordinal), s1 = item.IndexOf("</Shaders>", StringComparison.Ordinal);
        if (s0 < 0 || s1 < 0) return list;
        var block = item.Substring(s0, s1 - s0);
        foreach (Match m in Regex.Matches(block, @"<Parameters>(.*?)</Parameters>", RegexOptions.Singleline))
        {
            var p = m.Groups[1].Value;
            var sh = new SrcShader();
            string Tex(string n)
            {
                var t = Regex.Match(p, $"<Item name=\"{n}\" type=\"Texture\">\\s*<Name>(.*?)</Name>", RegexOptions.Singleline);
                return t.Success ? t.Groups[1].Value.Trim() : null;
            }
            Vector3? Vec(string n)
            {
                var t = Regex.Match(p, $"<Item name=\"{n}\" type=\"Vector\" x=\"([^\"]*)\" y=\"([^\"]*)\" z=\"([^\"]*)\"");
                return t.Success ? new Vector3(F(t.Groups[1].Value), F(t.Groups[2].Value), F(t.Groups[3].Value)) : null;
            }
            sh.Diffuse = Tex("DiffuseSampler");
            sh.Bump = Tex("BumpSampler");
            sh.Spec = Tex("SpecSampler");
            if (Vec("specularIntensityMult") is Vector3 si) sh.SpecInt = si.X;
            if (Vec("specularFalloffMult") is Vector3 sf) sh.Falloff = sf.X;
            if (Vec("specularFresnel") is Vector3 fr) sh.Fresnel = fr.X;
            if (Vec("bumpiness") is Vector3 bu) sh.Bumpiness = bu.X;
            if (Vec("specMapIntMask") is Vector3 mk) sh.SpecMask = mk;
            list.Add(sh);
        }
        return list;
    }

    static List<Geo> ParseGeometries(string item)
    {
        var list = new List<Geo>();
        int h0 = item.IndexOf("<DrawableModelsHigh>", StringComparison.Ordinal);
        if (h0 < 0) return list;
        int h1 = item.IndexOf("</DrawableModelsHigh>", h0, StringComparison.Ordinal);
        var hi = item.Substring(h0, h1 - h0);
        var rx = new Regex(@"<ShaderIndex value=""(\d+)"" />.*?<VertexBuffer>(.*?)</VertexBuffer>\s*<IndexBuffer>\s*<Data>(.*?)</Data>", RegexOptions.Singleline);
        foreach (Match m in rx.Matches(hi))
        {
            var vb = m.Groups[2].Value;
            int l0 = vb.IndexOf("<Layout", StringComparison.Ordinal), l1 = vb.IndexOf("</Layout>", StringComparison.Ordinal);
            var sems = Regex.Matches(vb.Substring(l0, l1 - l0), @"<(\w+) />").Select(x => x.Groups[1].Value).ToList();
            var off = new Dictionary<string, int>(); int cols = 0;
            foreach (var sem in sems) { off[sem] = cols; cols += Sizes.TryGetValue(sem, out var z) ? z : 0; }
            var data = Regex.Match(vb, @"<Data2?>(.*?)</Data2?>", RegexOptions.Singleline).Groups[1].Value;
            var g = new Geo { Shader = int.Parse(m.Groups[1].Value, IC), HasTangent = off.ContainsKey("Tangent") };
            foreach (var line in data.Split('\n'))
            {
                var t = line.Split((char[])null, StringSplitOptions.RemoveEmptyEntries);
                if (t.Length < cols || cols == 0) continue;
                int p = off["Position"];
                g.P.Add(new Vector3(F(t[p]), F(t[p + 1]), F(t[p + 2])));
                if (off.TryGetValue("Normal", out var n)) g.N.Add(SafeNormal(new Vector3(F(t[n]), F(t[n + 1]), F(t[n + 2]))));
                else g.N.Add(Vector3.UnitZ);
                if (off.TryGetValue("TexCoord0", out var u)) g.UV.Add(new Vector2(F(t[u]), F(t[u + 1]))); else g.UV.Add(Vector2.Zero);
                if (off.TryGetValue("Tangent", out var tg)) g.T.Add(new Vector4(F(t[tg]), F(t[tg + 1]), F(t[tg + 2]), F(t[tg + 3]))); else g.T.Add(new Vector4(1, 0, 0, 1));
            }
            foreach (var v in m.Groups[3].Value.Split((char[])null, StringSplitOptions.RemoveEmptyEntries)) g.I.Add(int.Parse(v, IC));
            // drop triangles that point past the vertex list (broken exports)
            var clean = new List<int>(g.I.Count);
            for (int k = 0; k + 2 < g.I.Count; k += 3)
                if (g.I[k] < g.P.Count && g.I[k + 1] < g.P.Count && g.I[k + 2] < g.P.Count) { clean.Add(g.I[k]); clean.Add(g.I[k + 1]); clean.Add(g.I[k + 2]); }
            g.I = clean;
            if (g.P.Count > 0 && g.I.Count > 0) list.Add(g);
        }
        return list;
    }

    static Vector3 SafeNormal(Vector3 v)
    {
        var l = v.Length();
        return l < 1e-6f ? Vector3.UnitZ : v / l;
    }

    // textures ---------------------------------------------------------------------------------------

    static readonly Regex NotDiffuse = new("normal|_n$|_nrm|spec|_s$|metal|rough|gloss", RegexOptions.IgnoreCase);

    static Dictionary<string, CodeWalker.GameFiles.Texture> Embedded(YddFile ydd)
    {
        var d = new Dictionary<string, CodeWalker.GameFiles.Texture>(StringComparer.OrdinalIgnoreCase);
        foreach (var dr in ydd.Drawables ?? Array.Empty<Drawable>())
            foreach (var t in dr.ShaderGroup?.TextureDictionary?.Textures?.data_items ?? Array.Empty<CodeWalker.GameFiles.Texture>())
                if (t?.Name != null) d.TryAdd(t.Name, t);
        return d;
    }

    static CodeWalker.GameFiles.Texture VariantDiffuse(string ytdPath, out Dictionary<string, CodeWalker.GameFiles.Texture> all)
    {
        all = new Dictionary<string, CodeWalker.GameFiles.Texture>(StringComparer.OrdinalIgnoreCase);
        var ytd = new YtdFile(); ytd.Load(File.ReadAllBytes(ytdPath));
        var items = ytd.TextureDict?.Textures?.data_items ?? Array.Empty<CodeWalker.GameFiles.Texture>();
        foreach (var t in items) if (t?.Name != null) all.TryAdd(t.Name, t);
        return items.FirstOrDefault(t => t != null && !NotDiffuse.IsMatch(t.Name ?? "")) ?? items.FirstOrDefault();
    }

    public class Img { public byte[] Rgba; public int W, H; }

    static Img Pixels(CodeWalker.GameFiles.Texture t, int max)
    {
        var bgra = CodeWalker.Utils.DDSIO.GetPixels(t, 0);
        var rgba = new byte[t.Width * t.Height * 4];
        for (int i = 0; i < rgba.Length; i += 4) { rgba[i] = bgra[i + 2]; rgba[i + 1] = bgra[i + 1]; rgba[i + 2] = bgra[i]; rgba[i + 3] = bgra[i + 3]; }
        int tw = Pow2(t.Width, max), th = Pow2(t.Height, max);
        return new Img { Rgba = Resize(rgba, t.Width, t.Height, tw, th), W = tw, H = th };
    }

    // nearest power of two, 16 .. max
    static int Pow2(int v, int max) => Math.Clamp(1 << (int)Math.Round(Math.Log2(Math.Max(4, v))), 16, max);

    static byte[] Resize(byte[] src, int w, int h, int nw, int nh)
    {
        if (w == nw && h == nh) return src;
        // box-filter down by powers of two first so big textures don't alias, then bilinear for the rest
        while (w >= nw * 2 && h >= nh * 2)
        {
            var half = new byte[(w / 2) * (h / 2) * 4];
            for (int y = 0; y < h / 2; y++)
                for (int x = 0; x < w / 2; x++)
                    for (int c = 0; c < 4; c++)
                        half[(y * (w / 2) + x) * 4 + c] = (byte)((src[((2 * y) * w + 2 * x) * 4 + c] + src[((2 * y) * w + 2 * x + 1) * 4 + c] +
                                                                  src[((2 * y + 1) * w + 2 * x) * 4 + c] + src[((2 * y + 1) * w + 2 * x + 1) * 4 + c] + 2) / 4);
            src = half; w /= 2; h /= 2;
        }
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
        for (int i = 3; i < rgba.Length; i += 4) if (rgba[i] < 128) low++;
        return low > n * 0.04;
    }

    static Img Opaque(Img i)
    {
        var c = (byte[])i.Rgba.Clone();
        for (int k = 3; k < c.Length; k += 4) c[k] = 255;
        return new Img { Rgba = c, W = i.W, H = i.H };
    }

    // the conversion ---------------------------------------------------------------------------------

    class OutTex { public string Name; public Img Img; public string Usage; }
    class OutShader { public string Kind, Bump, Spec; public SrcShader Src; }

    static bool Convert(string outDir, ChainMap map, Src s)
    {
        var id = PropId(s);
        var tmp = Path.Combine(Path.GetTempPath(), "chainkit_" + Guid.NewGuid().ToString("n"));
        Directory.CreateDirectory(tmp);
        try
        {
            var ydd = new YddFile(); ydd.Load(File.ReadAllBytes(s.Ydd));
            if (ydd.Drawables == null || ydd.Drawables.Length == 0) { Console.WriteLine($"skip {s.Key}: no drawable in {Path.GetFileName(s.Ydd)}"); return false; }
            var item = FirstItem(YddXml.GetXml(ydd, tmp));
            foreach (var f in Directory.GetFiles(tmp)) File.Delete(f); // the XML export also dumps textures, we write our own
            var shaders = ParseShaders(item);
            var geos = ParseGeometries(item);
            if (geos.Count == 0) { Console.WriteLine($"skip {s.Key}: no high detail mesh"); return false; }
            if (shaders.Count == 0) shaders.Add(new SrcShader());

            // pivot = centre of the mesh, so the prop turns in place and sits where you put it
            var allP = geos.SelectMany(g => g.P);
            var mn0 = allP.Aggregate(Vector3.Min); var mx0 = allP.Aggregate(Vector3.Max);
            var centre = (mn0 + mx0) / 2;
            foreach (var g in geos) for (int k = 0; k < g.P.Count; k++) g.P[k] -= centre;

            var emb = Embedded(ydd);

            // variants: one per texture letter; without any .ytd the drawable's own diffuse
            var variants = new List<(char letter, CodeWalker.GameFiles.Texture tex, string from)>();
            var extra = new Dictionary<string, CodeWalker.GameFiles.Texture>(StringComparer.OrdinalIgnoreCase);
            foreach (var (letter, path) in s.Ytds)
            {
                try
                {
                    var t = VariantDiffuse(path, out var inYtd);
                    foreach (var kv in inYtd) extra.TryAdd(kv.Key, kv.Value);
                    if (t != null) variants.Add((letter, t, Path.GetFileName(path)));
                }
                catch (Exception e) { Console.WriteLine($"  {s.Key}: could not read {Path.GetFileName(path)} ({e.Message})"); }
            }
            if (variants.Count == 0)
            {
                var own = shaders.Select(sh => sh.Diffuse).Where(n => n != null && emb.ContainsKey(n)).Select(n => emb[n]).FirstOrDefault()
                          ?? emb.Values.FirstOrDefault(t => !NotDiffuse.IsMatch(t.Name ?? ""));
                if (own == null) { Console.WriteLine($"skip {s.Key}: no texture (.ytd) found next to {Path.GetFileName(s.Ydd)}"); return false; }
                variants.Add(('a', own, "embedded"));
            }

            CodeWalker.GameFiles.Texture Lookup(string n) => n == null ? null : emb.TryGetValue(n, out var t) ? t : extra.TryGetValue(n, out var e) ? e : null;

            // shared normal + spec maps, one output shader per input shader
            var shared = new List<OutTex>();
            var outShaders = new List<OutShader>();
            var cache = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            string Add(CodeWalker.GameFiles.Texture t, string suffix, int max, string usage)
            {
                if (cache.TryGetValue(t.Name + "|" + suffix, out var have)) return have;
                var name = $"{id}_{suffix}{shared.Count}";
                shared.Add(new OutTex { Name = name, Img = Opaque(Pixels(t, max)), Usage = usage });
                cache[t.Name + "|" + suffix] = name;
                return name;
            }
            for (int si = 0; si < shaders.Count; si++)
            {
                var sh = shaders[si];
                var users = geos.Where(g => g.Shader == si).ToList();
                var bump = Lookup(sh.Bump);
                var spec = Lookup(sh.Spec);
                var o = new OutShader { Src = sh };
                if (bump != null && users.Count > 0 && users.All(g => g.HasTangent)) o.Bump = Add(bump, "n", Math.Min(texMax, 1024), "BUMP");
                if (spec != null) o.Spec = Add(spec, "s", Math.Min(texMax, 512), "SPECULAR");
                o.Kind = o.Bump != null && o.Spec != null ? "normal_spec" : o.Spec != null ? "spec" : "default";
                outShaders.Add(o);
            }
            // clamp shader indices that point nowhere
            foreach (var g in geos) if (g.Shader < 0 || g.Shader >= outShaders.Count) g.Shader = 0;

            var built = new JsonArray();
            var tris = geos.Sum(g => g.I.Count / 3);
            var verts = geos.Sum(g => g.P.Count);
            long bytes = 0;
            foreach (var (letter, tex, from) in variants)
            {
                var prop = $"{id}_{letter}";
                var diff = Pixels(tex, texMax);
                bool alpha = UsesAlpha(diff.Rgba);
                var dname = prop + "_d";
                var texs = new List<OutTex> { new() { Name = dname, Img = alpha ? diff : Opaque(diff), Usage = "DIFFUSE" } };
                texs.AddRange(shared);
                var mips = new Dictionary<string, int>();
                foreach (var t in texs) mips[t.Name] = Dxt.WriteDds(Path.Combine(tmp, t.Name + ".dds"), t.Img.Rgba, t.Img.W, t.Img.H);

                var xml = PropXml(prop, geos, outShaders, texs, mips, dname, alpha);
                var ydr = XmlYdr.GetYdr(xml, tmp);
                var data = ydr.Save();
                var back = new YdrFile(); back.Load(data);  // must load back
                if (back.Drawable == null) throw new Exception("compiled prop did not load back");
                File.WriteAllBytes(Path.Combine(outDir, "stream", prop + ".ydr"), data);
                bytes += data.Length;
                foreach (var f in Directory.GetFiles(tmp)) File.Delete(f);

                if (iconSize > 0)
                {
                    try
                    {
                        Directory.CreateDirectory(Path.Combine(outDir, "icons"));
                        var spec = shared.FirstOrDefault(t => t.Usage == "SPECULAR")?.Img;
                        Raster.Icon(Path.Combine(outDir, "icons", prop + ".png"), geos, diff, spec, outShaders.Count > 0 ? outShaders[0].Src : new SrcShader(), iconSize);
                    }
                    catch (Exception e) { Console.WriteLine($"  icon for {prop} failed: {e.Message}"); }
                }
                built.Add(new JsonObject { ["letter"] = letter.ToString(), ["prop"] = prop, ["from"] = from, ["alpha"] = alpha });
            }

            var all = geos.SelectMany(g => g.P).ToList();
            var mn = all.Aggregate(Vector3.Min); var mx = all.Aggregate(Vector3.Max);
            map.Set(s, id, built, centre, mn, mx, tris, verts, outShaders.Select(o => o.Kind).Distinct().ToArray());
            Console.WriteLine($"ok {s.Key} -> {id} x{variants.Count} ({verts} verts, {tris} tris, {bytes / 1024} KB, {string.Join("/", outShaders.Select(o => o.Kind))})");
            return true;
        }
        finally { try { Directory.Delete(tmp, true); } catch { } }
    }

    static string N(float v)
    {
        var s = v.ToString("0.######", IC);
        return s == "-0" ? "0" : s;
    }
    static string V3(string tag, Vector3 v, bool w = false) => $"<{tag} x=\"{N(v.X)}\" y=\"{N(v.Y)}\" z=\"{N(v.Z)}\"{(w ? " w=\"0\"" : "")} />";
    static string Vec(string name, float x, float y = 0, float z = 0, float w = 0) =>
        $"     <Item name=\"{name}\" type=\"Vector\" x=\"{N(x)}\" y=\"{N(y)}\" z=\"{N(z)}\" w=\"{N(w)}\" />\n";
    static string TexP(string name, string tex) => $"     <Item name=\"{name}\" type=\"Texture\">\n      <Name>{tex}</Name>\n     </Item>\n";

    static IEnumerable<Geo> Split(Geo g)
    {
        if (g.P.Count <= 65000) { yield return g; yield break; }
        var cur = new Geo { Shader = g.Shader, HasTangent = g.HasTangent }; var remap = new Dictionary<int, int>();
        for (int k = 0; k < g.I.Count; k += 3)
        {
            if (cur.P.Count > 64990) { yield return cur; cur = new Geo { Shader = g.Shader, HasTangent = g.HasTangent }; remap.Clear(); }
            for (int j = 0; j < 3; j++)
            {
                int v = g.I[k + j];
                if (!remap.TryGetValue(v, out var nv)) { nv = cur.P.Count; remap[v] = nv; cur.P.Add(g.P[v]); cur.N.Add(g.N[v]); cur.UV.Add(g.UV[v]); cur.T.Add(g.T[v]); }
                cur.I.Add(nv);
            }
        }
        if (cur.I.Count > 0) yield return cur;
    }

    static string PropXml(string name, List<Geo> geos, List<OutShader> shaders, List<OutTex> texs, Dictionary<string, int> mips, string diffuse, bool alpha)
    {
        var all = geos.SelectMany(g => g.P).ToList();
        var mn = all.Aggregate(Vector3.Min); var mx = all.Aggregate(Vector3.Max);
        var c = (mn + mx) / 2; float r = all.Max(p => Vector3.Distance(p, c));
        var sb = new StringBuilder();
        sb.Append($"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Drawable>\n <Name>{name}</Name>\n {V3("BoundingSphereCenter", c)}\n <BoundingSphereRadius value=\"{N(r)}\" />\n");
        sb.Append($" {V3("BoundingBoxMin", mn)}\n {V3("BoundingBoxMax", mx)}\n");
        sb.Append(" <LodDistHigh value=\"9998\" />\n <LodDistMed value=\"9998\" />\n <LodDistLow value=\"9998\" />\n <LodDistVlow value=\"9998\" />\n");
        sb.Append(" <FlagsHigh value=\"1\" />\n <FlagsMed value=\"0\" />\n <FlagsLow value=\"0\" />\n <FlagsVlow value=\"0\" />\n");
        sb.Append(" <ShaderGroup>\n  <TextureDictionary>\n");
        foreach (var t in texs)
        {
            sb.Append($"   <Item>\n    <Name>{t.Name}</Name>\n    <Unk32 value=\"128\" />\n    <Usage>{t.Usage}</Usage>\n    <UsageFlags>UNK24</UsageFlags>\n    <ExtraFlags value=\"0\" />\n");
            sb.Append($"    <Width value=\"{t.Img.W}\" />\n    <Height value=\"{t.Img.H}\" />\n    <MipLevels value=\"{mips[t.Name]}\" />\n    <Format>D3DFMT_DXT5</Format>\n    <FileName>{t.Name}.dds</FileName>\n   </Item>\n");
        }
        sb.Append("  </TextureDictionary>\n  <Shaders>\n");
        foreach (var sh in shaders)
        {
            sb.Append($"   <Item>\n    <Name>{sh.Kind}</Name>\n    <FileName>{sh.Kind}.sps</FileName>\n    <RenderBucket value=\"0\" />\n    <Parameters>\n");
            sb.Append(TexP("DiffuseSampler", diffuse));
            var s = sh.Src;
            if (sh.Kind == "normal_spec")
            {
                sb.Append(TexP("BumpSampler", sh.Bump));
                sb.Append(TexP("SpecSampler", sh.Spec));
                sb.Append(Vec("specularFresnel", s.Fresnel));
                sb.Append(Vec("specularFalloffMult", s.Falloff));
                sb.Append(Vec("specularIntensityMult", s.SpecInt));
                sb.Append(Vec("specMapIntMask", s.SpecMask.X, s.SpecMask.Y, s.SpecMask.Z));
                sb.Append(Vec("bumpiness", s.Bumpiness));
                sb.Append(Vec("wetnessMultiplier", 1));
                sb.Append(Vec("useTessellation", 0));
                sb.Append(Vec("HardAlphaBlend", 1));
            }
            else if (sh.Kind == "spec")
            {
                sb.Append(TexP("SpecSampler", sh.Spec));
                sb.Append(Vec("globalAnimUV0", 1, 0, 0));
                sb.Append(Vec("globalAnimUV1", 0, 1, 0));
                sb.Append(Vec("specularFresnel", s.Fresnel));
                sb.Append(Vec("specularFalloffMult", s.Falloff));
                sb.Append(Vec("specularIntensityMult", s.SpecInt));
                sb.Append(Vec("specMapIntMask", s.SpecMask.X, s.SpecMask.Y, s.SpecMask.Z));
                sb.Append(Vec("wetnessMultiplier", 1));
                sb.Append(Vec("useTessellation", 0));
                sb.Append(Vec("HardAlphaBlend", 1));
            }
            else
            {
                sb.Append(Vec("matMaterialColorScale", 1, 0, 0, 1));
                sb.Append(Vec("HardAlphaBlend", 1));
                sb.Append(Vec("useTessellation", 0));
                sb.Append(Vec("wetnessMultiplier", 1));
                sb.Append(Vec("globalAnimUV0", 1, 0, 0));
                sb.Append(Vec("globalAnimUV1", 0, 1, 0));
            }
            sb.Append("    </Parameters>\n   </Item>\n");
        }
        sb.Append("  </Shaders>\n </ShaderGroup>\n <DrawableModelsHigh>\n  <Item>\n   <RenderMask value=\"255\" />\n   <Flags value=\"0\" />\n   <HasSkin value=\"0\" />\n   <BoneIndex value=\"0\" />\n   <Unknown1 value=\"0\" />\n   <Geometries>\n");
        foreach (var g in geos.SelectMany(Split))
        {
            bool tan = shaders[g.Shader].Kind == "normal_spec";
            var gmn = g.P.Aggregate(Vector3.Min); var gmx = g.P.Aggregate(Vector3.Max);
            sb.Append($"    <Item>\n     <ShaderIndex value=\"{g.Shader}\" />\n     {V3("BoundingBoxMin", gmn, true)}\n     {V3("BoundingBoxMax", gmx, true)}\n");
            sb.Append("     <VertexBuffer>\n      <Flags value=\"0\" />\n      <Layout type=\"GTAV1\">\n       <Position />\n       <Normal />\n       <Colour0 />\n       <TexCoord0 />\n");
            if (tan) sb.Append("       <Tangent />\n");
            sb.Append("      </Layout>\n      <Data>\n");
            for (int k = 0; k < g.P.Count; k++)
            {
                var p = g.P[k]; var n = g.N[k]; var uv = g.UV[k];
                sb.Append($"       {N(p.X)} {N(p.Y)} {N(p.Z)}   {N(n.X)} {N(n.Y)} {N(n.Z)}   255 255 255 255   {N(uv.X)} {N(uv.Y)}");
                if (tan) { var t = g.T[k]; sb.Append($"   {N(t.X)} {N(t.Y)} {N(t.Z)} {N(t.W)}"); }
                sb.Append('\n');
            }
            sb.Append("      </Data>\n     </VertexBuffer>\n     <IndexBuffer>\n      <Data>\n");
            for (int k = 0; k < g.I.Count; k += 24) sb.Append("       " + string.Join(' ', g.I.Skip(k).Take(24)) + "\n");
            sb.Append("      </Data>\n     </IndexBuffer>\n    </Item>\n");
        }
        sb.Append("   </Geometries>\n  </Item>\n </DrawableModelsHigh>\n <Lights />\n</Drawable>\n");
        return sb.ToString();
    }

    static void WriteYtyp(string outDir, ChainMap map)
    {
        var items = new StringBuilder();
        foreach (var e in map.Entries.Values.OrderBy(e => e["id"].GetValue<string>()))
        {
            var mn = new Vector3(e["min"][0].GetValue<float>(), e["min"][1].GetValue<float>(), e["min"][2].GetValue<float>());
            var mx = new Vector3(e["max"][0].GetValue<float>(), e["max"][1].GetValue<float>(), e["max"][2].GetValue<float>());
            var c = (mn + mx) / 2; var r = Vector3.Distance(mn, mx) / 2;
            foreach (var v in e["variants"].AsArray())
            {
                var name = v["prop"].GetValue<string>();
                items.Append($"  <Item type=\"CBaseArchetypeDef\">\n   <lodDist value=\"{lodDist}\" />\n   <flags value=\"32\" />\n   <specialAttribute value=\"0\" />\n");
                items.Append($"   <bbMin x=\"{N(mn.X)}\" y=\"{N(mn.Y)}\" z=\"{N(mn.Z)}\" />\n   <bbMax x=\"{N(mx.X)}\" y=\"{N(mx.Y)}\" z=\"{N(mx.Z)}\" />\n");
                items.Append($"   <bsCentre x=\"{N(c.X)}\" y=\"{N(c.Y)}\" z=\"{N(c.Z)}\" />\n   <bsRadius value=\"{N(r)}\" />\n   <hdTextureDist value=\"{Math.Max(10, lodDist / 2)}\" />\n");
                items.Append($"   <name>{name}</name>\n   <textureDictionary />\n   <clipDictionary />\n   <drawableDictionary />\n   <physicsDictionary />\n");
                items.Append($"   <assetType>ASSET_TYPE_DRAWABLE</assetType>\n   <assetName>{name}</assetName>\n   <extensions />\n  </Item>\n");
            }
        }
        var xml = $"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<CMapTypes>\n <extensions />\n <archetypes>\n{items}</archetypes>\n <name>nzc_chains</name>\n <dependencies />\n <compositeEntityTypes itemType=\"CCompositeEntityType\" />\n</CMapTypes>\n";
        var doc = new XmlDocument(); doc.LoadXml(xml);
        var data = XmlMeta.GetData(doc, MetaFormat.RSC, outDir);
        var back = new YtypFile(); back.Load(data);
        File.WriteAllBytes(Path.Combine(outDir, "stream", "nzc_chains.ytyp"), data);
    }

    // icons only: reload each prop and draw it again
    static void RedrawIcons(string outDir, ChainMap map)
    {
        Directory.CreateDirectory(Path.Combine(outDir, "icons"));
        int i = 0, n = map.Entries.Values.Sum(e => e["variants"].AsArray().Count), ok = 0;
        foreach (var e in map.Entries.Values)
        {
            foreach (var v in e["variants"].AsArray())
            {
                var prop = v["prop"].GetValue<string>();
                i++;
                Emit("progress", new JsonObject { ["i"] = i, ["n"] = n, ["key"] = prop, ["label"] = e["label"]?.GetValue<string>() });
                try
                {
                    var y = new YdrFile(); y.Load(File.ReadAllBytes(Path.Combine(outDir, "stream", prop + ".ydr")));
                    var tmp = Path.Combine(Path.GetTempPath(), "chainkit_" + Guid.NewGuid().ToString("n"));
                    Directory.CreateDirectory(tmp);
                    try
                    {
                        var xml = CodeWalker.GameFiles.YdrXml.GetXml(y, tmp);
                        var geos = ParseGeometries(xml);
                        var shaders = ParseShaders(xml);
                        var texd = y.Drawable.ShaderGroup?.TextureDictionary?.Textures?.data_items ?? Array.Empty<CodeWalker.GameFiles.Texture>();
                        var diff = texd.FirstOrDefault(t => t.Name == prop + "_d");
                        var spec = texd.FirstOrDefault(t => t.Name.Contains("_s"));
                        if (diff == null) continue;
                        Raster.Icon(Path.Combine(outDir, "icons", prop + ".png"), geos, Pixels(diff, 1024), spec != null ? Pixels(spec, 512) : null,
                            shaders.FirstOrDefault() ?? new SrcShader(), iconSize > 0 ? iconSize : 256);
                        ok++;
                    }
                    finally { try { Directory.Delete(tmp, true); } catch { } }
                }
                catch (Exception ex) { Console.WriteLine($"skip icon {prop}: {ex.Message}"); }
            }
        }
        Emit("done", new JsonObject { ["built"] = ok, ["tried"] = n, ["removed"] = 0, ["chains"] = map.Entries.Count, ["icons"] = true });
    }

    // chainmap.json: which props belong to which chain, and what they were made from ------------------

    public class ChainMap
    {
        public Dictionary<string, JsonObject> Entries = new();

        public static ChainMap Load(string dir)
        {
            var m = new ChainMap();
            var f = Path.Combine(dir, "chainmap.json");
            if (!File.Exists(f)) return m;
            try
            {
                var root = JsonNode.Parse(File.ReadAllText(f))?["chains"]?.AsObject();
                if (root != null) foreach (var kv in root) m.Entries[kv.Key] = kv.Value.AsObject();
            }
            catch { }
            return m;
        }

        public void Save(string dir)
        {
            var chains = new JsonObject();
            foreach (var kv in Entries.OrderBy(k => k.Key, StringComparer.Ordinal)) chains[kv.Key] = JsonNode.Parse(kv.Value.ToJsonString());
            var root = new JsonObject { ["version"] = 1, ["built"] = DateTimeOffset.UtcNow.ToUnixTimeSeconds(), ["chains"] = chains };
            File.WriteAllText(Path.Combine(dir, "chainmap.json"), root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        }

        static JsonArray A(Vector3 v) => new(MathF.Round(v.X, 5), MathF.Round(v.Y, 5), MathF.Round(v.Z, 5));

        public void Set(Src s, string id, JsonArray variants, Vector3 centre, Vector3 mn, Vector3 mx, int tris, int verts, string[] shaders)
        {
            // props of letters that are gone now
            if (Entries.TryGetValue(s.Key, out var old))
                foreach (var v in old["variants"]?.AsArray() ?? new JsonArray())
                {
                    var p = v?["prop"]?.GetValue<string>();
                    if (p != null && !variants.Any(n => n["prop"].GetValue<string>() == p)) DeleteProp(p);
                }
            Entries[s.Key] = new JsonObject
            {
                ["id"] = id, ["label"] = s.Label, ["origin"] = s.Origin, ["gender"] = s.Gender, ["collection"] = s.Collection,
                ["comp"] = s.Comp, ["local"] = s.Local, ["src"] = s.Ydd, ["sig"] = s.Sig, ["folder"] = s.Folder,
                ["variants"] = variants, ["centre"] = A(centre), ["min"] = A(mn), ["max"] = A(mx),
                ["tris"] = tris, ["verts"] = verts, ["shaders"] = new JsonArray(shaders.Select(x => (JsonNode)x).ToArray()),
            };
        }

        string dir;
        void DeleteProp(string p)
        {
            if (dir == null) return;
            try { File.Delete(Path.Combine(dir, "stream", p + ".ydr")); } catch { }
            try { File.Delete(Path.Combine(dir, "icons", p + ".png")); } catch { }
        }

        public void Remove(string outDir, string key)
        {
            dir = outDir;
            if (!Entries.TryGetValue(key, out var e)) return;
            foreach (var v in e["variants"]?.AsArray() ?? new JsonArray()) DeleteProp(v["prop"].GetValue<string>());
            Entries.Remove(key);
        }

        public void Bind(string outDir) => dir = outDir;

        public class DiffResult
        {
            public List<Src> New = new(), Changed = new();
            public List<string> Removed = new();
            public JsonObject ToJson(List<Src> found, ChainMap map) => new()
            {
                ["found"] = found.Count, ["chains"] = map.Entries.Count,
                ["new"] = new JsonArray(New.Select(s => (JsonNode)new JsonObject { ["key"] = s.Key, ["label"] = s.Label, ["variants"] = Math.Max(1, s.Ytds.Count) }).ToArray()),
                ["changed"] = new JsonArray(Changed.Select(s => (JsonNode)new JsonObject { ["key"] = s.Key, ["label"] = s.Label, ["variants"] = Math.Max(1, s.Ytds.Count) }).ToArray()),
                ["removed"] = new JsonArray(Removed.Select(k => (JsonNode)new JsonObject { ["key"] = k, ["label"] = map.Entries.TryGetValue(k, out var e) ? e["label"]?.GetValue<string>() : k }).ToArray()),
            };
        }

        public DiffResult Diff(List<Src> found)
        {
            var d = new DiffResult();
            var seen = new HashSet<string>();
            foreach (var s in found)
            {
                seen.Add(s.Key);
                if (!Entries.TryGetValue(s.Key, out var e)) d.New.Add(s);
                else if (e["sig"]?.GetValue<string>() != s.Sig || e["src"]?.GetValue<string>() != s.Ydd) d.Changed.Add(s);
            }
            foreach (var kv in Entries) if (!seen.Contains(kv.Key)) d.Removed.Add(kv.Key);
            return d;
        }
    }

}
