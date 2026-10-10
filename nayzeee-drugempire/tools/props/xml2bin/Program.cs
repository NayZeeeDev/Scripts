// Converts every *.ydr.xml / *.ytyp.xml in <in dir> to binary files in <out dir>.
// Texture folders sit next to each ydr.xml (Sollumz / CodeWalker layout).
using System;
using System.IO;
using System.Xml;
using CodeWalker.GameFiles;

if (args.Length < 2)
{
    Console.WriteLine("usage: xml2bin <in dir> <out dir>");
    return 1;
}
string inDir = Path.GetFullPath(args[0]), outDir = Path.GetFullPath(args[1]);
Directory.CreateDirectory(outDir);
int fails = 0;

foreach (var path in Directory.GetFiles(inDir, "*.xml"))
{
    var file = Path.GetFileName(path);
    var format = XmlMeta.GetXMLFormat(file.ToLowerInvariant(), out int trim);
    var name = file.Substring(0, file.Length - trim);
    var doc = new XmlDocument();
    doc.LoadXml(File.ReadAllText(path));
    var folder = Path.Combine(inDir, Path.GetFileNameWithoutExtension(name));
    byte[] data = null;
    try { data = XmlMeta.GetData(doc, format, folder); }
    catch (Exception e) { Console.WriteLine($"FAIL {file}: {e.Message}"); }
    if (data == null) { fails++; Console.WriteLine($"FAIL {file}"); continue; }
    File.WriteAllBytes(Path.Combine(outDir, name), data);
    Console.WriteLine($"OK   {name} ({data.Length} bytes, {format})");
}
// load every .ydr back through CodeWalker to make sure the game format round-trips
foreach (var path in Directory.GetFiles(outDir, "*.ydr"))
{
    var ydr = new YdrFile();
    try
    {
        RpfFile.LoadResourceFile(ydr, File.ReadAllBytes(path), 165);
        var d = ydr.Drawable;
        int tex = d?.ShaderGroup?.TextureDictionary?.Textures?.data_items?.Length ?? 0;
        int models = d?.DrawableModels?.High?.Length ?? 0;
        Console.WriteLine($"CHECK {Path.GetFileName(path)}: models {models}, embedded textures {tex}, bounds {(d?.Bound != null ? "yes" : "no")}");
        if (d == null || models == 0) fails++;
    }
    catch (Exception e) { fails++; Console.WriteLine($"CHECK FAIL {Path.GetFileName(path)}: {e.Message}"); }
}
return fails == 0 ? 0 : 2;
