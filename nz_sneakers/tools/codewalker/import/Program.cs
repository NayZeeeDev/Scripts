// Imports every .ydr.xml / .ytyp.xml in a folder the same way CodeWalker's
// RPF Explorer "Import XML" does, writes the binary next to it, then loads the
// binary back and prints what's inside.
using System;
using System.IO;
using System.Linq;
using System.Xml;
using CodeWalker.GameFiles;

class Program
{
    static int Main(string[] args)
    {
        var dir = args[0];
        int fails = 0;
        foreach (var fpath in Directory.GetFiles(dir, "*.xml", SearchOption.AllDirectories).OrderBy(p => p))
        {
            var fname = Path.GetFileName(fpath);
            var fnamel = fname.ToLowerInvariant();
            if (fnamel.IndexOf('.') == fnamel.LastIndexOf('.')) continue;
            try
            {
                var mformat = XmlMeta.GetXMLFormat(fnamel, out int trim);
                var outName = fname.Substring(0, fname.Length - trim);
                var fpathin = fpath.Substring(0, fpath.Length - trim);
                fpathin = Path.Combine(Path.GetDirectoryName(fpathin), Path.GetFileNameWithoutExtension(fpathin));
                var doc = new XmlDocument();
                doc.LoadXml(File.ReadAllText(fpath));
                var data = XmlMeta.GetData(doc, mformat, fpathin);
                if (data == null) throw new Exception("GetData returned null (" + mformat + ")");
                var outPath = Path.Combine(Path.GetDirectoryName(fpath), outName);
                File.WriteAllBytes(outPath, data);
                Console.WriteLine($"OK   {fname} -> {outName} ({data.Length} bytes, {mformat})");
                Describe(mformat, data);
            }
            catch (Exception ex)
            {
                fails++;
                Console.WriteLine($"FAIL {fname}: {ex}");
            }
        }
        return fails;
    }

    static void Describe(MetaFormat fmt, byte[] data)
    {
        if (fmt == MetaFormat.Ydr)
        {
            var copy = (byte[])data.Clone();
            var entry = RpfFile.CreateResourceFileEntry(ref copy, 0);
            var ydr = RpfFile.GetResourceFile<YdrFile>((byte[])data.Clone());
            var d = ydr.Drawable;
            Console.WriteLine($"     drawable '{d.Name}' rsc v{entry.Version}  bbox {d.BoundingBoxMin} .. {d.BoundingBoxMax}  r={d.BoundingSphereRadius}");
            Console.WriteLine($"     lod high {d.LodDistHigh}  flagsHigh {d.FlagsHigh}");
            foreach (var t in d.ShaderGroup?.TextureDictionary?.Textures?.data_items ?? new Texture[0])
                Console.WriteLine($"     texture '{t.Name}' {t.Width}x{t.Height} {t.Format} mips {t.Levels} usage {t.Usage} bytes {t.Data?.FullData?.Length}");
            foreach (var s in d.ShaderGroup?.Shaders?.data_items ?? new ShaderFX[0])
            {
                Console.WriteLine($"     shader {s.Name} / {s.FileName} bucket {s.RenderBucket} params {s.ParameterCount}");
                var pl = s.ParametersList;
                for (int i = 0; i < pl.Parameters.Length; i++)
                {
                    var p = pl.Parameters[i];
                    var val = p.Data is TextureBase tb ? "tex " + tb.Name + (tb is Texture ? " (embedded)" : " (external)") : p.Data?.ToString();
                    Console.WriteLine($"        {pl.Hashes[i]} = {val}");
                }
            }
            foreach (var m in d.DrawableModels?.High ?? new DrawableModel[0])
                foreach (var g in m.Geometries)
                    Console.WriteLine($"     geometry: {g.VerticesCount} verts, {g.IndicesCount} idx, stride {g.VertexStride}, type {g.VertexData?.VertexType}, shader {g.ShaderID}");
            if (d.Bound is BoundComposite bc)
            {
                Console.WriteLine($"     bounds Composite {bc.BoxMin} .. {bc.BoxMax}, children {bc.Children?.data_items?.Length}");
                foreach (var c in bc.Children.data_items)
                    Console.WriteLine($"        child {c.Type} {c.BoxMin} .. {c.BoxMax} flags {c.CompositeFlags1.Flags1} | {c.CompositeFlags1.Flags2}");
            }
            else Console.WriteLine($"     bounds: {d.Bound?.Type.ToString() ?? "none"}");
            // vertex sample
            var g0 = d.DrawableModels?.High?[0]?.Geometries?[0];
            if (g0?.VertexData != null)
            {
                var vd = g0.VertexData;
                for (int v = 0; v < Math.Min(2, vd.VertexCount); v++)
                    Console.WriteLine($"        v{v}: {string.Join(" | ", Enumerable.Range(0, 16).Where(k => ((vd.Info.Flags >> k) & 1) == 1).Select(k => vd.GetString(v, k, " ")))}");
            }
        }
        else if (fmt == MetaFormat.RSC)
        {
            var ytyp = new YtypFile();
            ytyp.Load(data);
            Console.WriteLine($"     ytyp '{ytyp.Name}' archetypes: {string.Join(", ", ytyp.AllArchetypes.Select(a => a.Name + $" [txd {a._BaseArchetypeDef.textureDictionary} lod {a.LodDist} bb {a.BBMin}..{a.BBMax}]"))}");
        }
    }
}
