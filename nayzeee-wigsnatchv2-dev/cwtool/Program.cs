using System;
using System.IO;
using System.Xml;
using CodeWalker.GameFiles;

// cwtool ydr2xml <in.ydr> <outdir> | xml2ydr <in.xml> <texdir> <out.ydr> | ytyp2xml <in.ytyp> <out.xml> | xml2ytyp <in.xml> <out.ytyp>
var cmd = args[0];
switch (cmd) {
  case "ydr2xml": {
    var y = new YdrFile();
    y.Load(File.ReadAllBytes(args[1]));
    Directory.CreateDirectory(args[2]);
    var xml = YdrXml.GetXml(y, args[2]);
    File.WriteAllText(Path.Combine(args[2], Path.GetFileNameWithoutExtension(args[1]) + ".ydr.xml"), xml);
    Console.WriteLine("ok " + (y.Drawable?.Name ?? "?"));
    break;
  }
  case "xml2ydr": {
    var y = XmlYdr.GetYdr(File.ReadAllText(args[1]), args[2]);
    var data = y.Save();
    File.WriteAllBytes(args[3], data);
    // round trip: load what we wrote
    var back = new YdrFile();
    back.Load(data);
    var d = back.Drawable;
    int geoms = 0, verts = 0, tris = 0;
    foreach (var m in d.DrawableModels?.High ?? new DrawableModel[0])
      foreach (var g in m.Geometries ?? new DrawableGeometry[0]) { geoms++; verts += (int)g.VerticesCount; tris += (int)(g.IndicesCount / 3); }
    var texs = d.ShaderGroup?.TextureDictionary?.Textures?.data_items?.Length ?? 0;
    Console.WriteLine($"ok {args[3]} bytes={data.Length} name={d.Name} geoms={geoms} verts={verts} tris={tris} textures={texs} r={d.BoundingSphereRadius}");
    break;
  }
  case "ydd2xml": {
    var y = new YddFile();
    y.Load(File.ReadAllBytes(args[1]));
    Directory.CreateDirectory(args[2]);
    File.WriteAllText(Path.Combine(args[2], Path.GetFileNameWithoutExtension(args[1]) + ".ydd.xml"), YddXml.GetXml(y, args[2]));
    Console.WriteLine("ok drawables=" + (y.Drawables?.Length ?? 0));
    break;
  }
  case "ytd2dds": {
    var y = new YtdFile();
    y.Load(File.ReadAllBytes(args[1]));
    Directory.CreateDirectory(args[2]);
    foreach (var t in y.TextureDict.Textures.data_items) {
      File.WriteAllBytes(Path.Combine(args[2], t.Name + ".dds"), CodeWalker.Utils.DDSIO.GetDDSFile(t));
      Console.WriteLine($"tex {t.Name} {t.Width}x{t.Height} {t.Format} mips={t.Levels}");
    }
    break;
  }
  case "ytyp2xml": {
    var y = new YtypFile();
    y.Load(File.ReadAllBytes(args[1]));
    File.WriteAllText(args[2], MetaXml.GetXml(y, out string fn));
    Console.WriteLine("ok " + fn);
    break;
  }
  case "xml2ytyp": {
    var doc = new XmlDocument();
    doc.LoadXml(File.ReadAllText(args[1]));
    var data = XmlMeta.GetData(doc, MetaFormat.RSC, Path.GetDirectoryName(Path.GetFullPath(args[1])));
    File.WriteAllBytes(args[2], data);
    var back = new YtypFile();
    back.Load(data);
    foreach (var a in back.AllArchetypes) Console.WriteLine($"ok archetype {a.Name} txd={a._BaseArchetypeDef.textureDictionary} lod={a._BaseArchetypeDef.lodDist} r={a._BaseArchetypeDef.bsRadius}");
    break;
  }
}
