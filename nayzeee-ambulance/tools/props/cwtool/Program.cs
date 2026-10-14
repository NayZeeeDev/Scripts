using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Xml;
using CodeWalker.GameFiles;

// cwtool - thin CLI over CodeWalker.Core (dexyfex) used by tools/props/build.py.
//
//   cwtool ydr  <in.ydr.xml>  <ddsFolder> <out.ydr>      XML (+ DDS) -> legacy RSC7 drawable
//   cwtool ytd  <in.ytd.xml>  <ddsFolder> <out.ytd>      XML (+ DDS) -> texture dictionary
//   cwtool ytyp <in.ytyp.xml> <out.ytyp>                  XML -> archetype definitions
//   cwtool inspect <file.ydr|.ytd|.ytyp> [reexport.xml]   load a binary back, print it and validate it
//   cwtool batch <commands.txt>                           run many of the above in one process
//
// Every command prints "RESULT OK" or "RESULT FAIL: <reasons>" as its last line. The process exit
// code is 0 only when every command succeeded (batch: every line), so build scripts can rely on it.
// Batch files hold one command per line, arguments separated by TABs; empty lines and lines that
// start with '#' are ignored. Each command's output is framed by "### <n> <command>" lines.
static class Program
{
    static int Main(string[] args)
    {
        RpfManager.IsGen9 = false; // legacy (gen8) resources - what FiveM streams
        if (args.Length == 0) return Usage();
        if (args[0] == "batch")
        {
            if (args.Length < 2) return Usage();
            return Batch(args[1]);
        }
        return Run(args);
    }

    static int Usage()
    {
        Console.WriteLine("usage:\n  cwtool ydr  <in.ydr.xml>  <ddsFolder> <out.ydr>\n  cwtool ytd  <in.ytd.xml>  <ddsFolder> <out.ytd>\n  cwtool ytyp <in.ytyp.xml> <out.ytyp>\n  cwtool inspect <file.ydr|.ytd|.ytyp> [reexport.xml]\n  cwtool batch <commands.txt>");
        return 1;
    }

    static int Run(string[] args)
    {
        var problems = new List<string>();
        try
        {
            switch (args[0])
            {
                case "ydr": Need(args, 4); BuildYdr(args[1], args[2], args[3]); break;
                case "ytd": Need(args, 4); BuildYtd(args[1], args[2], args[3]); break;
                case "ytyp": Need(args, 3); BuildYtyp(args[1], args[2]); break;
                case "inspect": Need(args, 2); Inspect(args[1], args.Length > 2 ? args[2] : null, problems); break;
                default: return Usage();
            }
        }
        catch (Exception ex)
        {
            problems.Add(ex.GetType().Name + ": " + ex.Message);
            Console.Error.WriteLine(ex.ToString());
        }
        if (problems.Count == 0)
        {
            Console.WriteLine("RESULT OK");
            return 0;
        }
        Console.WriteLine("RESULT FAIL: " + string.Join(" | ", problems));
        return 2;
    }

    static int Batch(string listPath)
    {
        var lines = File.ReadAllLines(listPath);
        int n = 0, failed = 0;
        foreach (var raw in lines)
        {
            var line = raw.TrimEnd('\r', '\n');
            if (line.Trim().Length == 0 || line.TrimStart().StartsWith("#")) continue;
            n++;
            var parts = line.Split('\t').Select(p => p.Trim()).Where(p => p.Length > 0).ToArray();
            Console.WriteLine($"### {n} {string.Join(" ", parts)}");
            var rc = Run(parts);
            if (rc != 0) failed++;
            Console.WriteLine($"### {n} end rc={rc}");
        }
        Console.WriteLine($"BATCH {n} commands, {failed} failed");
        return failed == 0 ? 0 : 4;
    }

    static void Need(string[] args, int count)
    {
        if (args.Length < count) throw new ArgumentException($"'{args[0]}' needs {count - 1} argument(s)");
    }

    static XmlDocument LoadDoc(string path)
    {
        var doc = new XmlDocument();
        doc.LoadXml(File.ReadAllText(path));
        return doc;
    }

    static void BuildYdr(string xmlPath, string ddsFolder, string outPath)
    {
        var ydr = XmlYdr.GetYdr(LoadDoc(xmlPath), ddsFolder);
        if (ydr?.Drawable == null) throw new Exception("Drawable not parsed from " + xmlPath);
        var data = ydr.Save();
        File.WriteAllBytes(outPath, data);
        Console.WriteLine($"wrote {outPath} ({data.Length} bytes)");
    }

    static void BuildYtd(string xmlPath, string ddsFolder, string outPath)
    {
        var ytd = XmlYtd.GetYtd(LoadDoc(xmlPath), ddsFolder);
        if (ytd?.TextureDict == null) throw new Exception("TextureDictionary not parsed from " + xmlPath);
        var data = ytd.Save();
        File.WriteAllBytes(outPath, data);
        Console.WriteLine($"wrote {outPath} ({data.Length} bytes)");
    }

