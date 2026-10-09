using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Xml;
using CodeWalker.GameFiles;

// cwtool: thin CLI over CodeWalker.Core (dexyfex) to convert CodeWalker XML -> legacy (non-gen9) RSC7 binaries,
// and to load binaries back for round-trip verification.
static class Program
{
    static int Main(string[] args)
    {
        try
        {
            RpfManager.IsGen9 = false; // legacy format (what FiveM uses)
            if (args.Length == 0) return Usage();
            switch (args[0])
            {
                case "ydr": return BuildYdr(args[1], args[2], args[3]);
                case "ytd": return BuildYtd(args[1], args[2], args[3]);
                case "ytyp": return BuildYtyp(args[1], args[2]);
                case "inspect": return Inspect(args[1], args.Length > 2 ? args[2] : null);
                default: return Usage();
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("ERROR: " + ex);
            return 2;
        }
    }

    static int Usage()
    {
        Console.WriteLine("usage:\n  cwtool ydr  <in.ydr.xml>  <ddsFolder> <out.ydr>\n  cwtool ytd  <in.ytd.xml>  <ddsFolder> <out.ytd>\n  cwtool ytyp <in.ytyp.xml> <out.ytyp>\n  cwtool inspect <file.ydr|.ytd|.ytyp> [reexport.xml]");
        return 1;
    }

    static XmlDocument LoadDoc(string path)
    {
        var doc = new XmlDocument();
        doc.LoadXml(File.ReadAllText(path));
        return doc;
    }

    static int BuildYdr(string xmlPath, string ddsFolder, string outPath)
    {
        var ydr = XmlYdr.GetYdr(LoadDoc(xmlPath), ddsFolder);
        if (ydr.Drawable == null) throw new Exception("Drawable not parsed");
        var data = ydr.Save();
        File.WriteAllBytes(outPath, data);
        Console.WriteLine($"wrote {outPath} ({data.Length} bytes)");
        return 0;
    }

    static int BuildYtd(string xmlPath, string ddsFolder, string outPath)
    {
        var ytd = XmlYtd.GetYtd(LoadDoc(xmlPath), ddsFolder);
        if (ytd.TextureDict == null) throw new Exception("TextureDictionary not parsed");
        var data = ytd.Save();
        File.WriteAllBytes(outPath, data);
        Console.WriteLine($"wrote {outPath} ({data.Length} bytes)");
        return 0;
    }

    static int BuildYtyp(string xmlPath, string outPath)
    {
        var data = XmlMeta.GetRSCData(LoadDoc(xmlPath));
        if (data == null) throw new Exception("ytyp meta not built (empty?)");
        File.WriteAllBytes(outPath, data);
        Console.WriteLine($"wrote {outPath} ({data.Length} bytes)");
        return 0;
    }

    static int Inspect(string path, string reexport)
    {
        var bytes = File.ReadAllBytes(path);
        var ext = Path.GetExtension(path).ToLowerInvariant();
        Console.WriteLine($"file: {path} size={bytes.Length} magic={Encoding.ASCII.GetString(bytes, 0, 4)} version={BitConverter.ToInt32(bytes, 4)}");
        if (ext == ".ydr")
        {
            var ydr = new YdrFile();
            ydr.Load(bytes);
            var d = ydr.Drawable;
            if (d == null) throw new Exception("drawable failed to load");
            Console.WriteLine($"Drawable Name={d.Name}");
            Console.WriteLine($"  BSCenter={d.BoundingCenter} BSRadius={d.BoundingSphereRadius}");
            Console.WriteLine($"  BBMin={d.BoundingBoxMin} BBMax={d.BoundingBoxMax}");
            Console.WriteLine($"  LodDist H/M/L/VL={d.LodDistHigh}/{d.LodDistMed}/{d.LodDistLow}/{d.LodDistVlow} Flags={d.FlagsHigh}/{d.FlagsMed}/{d.FlagsLow}/{d.FlagsVlow}");
            var sg = d.ShaderGroup;
            if (sg?.Shaders?.data_items != null)
            {
                foreach (var s in sg.Shaders.data_items)
                {
                    Console.WriteLine($"  Shader Name={s.Name} FileName={s.FileName} Bucket={s.RenderBucket} Params={s.ParametersList?.Count} TexParams={s.TextureParametersCount}");
                    var pl = s.ParametersList;
                    if (pl?.Parameters != null)
                    {
                        for (int i = 0; i < pl.Parameters.Length; i++)
                        {
                            var p = pl.Parameters[i];
                            var nm = (ShaderParamNames)pl.Hashes[i];
                            string val = p.Data is TextureBase tb ? ("tex:" + tb.Name + (tb is Texture ? " (embedded)" : " (external)")) : (p.Data?.ToString() ?? "null");
                            Console.WriteLine($"    [{i}] {nm} type={p.DataType} {val}");
                        }
                    }
                }
            }
            if (sg?.TextureDictionary?.Textures?.data_items != null)
            {
                foreach (var t in sg.TextureDictionary.Textures.data_items)
                    Console.WriteLine($"  EmbeddedTex Name={t.Name} {t.Width}x{t.Height} mips={t.Levels} fmt={t.Format} usage={t.Usage} flags={t.UsageFlags} datalen={t.Data?.FullData?.Length}");
            }
            var hi = d.DrawableModels?.High;
            if (hi != null)
            {
                foreach (var m in hi)
                {
                    Console.WriteLine($"  Model RenderMask={m.RenderMask} Flags={m.Flags} HasSkin={m.HasSkin} Geoms={m.Geometries?.Length}");
                    if (m.Geometries != null)
                        foreach (var g in m.Geometries)
                            Console.WriteLine($"    Geom shader={g.ShaderID} verts={g.VerticesCount} idx={g.IndicesCount} stride={g.VertexStride} type={g.VertexBuffer?.Info?.Types} flags={g.VertexBuffer?.Info?.Flags} aabb={g.AABB.Min}..{g.AABB.Max}");
                }
            }
            if (d.Bound != null)
            {
                Console.WriteLine($"  Bound type={d.Bound.Type} BoxMin={d.Bound.BoxMin} BoxMax={d.Bound.BoxMax} SphereR={d.Bound.SphereRadius} Margin={d.Bound.Margin} Vol={d.Bound.Volume}");
                if (d.Bound is BoundComposite bc && bc.Children?.data_items != null)
                    foreach (var c in bc.Children.data_items)
                        Console.WriteLine($"    Child type={c?.Type} BoxMin={c?.BoxMin} BoxMax={c?.BoxMax} Margin={c?.Margin} Vol={c?.Volume} Mat={c?.MaterialIndex} F1={c?.CompositeFlags1.Flags1} F2={c?.CompositeFlags1.Flags2}");
            }
            else Console.WriteLine("  Bound: none");
            if (reexport != null) File.WriteAllText(reexport, YdrXml.GetXml(ydr));
        }
        else if (ext == ".ytd")
        {
            var ytd = new YtdFile();
            ytd.Load(bytes);
            foreach (var t in ytd.TextureDict.Textures.data_items)
                Console.WriteLine($"  Tex Name={t.Name} {t.Width}x{t.Height} mips={t.Levels} fmt={t.Format}");
            if (reexport != null) File.WriteAllText(reexport, YtdXml.GetXml(ytd));
        }
        else if (ext == ".ytyp")
        {
            var ytyp = new YtypFile();
            ytyp.Load(bytes);
            Console.WriteLine($"Ytyp Name={ytyp.NameHash} ({(uint)ytyp.NameHash}) archetypes={ytyp.AllArchetypes?.Length}");
            if (ytyp.AllArchetypes != null)
                foreach (var a in ytyp.AllArchetypes)
                    Console.WriteLine($"  Arch name={a.Name} hash={(uint)a.Hash} assetName={a.AssetName} type={a.Type} assetType={a._BaseArchetypeDef.assetType} lodDist={a.LodDist} hdTex={a._BaseArchetypeDef.hdTextureDist} flags={a._BaseArchetypeDef.flags} special={a._BaseArchetypeDef.specialAttribute} txd={a.TextureDict} phys={a._BaseArchetypeDef.physicsDictionary} bbmin={a.BBMin} bbmax={a.BBMax} bsc={a.BSCenter} bsr={a.BSRadius}");
            if (reexport != null) File.WriteAllText(reexport, MetaXml.GetXml(ytyp, out _));
        }
        return 0;
    }
}
