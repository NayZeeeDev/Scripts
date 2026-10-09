using System.Numerics;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;
using CodeWalker.GameFiles;

namespace NayzeeeSneakerStudio;

sealed class Colour
{
    public string Letter { get; set; } = "a";
    public string Name { get; set; } = "";
}

/// <summary>One shoe in catalogue.json, which nayzeee-sneakers reads in game.</summary>
sealed class CatalogueShoe
{
    public string Id { get; set; } = "";
    public string Key { get; set; } = "";
    public string Label { get; set; } = "";
    public string Gender { get; set; } = "";
    public string Ped { get; set; } = "";
    public string Collection { get; set; } = "";
    public int Drawable { get; set; }
    public bool Skin { get; set; }
    public bool Loose { get; set; }
    public string Box { get; set; } = "shoe";
    public float Scale { get; set; } = 1f;
    public float[] Size { get; set; } = Array.Empty<float>();
    public List<Colour> Colours { get; set; } = new();
    public string Source { get; set; } = "";
    public string Hash { get; set; } = "";
    public string Converted { get; set; } = "";
}

sealed class Catalogue
{
    public int Version { get; set; } = 1;
    public string Generated { get; set; } = "";
    public List<CatalogueShoe> Shoes { get; set; } = new();

    public static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
    };

    public static Catalogue Load(string path)
    {
        try { return File.Exists(path) ? JsonSerializer.Deserialize<Catalogue>(File.ReadAllText(path), Json) ?? new() : new(); }
        catch { return new(); }
    }
}

sealed class Options
{
    public int TextureSize { get; set; } = 512;
    public int MaxTriangles { get; set; } = 24000;
    public int IconSize { get; set; } = 256;
}

/// <summary>The three box sizes of nayzeee-sneakers, loaded from its own box props.</summary>
sealed class BoxModel
{
    public string Type = "";
    public Mesh Base = null!, Lid = null!;
    public Rgba?[] BaseTex = Array.Empty<Rgba?>(), LidTex = Array.Empty<Rgba?>();
    public Vector3 Hinge;
    public Vector3 Inside;   // usable space inside (x long side, y short side, z height)
}

static class Studio
{
    public const float Floor = 0.0045f, OpenAngle = 105f;

    static readonly Dictionary<string, (string baseName, string lidName, Vector3 hinge)> BoxDefs = new()
    {
        ["shoe"] = ("nzs_box", "nzs_box_lid", new Vector3(0f, -0.145f, 0.2f)),
        ["heel"] = ("nzs_box_heel", "nzs_box_heel_lid", new Vector3(0f, -0.15f, 0.12f)),
        ["boot"] = ("nzs_box_boot", "nzs_box_boot_lid", new Vector3(0f, -0.255f, 0.16f)),
    };

    static Dictionary<string, BoxModel>? boxes;

    static Mesh LoadYdr(string name, out Rgba?[] tex)
    {
        var asm = Assembly.GetExecutingAssembly();
        var res = asm.GetManifestResourceNames().First(r => r.EndsWith(name + ".ydr", StringComparison.OrdinalIgnoreCase));
        using var st = asm.GetManifestResourceStream(res)!;
        using var ms = new MemoryStream();
        st.CopyTo(ms);
        var ydr = RpfFile.GetResourceFile<YdrFile>(ms.ToArray());
        var mesh = Geometry.Read(ydr.Drawable, out _, 200000);
        tex = mesh.Mats.Select(m => m.Embedded != null ? Textures.Pixels(m.Embedded, Textures.LevelFor(m.Embedded, 512)) : null).ToArray();
        return mesh;
    }

    public static Dictionary<string, BoxModel> Boxes()
    {
        if (boxes != null) return boxes;
        boxes = new();
        foreach (var (type, def) in BoxDefs)
        {
            var b = new BoxModel { Type = type, Hinge = def.hinge };
            b.Base = LoadYdr(def.baseName, out b.BaseTex);
            b.Lid = LoadYdr(def.lidName, out b.LidTex);
            var (lo, hi) = b.Base.Bounds();
            b.Inside = (hi - lo) - new Vector3(0.016f, 0.016f, 0.012f);
            boxes[type] = b;
        }
        return boxes;
    }

    // ------------------------------------------------------------ colour names

