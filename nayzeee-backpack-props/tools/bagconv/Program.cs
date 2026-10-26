using System.Xml;
using CodeWalker.GameFiles;

// bagconv: thin CLI over CodeWalker.Core
//   export <file.ydd|ydr|ytd|ytyp> <outdir>      -> XML (+ .dds textures) in outdir
//   import <file.xml> <ydr|ytd|ytyp> <outfile>    -> binary from XML (textures read next to the xml)
//   info   <file.ydr|ydd>                          -> quick summary
class P
{
    static int Main(string[] a)
    {
        try
        {
            switch (a[0])
            {
                case "export": return Export(a[1], a[2]);
                case "import": return Import(a[1], a[2], a[3], a.Length > 4 ? a[4] : null);
                case "info": return Info(a[1]);
            }
        }
        catch (Exception e)
        {
            Console.Error.WriteLine("ERROR " + e);
            return 2;
        }
        Console.Error.WriteLine("usage: export|import|info");
        return 1;
    }

    static RpfFileEntry Entry(string path, ref byte[] data)
    {
        var e = RpfFile.CreateResourceFileEntry(ref data, 0);
        data = ResourceBuilder.Decompress(data);
        e.Name = Path.GetFileName(path);
        e.NameLower = e.Name.ToLowerInvariant();
        return e;
    }

    static int Export(string path, string outdir)
    {
        Directory.CreateDirectory(outdir);
        var data = File.ReadAllBytes(path);
        var e = Entry(path, ref data);
        string fname;
        var xml = MetaXml.GetXml(e, data, out fname, outdir);
        if (string.IsNullOrEmpty(xml)) { Console.Error.WriteLine("no xml for " + path); return 3; }
        File.WriteAllText(Path.Combine(outdir, fname), xml);
        Console.WriteLine(Path.Combine(outdir, fname));
        return 0;
    }

    static int Import(string xmlPath, string kind, string outFile, string texFolder)
    {
        var doc = new XmlDocument();
        doc.Load(xmlPath);
        var folder = texFolder ?? Path.GetDirectoryName(Path.GetFullPath(xmlPath));
        MetaFormat fmt = kind switch
        {
            "ydr" => MetaFormat.Ydr,
            "ytd" => MetaFormat.Ytd,
            "ytyp" => MetaFormat.RSC,
            _ => throw new Exception("unknown kind " + kind),
        };
        var bytes = XmlMeta.GetData(doc, fmt, folder);
        if (bytes == null || bytes.Length == 0) { Console.Error.WriteLine("import produced nothing"); return 4; }
        File.WriteAllBytes(outFile, bytes);
        Console.WriteLine($"{outFile} {bytes.Length}");
        return 0;
    }

    static int Info(string path)
    {
        var data = File.ReadAllBytes(path);
        var e = Entry(path, ref data);
        Drawable[] ds;
        if (path.EndsWith(".ydd"))
        {
            var y = new YddFile(); y.Load(data, e); ds = y.Drawables;
        }
        else
        {
            var y = new YdrFile(); y.Load(data, e); ds = new[] { y.Drawable };
        }
        foreach (var d in ds)
        {
            Console.WriteLine($"drawable {d.Name} bbmin {d.BoundingBoxMin} bbmax {d.BoundingBoxMax} centre {d.BoundingCenter} r {d.BoundingSphereRadius}");
            Console.WriteLine($"  skeleton {(d.Skeleton != null)} models {d.DrawableModels?.High?.Length} embeddedTex {d.ShaderGroup?.TextureDictionary?.Textures?.data_items?.Length}");
            foreach (var s in d.ShaderGroup?.Shaders?.data_items ?? Array.Empty<ShaderFX>())
                Console.WriteLine($"  shader {s.Name} {s.FileName}");
            foreach (var m in d.DrawableModels?.High ?? Array.Empty<DrawableModel>())
                foreach (var g in m.Geometries ?? Array.Empty<DrawableGeometry>())
                    Console.WriteLine($"  geom verts {g.VerticesCount} idx {g.IndicesCount} shader {g.ShaderID} layout {g.VertexBuffer?.Info?.Types} flags {g.VertexBuffer?.Info?.Flags}");
        }
        return 0;
    }
}