    static void BuildYtyp(string xmlPath, string outPath)
    {
        var data = XmlMeta.GetRSCData(LoadDoc(xmlPath));
        if (data == null || data.Length == 0) throw new Exception("ytyp meta not built (empty?) from " + xmlPath);
        File.WriteAllBytes(outPath, data);
        Console.WriteLine($"wrote {outPath} ({data.Length} bytes)");
    }

    static bool Finite(SharpDX.Vector3 v) => !(float.IsNaN(v.X) || float.IsNaN(v.Y) || float.IsNaN(v.Z) || float.IsInfinity(v.X) || float.IsInfinity(v.Y) || float.IsInfinity(v.Z));

    static bool Ordered(SharpDX.Vector3 a, SharpDX.Vector3 b) => a.X <= b.X && a.Y <= b.Y && a.Z <= b.Z;

    static void Inspect(string path, string reexport, List<string> problems)
    {
        var bytes = File.ReadAllBytes(path);
        var ext = Path.GetExtension(path).ToLowerInvariant();
        var magic = bytes.Length >= 4 ? Encoding.ASCII.GetString(bytes, 0, 4) : "????";
        var version = bytes.Length >= 8 ? BitConverter.ToInt32(bytes, 4) : -1;
        Console.WriteLine($"file: {path} size={bytes.Length} magic={magic} version={version}");
        if (magic != "RSC7") problems.Add("not an RSC7 resource");
        if (ext == ".ydr") InspectYdr(path, bytes, reexport, problems);
        else if (ext == ".ytd") InspectYtd(bytes, reexport, problems);
        else if (ext == ".ytyp") InspectYtyp(bytes, reexport, problems);
        else problems.Add("unsupported extension " + ext);
    }

    static void InspectYdr(string path, byte[] bytes, string reexport, List<string> problems)
    {
        var ydr = new YdrFile();
        ydr.Load(bytes);
        var d = ydr.Drawable;
        if (d == null) { problems.Add("drawable failed to load"); return; }
        var expectName = Path.GetFileNameWithoutExtension(path).ToLowerInvariant();
        Console.WriteLine($"Drawable Name={d.Name}");
        if (!string.Equals(d.Name, expectName, StringComparison.OrdinalIgnoreCase)) problems.Add($"drawable name '{d.Name}' != file name '{expectName}'");
        Console.WriteLine($"  BSCenter={d.BoundingCenter} BSRadius={d.BoundingSphereRadius}");
        Console.WriteLine($"  BBMin={d.BoundingBoxMin} BBMax={d.BoundingBoxMax}");
        Console.WriteLine($"  LodDist H/M/L/VL={d.LodDistHigh}/{d.LodDistMed}/{d.LodDistLow}/{d.LodDistVlow} Flags={d.FlagsHigh}/{d.FlagsMed}/{d.FlagsLow}/{d.FlagsVlow}");
        if (!Finite(d.BoundingBoxMin) || !Finite(d.BoundingBoxMax) || !Ordered(d.BoundingBoxMin, d.BoundingBoxMax)) problems.Add("invalid drawable bounding box");
        if (!(d.BoundingSphereRadius > 0)) problems.Add("bounding sphere radius <= 0");

        var embedded = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var sg = d.ShaderGroup;
        if (sg?.TextureDictionary?.Textures?.data_items != null)
        {
            foreach (var t in sg.TextureDictionary.Textures.data_items)
            {
                var len = t.Data?.FullData?.Length ?? 0;
                Console.WriteLine($"  EmbeddedTex Name={t.Name} {t.Width}x{t.Height} mips={t.Levels} fmt={t.Format} usage={t.Usage} datalen={len}");
                embedded.Add(t.Name);
                if (len == 0) problems.Add($"texture {t.Name} has no pixel data");
                if (t.Width == 0 || t.Height == 0 || t.Levels == 0) problems.Add($"texture {t.Name} has invalid size/mips");
            }
        }
        int shaderCount = sg?.Shaders?.data_items?.Length ?? 0;
        if (shaderCount == 0) problems.Add("no shaders");
        if (sg?.Shaders?.data_items != null)
        {
            foreach (var s in sg.Shaders.data_items)
            {
                Console.WriteLine($"  Shader Name={s.Name} FileName={s.FileName} Bucket={s.RenderBucket} Params={s.ParametersList?.Count} TexParams={s.TextureParametersCount}");
                var pl = s.ParametersList;
                if (pl?.Parameters == null) continue;
                for (int i = 0; i < pl.Parameters.Length; i++)
                {
                    var p = pl.Parameters[i];
                    var nm = (ShaderParamNames)pl.Hashes[i];
                    string val;
                    if (p.Data is TextureBase tb)
                    {
                        val = "tex:" + tb.Name + (tb is Texture ? " (embedded)" : " (reference)");
                        if (!(tb is Texture) && !embedded.Contains(tb.Name ?? "")) problems.Add($"shader {s.Name} param {nm} references missing texture '{tb.Name}'");
                    }
                    else if (p.DataType == 0 && p.Data == null)
                    {
                        val = "tex:<none>";
                        problems.Add($"shader {s.Name} param {nm} has no texture");
                    }
                    else val = p.Data?.ToString() ?? "null";
                    Console.WriteLine($"    [{i}] {nm} type={p.DataType} {val}");
                }
            }
        }

        var hi = d.DrawableModels?.High;
        int geoms = 0;
        if (hi != null)
        {
            foreach (var m in hi)
            {
                Console.WriteLine($"  Model RenderMask={m.RenderMask} Flags={m.Flags} HasSkin={m.HasSkin} Geoms={m.Geometries?.Length}");
                if (m.Geometries == null) continue;
                foreach (var g in m.Geometries)
                {
                    geoms++;
                    Console.WriteLine($"    Geom shader={g.ShaderID} verts={g.VerticesCount} idx={g.IndicesCount} stride={g.VertexStride} type={g.VertexBuffer?.Info?.Types} aabb={g.AABB.Min}..{g.AABB.Max}");
                    if (g.VerticesCount == 0 || g.IndicesCount == 0 || g.IndicesCount % 3 != 0) problems.Add($"geometry with invalid vertex/index count ({g.VerticesCount}/{g.IndicesCount})");
                    if (g.ShaderID >= shaderCount) problems.Add($"geometry shader index {g.ShaderID} out of range");
                }
            }
        }
        if (geoms == 0) problems.Add("no high LOD geometry");

        if (d.Bound != null)
        {
            Console.WriteLine($"  Bound type={d.Bound.Type} BoxMin={d.Bound.BoxMin} BoxMax={d.Bound.BoxMax} SphereR={d.Bound.SphereRadius} Margin={d.Bound.Margin} Vol={d.Bound.Volume}");
            if (!Ordered(d.Bound.BoxMin, d.Bound.BoxMax)) problems.Add("collision bounding box min > max");
            if (d.Bound is BoundComposite bc)
            {
                var kids = bc.Children?.data_items;
                if (kids == null || kids.Length == 0) problems.Add("composite bound without children");
                else
                {
                    foreach (var c in kids)
                    {
                        if (c == null) { problems.Add("null composite child"); continue; }
                        var t = c.Transform.TranslationVector;
                        Console.WriteLine($"    Child type={c.Type} BoxMin={c.BoxMin} BoxMax={c.BoxMax} Pos={t} Margin={c.Margin} Vol={c.Volume} Mat={c.MaterialIndex} F1={c.CompositeFlags1.Flags1} F2={c.CompositeFlags1.Flags2}");
                        if (!Ordered(c.BoxMin, c.BoxMax)) problems.Add($"child {c.Type} min > max");
                        if (!(c.Volume > 0)) problems.Add($"child {c.Type} volume <= 0");
                    }
                }
            }
        }
        else problems.Add("no embedded collision");
        if (reexport != null) File.WriteAllText(reexport, YdrXml.GetXml(ydr));
    }