    static readonly (string name, float r, float g, float b)[] Palette =
    {
        ("Black", 18, 18, 20), ("Charcoal", 58, 60, 64), ("Grey", 125, 127, 130), ("Silver", 190, 192, 196), ("White", 242, 242, 240),
        ("Cream", 238, 228, 202), ("Beige", 214, 194, 160), ("Tan", 190, 148, 100), ("Brown", 105, 68, 40), ("Mocha", 140, 106, 86),
        ("Red", 200, 32, 34), ("Maroon", 108, 22, 32), ("Pink", 240, 160, 190), ("Hot Pink", 236, 52, 142), ("Orange", 240, 128, 30),
        ("Yellow", 246, 214, 50), ("Gold", 198, 164, 62), ("Lime", 172, 222, 58), ("Olive", 108, 112, 48), ("Green", 40, 150, 62), ("Mint", 162, 228, 192),
        ("Teal", 22, 140, 138), ("Sky Blue", 132, 190, 234), ("Blue", 40, 92, 200), ("Navy", 26, 36, 80), ("Purple", 118, 58, 160),
        ("Lilac", 190, 162, 222),
    };

    static (float L, float A, float B) Lab(float r, float g, float b)
    {
        static float Lin(float c) { c /= 255f; return c <= 0.04045f ? c / 12.92f : MathF.Pow((c + 0.055f) / 1.055f, 2.4f); }
        float R = Lin(r), G = Lin(g), Bl = Lin(b);
        float x = (R * 0.4124f + G * 0.3576f + Bl * 0.1805f) / 0.95047f;
        float y = R * 0.2126f + G * 0.7152f + Bl * 0.0722f;
        float z = (R * 0.0193f + G * 0.1192f + Bl * 0.9505f) / 1.08883f;
        static float F(float t) => t > 0.008856f ? MathF.Cbrt(t) : 7.787f * t + 16f / 116f;
        float fx = F(x), fy = F(y), fz = F(z);
        return (116f * fy - 16f, 500f * (fx - fy), 200f * (fy - fz));
    }

    static readonly (string name, float L, float A, float B)[] PaletteLab =
        Palette.Select(p => { var l = Lab(p.r, p.g, p.b); return (p.name, l.L, l.A, l.B); }).ToArray();

    static string Nearest(float r, float g, float b)
    {
        var (L, A, B) = Lab(r, g, b);
        // clothing textures are often muted; lift weak colour so a pale mint reads as mint, not silver
        float chroma = MathF.Sqrt(A * A + B * B);
        if (chroma > 3f)
        {
            float boost = 1f + 1.5f * MathF.Exp(-chroma / 25f);
            A *= boost; B *= boost;
        }
        string best = "Grey"; float bd = float.MaxValue;
        foreach (var p in PaletteLab)
        {
            // lightness counts a bit less than hue, so a pale mint stays mint
            float d = 0.6f * (L - p.L) * (L - p.L) + (A - p.A) * (A - p.A) + (B - p.B) * (B - p.B);
            if (d < bd) { bd = d; best = p.name; }
        }
        return best;
    }

