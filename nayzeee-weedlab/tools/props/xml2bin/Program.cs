// Converts every *.ydr.xml / *.ytd.xml / *.ytyp.xml in <in dir> to binary files in <out dir>,
// then loads every binary back through CodeWalker and checks that each texture a model
// uses exists in the shared texture dictionary (non-embedded textures).
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
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

// texture dictionaries
var textures = new HashSet<string>();
foreach (var path in Directory.GetFiles(outDir, "*.ytd"))
{
    var ytd = new YtdFile();
    try
    {
        RpfFile.LoadResourceFile(ytd, File.ReadAllBytes(path), 13);
        var list = ytd.TextureDict?.Textures?.data_items ?? Array.Empty<Texture>();
        foreach (var t in list) textures.Add(t.Name.ToLowerInvariant());
        Console.WriteLine($"CHECK {Path.GetFileName(path)}: {list.Length} textures");
        if (list.Length == 0) fails++;
    }
    catch (Exception e) { fails++; Console.WriteLine($"CHECK FAIL {Path.GetFileName(path)}: {e.Message}"); }
}

// drawables
foreach (var path in Directory.GetFiles(outDir, "*.ydr"))
{
    var ydr = new YdrFile();
    try
    {
        RpfFile.LoadResourceFile(ydr, File.ReadAllBytes(path), 165);
        var d = ydr.Drawable;
        int models = d?.DrawableModels?.High?.Length ?? 0;
        var missing = new List<string>();
        int shaders = 0, refs = 0;
        foreach (var sh in d?.ShaderGroup?.Shaders?.data_items ?? Array.Empty<ShaderFX>())
        {
            shaders++;
            foreach (var p in sh.ParametersList?.Parameters ?? Array.Empty<ShaderParameter>())
            {
                if (p.Data is TextureBase tb && tb.Name != null)
                {
                    refs++;
                    if (!textures.Contains(tb.Name.ToLowerInvariant())) missing.Add(tb.Name);
                }
            }
        }
        Console.WriteLine($"CHECK {Path.GetFileName(path)}: models {models}, shaders {shaders}, texture refs {refs}, bounds {(d?.Bound != null ? "yes" : "no")}" +
                          (missing.Count > 0 ? $", MISSING TEXTURES {string.Join(",", missing.Distinct())}" : ""));
        if (d == null || models == 0 || refs == 0 || missing.Count > 0) fails++;
    }
    catch (Exception e) { fails++; Console.WriteLine($"CHECK FAIL {Path.GetFileName(path)}: {e.Message}"); }
}

// archetypes
foreach (var path in Directory.GetFiles(outDir, "*.ytyp"))
{
    var ytyp = new YtypFile();
    try
    {
        ytyp.Load(File.ReadAllBytes(path));
        var n = ytyp.AllArchetypes?.Length ?? 0;
        Console.WriteLine($"CHECK {Path.GetFileName(path)}: {n} archetypes");
        foreach (var a in ytyp.AllArchetypes ?? Array.Empty<Archetype>())
            if (!File.Exists(Path.Combine(outDir, a.Name + ".ydr"))) { fails++; Console.WriteLine($"  no drawable for archetype {a.Name}"); }
    }
    catch (Exception e) { fails++; Console.WriteLine($"CHECK FAIL {Path.GetFileName(path)}: {e.Message}"); }
}
Console.WriteLine(fails == 0 ? "ALL OK" : $"{fails} PROBLEM(S)");
return fails == 0 ? 0 : 2;
