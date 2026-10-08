// cwconv: inspect / export GTA resources with CodeWalker.Core
//   cwconv inspect <file.ydd|.ytd>
//   cwconv ydd2xml <file.ydd> <outdir>      (YddXml, like CodeWalker "Export XML")
//   cwconv ytd2dds <file.ytd> <outdir>
using System;
using System.IO;
using System.Linq;
using CodeWalker.GameFiles;
using CodeWalker.Utils;

class P {
  static int Main(string[] a) {
    var cmd = a[0]; var path = a[1];
    var data = File.ReadAllBytes(path);
    if (path.EndsWith(".ydd")) {
      var ydd = RpfFile.GetResourceFile<YddFile>(data);
      if (cmd == "ydd2xml") {
        Directory.CreateDirectory(a[2]);
        var name = Path.GetFileNameWithoutExtension(path);
        var xml = YddXml.GetXml(ydd, Path.Combine(a[2], name));
        File.WriteAllText(Path.Combine(a[2], name + ".ydd.xml"), xml);
        Console.WriteLine("wrote " + name + ".ydd.xml");
        return 0;
      }
      foreach (var d in ydd.Drawables) {
        Console.WriteLine($"drawable {d.Name}  bbox {d.BoundingBoxMin} .. {d.BoundingBoxMax}  skel {(d.Skeleton!=null)}");
        foreach (var s in d.ShaderGroup?.Shaders?.data_items ?? new ShaderFX[0]) {
          var ps = s.ParametersList; var texs = string.Join(", ", Enumerable.Range(0, ps.Parameters.Length).Where(i => ps.Parameters[i].Data is TextureBase).Select(i => ps.Hashes[i] + "=" + ((TextureBase)ps.Parameters[i].Data).Name));
          Console.WriteLine($"  shader {s.Name} ({s.FileName}) {texs}");
        }
        var lods = new[] { ("High", d.DrawableModels?.High), ("Med", d.DrawableModels?.Med), ("Low", d.DrawableModels?.Low) };
        foreach (var (ln, models) in lods) {
          if (models == null) continue;
          foreach (var m in models) foreach (var g in m.Geometries)
            Console.WriteLine($"  {ln}: geom shader {g.ShaderID} verts {g.VerticesCount} tris {g.IndicesCount/3} type {g.VertexData?.VertexType} skin {m.HasSkin}");
        }
        foreach (var t in d.ShaderGroup?.TextureDictionary?.Textures?.data_items ?? new Texture[0])
          Console.WriteLine($"  embedded tex {t.Name} {t.Width}x{t.Height} {t.Format}");
      }
    } else if (path.EndsWith(".ytd")) {
      var ytd = RpfFile.GetResourceFile<YtdFile>(data);
      foreach (var t in ytd.TextureDict.Textures.data_items) {
        Console.WriteLine($"tex {t.Name} {t.Width}x{t.Height} {t.Format} mips {t.Levels}");
        if (cmd == "ytd2dds") { Directory.CreateDirectory(a[2]); File.WriteAllBytes(Path.Combine(a[2], t.Name + ".dds"), DDSIO.GetDDSFile(t)); }
      }
    }
    return 0;
  }
}