    /// <summary>
    /// "Black" or "Black / Red" for each colourway, from the shoe's surface. Parts that look the same in
    /// every colourway (soles, linings) count for little, so the name follows what changes between them.
    /// </summary>
    static List<string> NameColours(Mesh m, List<Rgba?[]> perColour)
    {
        int nt = m.Tris, nc = perColour.Count;
        var area = new float[nt];
        var col = new (float r, float g, float b, bool ok)[nc, nt];
        for (int t = 0; t < nt; t++)
        {
            var a = m.P[m.I[t * 3]]; var b = m.P[m.I[t * 3 + 1]]; var c = m.P[m.I[t * 3 + 2]];
            area[t] = Vector3.Cross(b - a, c - a).Length() / 2;
            var uv = (m.T[m.I[t * 3]] + m.T[m.I[t * 3 + 1]] + m.T[m.I[t * 3 + 2]]) / 3;
            for (int k = 0; k < nc; k++)
            {
                var img = perColour[k].Length > m.M[t] ? perColour[k][m.M[t]] : null;
                if (img == null) continue;
                var px = img.At(uv.X, uv.Y);
                col[k, t] = (px.r, px.g, px.b, px.a >= 64);
            }
        }
        var names = new List<string>();
        for (int k = 0; k < nc; k++)
        {
            var score = new Dictionary<string, float>();
            for (int t = 0; t < nt; t++)
            {
                if (!col[k, t].ok) continue;
                float w = area[t];
                if (nc > 1)
                {
                    float spread = 0;
                    for (int o = 0; o < nc; o++)
                    {
                        if (o == k || !col[o, t].ok) continue;
                        float dr = col[k, t].r - col[o, t].r, dg = col[k, t].g - col[o, t].g, db = col[k, t].b - col[o, t].b;
                        spread = MathF.Max(spread, MathF.Sqrt(dr * dr + dg * dg + db * db));
                    }
                    float sp = MathF.Min(1f, spread / 60f);
                    w *= 0.004f + sp * sp;
                }
                // colourful bits say more about a colourway than black, white and grey
                float mx = MathF.Max(col[k, t].r, MathF.Max(col[k, t].g, col[k, t].b)), mn = MathF.Min(col[k, t].r, MathF.Min(col[k, t].g, col[k, t].b));
                float sat = mx <= 0 ? 0 : (mx - mn) / mx;
                w *= 1f + 1.5f * sat * MathF.Min(1f, mx / 90f);
                var n = Nearest(col[k, t].r, col[k, t].g, col[k, t].b);
                score[n] = score.GetValueOrDefault(n) + w;
            }
            if (score.Count == 0) { names.Add("Colour"); continue; }
            var top = score.OrderByDescending(kv => kv.Value).ToList();
            if (Environment.GetEnvironmentVariable("NZS_DEBUG") == "1")
                Console.WriteLine($"   colour {k}: " + string.Join(", ", top.Take(5).Select(kv => $"{kv.Key} {kv.Value / top.Sum(x => x.Value):0.00}")));
            float total = top.Sum(kv => kv.Value);
            names.Add(top.Count > 1 && top[1].Value / total > 0.24f ? $"{top[0].Key} / {top[1].Key}" : top[0].Key);
        }
        return names;
    }

    // ------------------------------------------------------------ conversion

    sealed class Loaded
    {
        public Mesh Mesh = null!;
        public string Lod = "";
        public SortedDictionary<char, Texture?[]> PerColour = new();   // letter -> texture per material
        public int Dropped;
        public string Reduced = "";
    }

    static Loaded Load(ShoeSource s, Options o)
    {
        var ydd = RpfFile.GetResourceFile<YddFile>(File.ReadAllBytes(s.YddPath));
        var d = ydd?.Drawables?.FirstOrDefault(x => x?.DrawableModels != null) ?? throw new Exception("couldn't read the .ydd");
        // the most detailed LOD that isn't far over budget; reduced to the budget after cleaning
        var mesh = Geometry.Read(d, out var lod, o.MaxTriangles * 3);
        var l = new Loaded { Mesh = mesh, Lod = lod };

        var letters = s.Textures.Count > 0 ? s.Textures.Keys.ToList() : new List<char> { 'a' };
        foreach (var letter in letters)
        {
            Texture[] inYtd = Array.Empty<Texture>();
            if (s.Textures.TryGetValue(letter, out var path))
            {
                var ytd = RpfFile.GetResourceFile<YtdFile>(File.ReadAllBytes(path));
                inYtd = ytd?.TextureDict?.Textures?.data_items ?? Array.Empty<Texture>();
            }
            var perMat = new Texture?[mesh.Mats.Count];
            for (int i = 0; i < mesh.Mats.Count; i++)
            {
                // like the game: the colourway's .ytd is the diffuse, whatever the .ydd has inside it
                // (decals keep their own texture)
                var mat = mesh.Mats[i];
                var fromYtd = inYtd.FirstOrDefault(t => string.Equals(t.Name, mat.Diffuse, StringComparison.OrdinalIgnoreCase))
                              ?? (inYtd.Length > 0 ? inYtd[0] : null);
                perMat[i] = mat.Decal && mat.Embedded != null ? mat.Embedded : fromYtd ?? mat.Embedded;
            }
            l.PerColour[letter] = perMat;
        }
        // clean against the first colourway
        var reference = l.PerColour.First().Value.Select(t => t == null ? null : Textures.Pixels(t, Textures.LevelFor(t, 1024))).ToArray();
        l.Mesh = Geometry.Clean(mesh, reference, s.Skin, out l.Dropped);
        if (l.Mesh.Tris > o.MaxTriangles)
        {
            int before = l.Mesh.Tris;
            l.Mesh = Simplify.Run(l.Mesh, o.MaxTriangles);
            l.Reduced = $"reduced {before} -> {l.Mesh.Tris} triangles";
        }
        return l;
    }