    static void InspectYtd(byte[] bytes, string reexport, List<string> problems)
    {
        var ytd = new YtdFile();
        ytd.Load(bytes);
        var items = ytd.TextureDict?.Textures?.data_items;
        if (items == null || items.Length == 0) { problems.Add("texture dictionary empty"); return; }
        foreach (var t in items)
            Console.WriteLine($"  Tex Name={t.Name} {t.Width}x{t.Height} mips={t.Levels} fmt={t.Format}");
        if (reexport != null) File.WriteAllText(reexport, YtdXml.GetXml(ytd));
    }

    static void InspectYtyp(byte[] bytes, string reexport, List<string> problems)
    {
        var ytyp = new YtypFile();
        ytyp.Load(bytes);
        var all = ytyp.AllArchetypes;
        Console.WriteLine($"Ytyp Name={ytyp.NameHash} ({(uint)ytyp.NameHash}) archetypes={all?.Length}");
        if (all == null || all.Length == 0) { problems.Add("no archetypes"); return; }
        foreach (var a in all)
        {
            var b = a._BaseArchetypeDef;
            Console.WriteLine($"  Arch name={a.Name} hash={(uint)a.Hash} assetName={a.AssetName} type={a.Type} assetType={b.assetType} lodDist={a.LodDist} hdTex={b.hdTextureDist} flags={b.flags} special={b.specialAttribute} txd={a.TextureDict} phys={b.physicsDictionary} bbmin={a.BBMin} bbmax={a.BBMax} bsc={a.BSCenter} bsr={a.BSRadius}");
            if (string.IsNullOrEmpty(a.Name)) problems.Add("archetype without name");
            if (!string.Equals(a.Name, a.AssetName, StringComparison.OrdinalIgnoreCase)) problems.Add($"archetype {a.Name} assetName mismatch ({a.AssetName})");
            if (!(a.LodDist > 0)) problems.Add($"archetype {a.Name} lodDist <= 0");
            if (!Ordered(a.BBMin, a.BBMax)) problems.Add($"archetype {a.Name} bbMin > bbMax");
            if (!(a.BSRadius > 0)) problems.Add($"archetype {a.Name} bsRadius <= 0");
        }
        if (reexport != null) File.WriteAllText(reexport, MetaXml.GetXml(ytyp, out _));
    }
}