    /// <summary>
    /// Packs the pair for the smallest box it fits. Low shoes go upright in a shoe box; anything taller
    /// lies on its side in a heel or boot box. Shrinks it up to 10% rather than going up a box size, and to 85% at most when nothing fits.
    /// </summary>
    public static Mesh Pack(Mesh pair, string? forceBox, bool heels, out string box, out float scale, out Vector3 size)
    {
        var bx = Boxes();
        var flat = LongSideX(Geometry.Arrange(pair.Subset(Enumerable.Range(0, pair.Tris)), false, out var flatSize), ref flatSize);
        var side = LongSideX(Geometry.Arrange(pair.Subset(Enumerable.Range(0, pair.Tris)), true, out var sideSize), ref sideSize);
        float Fit(Vector3 sz, string type)
        {
            var inside = bx[type].Inside;
            return MathF.Min(inside.X / sz.X, MathF.Min(inside.Y / sz.Y, inside.Z / sz.Z));
        }
        if (Environment.GetEnvironmentVariable("NZS_DEBUG") == "1")
            Console.WriteLine($"   flat {flatSize}  side {sideSize}  inside shoe {bx["shoe"].Inside} heel {bx["heel"].Inside} boot {bx["boot"].Inside}");
        var options = new List<(string type, bool sideways)>();
        if (forceBox != null && bx.ContainsKey(forceBox)) options.Add((forceBox, forceBox != "shoe"));
        else
        {
            // open-toe heels and sandals (skin-tone drawables) go in a heel box when they fit one
            if (heels) { options.Add(("heel", true)); options.Add(("heel", false)); }
            options.Add(("shoe", false));
            options.Add(("heel", false));
            options.Add(("heel", true));
            options.Add(("boot", true));
            options.Add(("boot", false));
        }
        foreach (var (type, sideways) in options)
        {
            var sz = sideways ? sideSize : flatSize;
            float fit = Fit(sz, type);
            if (fit >= 0.9f || forceBox != null)
            {
                box = type;
                scale = MathF.Min(1f, MathF.Max(fit, forceBox != null ? 0.5f : 0.9f));
                var m = sideways ? side : flat;
                if (scale < 1f) m.Scale(scale);
                size = sz * scale;
                return m;
            }
        }
        // nothing fits: boot box, side by side, shrunk to fit
        box = "boot";
        float f = MathF.Max(0.85f, Fit(sideSize, "boot"));
        scale = MathF.Min(1f, f);
        side.Scale(scale);
        size = sideSize * scale;
        return side;
    }

    /// <summary>The boxes are longest along X: turn the packed pair to match.</summary>
    static Mesh LongSideX(Mesh m, ref Vector3 size)
    {
        if (size.Y <= size.X) return m;
        m.Rotate(Matrix4x4.CreateRotationZ(MathF.PI / 2));
        size = new Vector3(size.Y, size.X, size.Z);
        return m;
    }

    static Matrix4x4 LidMatrix(BoxModel b, float angleDeg) =>
        Matrix4x4.CreateRotationX(angleDeg * MathF.PI / 180f) * Matrix4x4.CreateTranslation(b.Hinge);

    /// <summary>Loose pair icon: the packed pair seen from the front, three-quarter.</summary>
    public static Rgba LooseIcon(Mesh packed, Rgba?[] tex, int size) =>
        Renderer.Icon(new[] { new RenderItem { Mesh = packed, Textures = tex } }, new Vector3(0.55f, 0.85f, -0.62f), size);

    /// <summary>Boxed icon: the box open, lid back, the pair inside.</summary>
    public static Rgba BoxIcon(Mesh packed, Rgba?[] tex, string boxType, int size)
    {
        var b = Boxes()[boxType];
        var items = new List<RenderItem>
        {
            new() { Mesh = b.Base, Textures = b.BaseTex },
            new() { Mesh = b.Lid, Textures = b.LidTex, World = LidMatrix(b, OpenAngle) },
            new() { Mesh = packed, Textures = tex, World = Matrix4x4.CreateTranslation(0, 0, Floor) },
        };
        return Renderer.Icon(items, new Vector3(-0.62f, -0.7f, -1.05f), size);
    }

    /// <summary>Quick preview of a shoe for the app: the worn pair standing.</summary>
    public static Rgba Preview(ShoeSource s, Options o, int size = 192)
    {
        var l = Load(s, o);
        var first = l.PerColour.First().Value;
        var tex = first.Select(t => t == null ? null : Textures.Pixels(t, Textures.LevelFor(t, 512))).ToArray();
        var standing = Geometry.Standing(l.Mesh);
        return Renderer.Icon(new[] { new RenderItem { Mesh = standing, Textures = tex } }, new Vector3(0.6f, 0.8f, -0.45f), size);
    }

    /// <summary>
    /// Converts one shoe: a prop per colourway (packed for its box, texture embedded, with collision),
    /// a .ytyp for them, and two inventory icons per colourway.
    /// </summary>
    public static CatalogueShoe Convert(ShoeSource s, string outRoot, Options o, string? forceBox, string label, Action<string> log)
    {
        var l = Load(s, o);
        if (l.Dropped > 0) log($"  removed {l.Dropped} skin / see-through triangles");
        if (l.Reduced.Length > 0) log("  " + l.Reduced);
        var packed = Pack(l.Mesh, forceBox, s.Skin, out var box, out var scale, out var size);
        log($"  {l.Mesh.Tris} triangles ({l.Lod} LOD) -> {box} box{(scale < 0.999f ? $", shrunk to {scale * 100:0}%" : "")}");

        var streamDir = Path.Combine(outRoot, "stream", s.Id);
        var iconDir = Path.Combine(outRoot, "icons");
        var tempDir = Path.Combine(Path.GetTempPath(), "nzs-studio-" + Guid.NewGuid().ToString("N")[..8]);
        if (Directory.Exists(streamDir)) Directory.Delete(streamDir, true);
        Directory.CreateDirectory(streamDir);
        Directory.CreateDirectory(iconDir);
        Directory.CreateDirectory(tempDir);

        var entry = new CatalogueShoe
        {
            Id = s.Id, Key = s.Key, Label = label, Gender = s.Gender, Ped = s.Ped, Collection = s.Collection,
            Drawable = s.Drawable, Skin = s.Skin, Loose = s.Loose, Box = box, Scale = MathF.Round(scale, 3),
            Size = new[] { MathF.Round(size.X, 3), MathF.Round(size.Y, 3), MathF.Round(size.Z, 3) },
            Source = s.Folder, Hash = s.Hash, Converted = DateTime.UtcNow.ToString("u"),
        };
        var props = new List<(string, Mesh)>();
        var names = new Dictionary<string, int>();
        var allPix = new List<Rgba?[]>();
        try
        {
            foreach (var (letter, texs) in l.PerColour)
            {
                var prop = $"nzs_{s.Id}_{letter}";
                var pt = new PropTexture[packed.Mats.Count];
                var pix = new Rgba?[packed.Mats.Count];
                var byTex = new Dictionary<Texture, PropTexture>();
                for (int i = 0; i < pt.Length; i++)
                {
                    var t = texs[i];
                    if (t == null)
                    {
                        // nothing to show: a plain grey texture
                        var grey = new Rgba(8, 8, Enumerable.Repeat((byte)150, 8 * 8 * 4).ToArray());
                        var dds = Textures.Uncompressed(grey, out var gf, out var gw, out var gh, out var gl);
                        pt[i] = new PropTexture { Name = $"{prop}_grey", Dds = dds, Format = gf, W = gw, H = gh, Levels = gl };
                        continue;
                    }
                    if (!byTex.TryGetValue(t, out var p))
                    {
                        var dds = Textures.PropDds(t, o.TextureSize, out var f, out var w, out var h, out var lv);
                        p = new PropTexture { Name = $"{prop}_d{byTex.Count}", Dds = dds, Format = f, W = w, H = h, Levels = lv };
                        byTex[t] = p;
                    }
                    pt[i] = p;
                    pix[i] = Textures.Pixels(t, Textures.LevelFor(t, 512));
                }
                File.WriteAllBytes(Path.Combine(streamDir, prop + ".ydr"), PropWriter.Ydr(prop, packed, pt, tempDir));
                props.Add((prop, packed));

                File.WriteAllBytes(Path.Combine(iconDir, prop + ".png"), Textures.Png(LooseIcon(packed, pix, o.IconSize)));
                File.WriteAllBytes(Path.Combine(iconDir, prop + "_box.png"), Textures.Png(BoxIcon(packed, pix, box, o.IconSize)));

                allPix.Add(pix);
                entry.Colours.Add(new Colour { Letter = letter.ToString() });
            }
            var auto = NameColours(packed, allPix);
            for (int k = 0; k < entry.Colours.Count; k++)
            {
                var cname = auto[k];
                names[cname] = names.GetValueOrDefault(cname) + 1;
                entry.Colours[k].Name = names[cname] > 1 ? $"{cname} {names[cname]}" : cname;
                log($"  nzs_{s.Id}_{entry.Colours[k].Letter}  {entry.Colours[k].Name}");
            }
            File.WriteAllBytes(Path.Combine(streamDir, $"nzs_{s.Id}.ytyp"), PropWriter.Ytyp($"nzs_{s.Id}", props));
        }
        finally
        {
            try { Directory.Delete(tempDir, true); } catch { }
        }
        return entry;
    }

    // ------------------------------------------------------------ the output resource

    public static void WriteResource(string outRoot, Catalogue cat)
    {
        Directory.CreateDirectory(outRoot);
        cat.Generated = DateTime.UtcNow.ToString("u");
        cat.Shoes = cat.Shoes.OrderBy(s => s.Gender).ThenBy(s => s.Label).ToList();
        File.WriteAllText(Path.Combine(outRoot, "catalogue.json"), JsonSerializer.Serialize(cat, Catalogue.Json));

        var ytyps = cat.Shoes.Select(s => $"stream/{s.Id}/nzs_{s.Id}.ytyp")
                             .Where(p => File.Exists(Path.Combine(outRoot, p))).ToList();
        var fx = new System.Text.StringBuilder();
        fx.AppendLine("--[[");
        fx.AppendLine("    nayzeee-sneakers-props  |  NayZeee Development");
        fx.AppendLine("    Made by NayZeee Sneaker Studio from the shoes on this server. Re-run the studio after adding or");
        fx.AppendLine("    removing clothing packs; it rewrites this file. Start it before nayzeee-sneakers.");
        fx.AppendLine("]]");
        fx.AppendLine();
        fx.AppendLine("fx_version 'cerulean'");
        fx.AppendLine("game 'gta5'");
        fx.AppendLine();
        fx.AppendLine("name 'nayzeee-sneakers-props'");
        fx.AppendLine("author 'NayZeee'");
        fx.AppendLine("description 'Shoe props made by NayZeee Sneaker Studio'");
        fx.AppendLine($"version '{DateTime.UtcNow:yyyy.M.d}'");
        fx.AppendLine();
        fx.AppendLine("files {");
        fx.AppendLine("    'catalogue.json',");
        fx.AppendLine("    'icons/*.png',");
        foreach (var y in ytyps) fx.AppendLine($"    '{y}',");
        fx.AppendLine("}");
        fx.AppendLine();
        foreach (var y in ytyps) fx.AppendLine($"data_file 'DLC_ITYP_REQUEST' '{y}'");
        File.WriteAllText(Path.Combine(outRoot, "fxmanifest.lua"), fx.ToString());

        File.WriteAllText(Path.Combine(outRoot, "README.txt"),
$@"nayzeee-sneakers-props
======================

Made by NayZeee Sneaker Studio from the shoe clothing on your server: {cat.Shoes.Count} shoes,
{cat.Shoes.Sum(s => s.Colours.Count)} colourways.

  stream/<shoe>/      one prop per colourway (nzs_<shoe>_<letter>.ydr) and a .ytyp
  icons/              inventory icons: nzs_<shoe>_<letter>.png and _box.png
  catalogue.json      what nayzeee-sneakers reads: names, colourways, which drawable each shoe is, box size

1. Put this folder in your resources and start it before nayzeee-sneakers:
     ensure nayzeee-sneakers-props
     ensure nayzeee-sneakers
2. Copy icons/*.png into your inventory's images folder (the studio can do this for you).
3. Restart, then open the in-game studio (/sneakerstudio) to price them and switch them on.

Added or removed clothing? Run the studio again. It only converts what's new or changed and
removes props for shoes that are gone.
");
    }
}
