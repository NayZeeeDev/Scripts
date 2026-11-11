// The hair drop folder (nayzeee-wigsnatchv2/hairstyles): hairstyles dropped there become a real female hair
// pack inside nzw_hairprops (mp_f_freemode_01_mp_f_nzw_salon), so characters can wear them, and they get
// their foam-head prop and salon slices like any other hairstyle.
//
//   hairstyles/
//   ├─ Knotless Braids/            the folder name is the hairstyle's name
//   │  ├─ hair_000_u.ydd           any name works
//   │  ├─ hair_diff_000_a_uni.ytd  texture A
//   │  └─ hair_diff_000_b_uni.ytd  texture B
//   └─ Kiki Bob/
//      ├─ mp_f_freemode_01^hair_003_u.ydd
//      └─ mp_f_freemode_01^hair_diff_003_uni.ytd
//
// Each hairstyle keeps its number in the pack (hairstyles.json), so adding or removing one never moves the
// others. Female only: files named mp_m_... are left out.

using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Xml;
using CodeWalker.GameFiles;

static partial class P
{
    public const string PackDlc = "mp_f_nzw_salon";
    const string PackPed = "mp_f_freemode_01";
    static string PackFull => $"{PackPed}_{PackDlc}";
    const int PackMax = 255;

    static readonly Regex DropNum = new(@"hair_(?:diff_)?(\d{3})", RegexOptions.IgnoreCase);
    static readonly Regex DropLetter = new(@"hair_diff_\d{3}_([a-z])(?:_|\.)", RegexOptions.IgnoreCase);
    static readonly Regex MaleFile = new(@"^mp_m_", RegexOptions.IgnoreCase);

    public class DropHair { public string Id, Label, Ydd; public List<string> Ytds = new(); public long Size, Mtime; }

    // every hairstyle in the drop folders: each folder with .ydd files in it is one hairstyle (or several)
    static List<DropHair> FindDrop(List<string> drops)
    {
        var outList = new List<DropHair>();
        foreach (var root in drops.Distinct())
        {
            if (!Directory.Exists(root)) continue;
            var dirs = new List<string> { root };
            try { dirs.AddRange(Directory.EnumerateDirectories(root, "*", SearchOption.AllDirectories)); } catch { }
            foreach (var dir in dirs.OrderBy(d => d, StringComparer.OrdinalIgnoreCase))
            {
                string[] files;
                try { files = Directory.GetFiles(dir); } catch { continue; }
                bool Has(string f) { try { return new FileInfo(f).Length > 0; } catch { return false; } }
                var ydds = files.Where(f => f.EndsWith(".ydd", StringComparison.OrdinalIgnoreCase) && !MaleFile.IsMatch(Path.GetFileName(f)))
                                .OrderBy(f => f, StringComparer.OrdinalIgnoreCase).ToList();
                var skipped = files.Where(f => f.EndsWith(".ydd", StringComparison.OrdinalIgnoreCase) && MaleFile.IsMatch(Path.GetFileName(f))).ToList();
                foreach (var f in skipped) Console.WriteLine($"drop: left out {Path.GetFileName(f)} (male, hairstyles here are female only)");
                var ytds = files.Where(f => f.EndsWith(".ytd", StringComparison.OrdinalIgnoreCase) && !MaleFile.IsMatch(Path.GetFileName(f))).ToList();
                foreach (var f in ytds.Where(f => !Has(f))) Console.WriteLine($"drop: {Path.GetFileName(f)} is empty (0 bytes), left out");
                ytds = ytds.Where(Has).ToList();
                ydds = ydds.Where(f =>
                {
                    if (Has(f)) return true;
                    Console.WriteLine($"drop: {Path.GetFileName(f)} is empty (0 bytes), left out");
                    return false;
                }).ToList();
                if (ydds.Count == 0) continue;

                var folder = Path.GetFullPath(dir).TrimEnd('/', '\\') == Path.GetFullPath(root).TrimEnd('/', '\\') ? null : Path.GetFileName(dir.TrimEnd('/', '\\'));
                for (int i = 0; i < ydds.Count; i++)
                {
                    var y = ydds[i];
                    var fi = new FileInfo(y);
                    var label = folder ?? Path.GetFileNameWithoutExtension(y);
                    if (folder != null && ydds.Count > 1) label = $"{folder} {i + 1}";
                    var h = new DropHair
                    {
                        Id = Path.GetRelativePath(root, y).Replace('\\', '/').ToLowerInvariant(),
                        Label = label.Trim(), Ydd = y, Size = fi.Length,
                        Mtime = new DateTimeOffset(fi.LastWriteTimeUtc).ToUnixTimeSeconds(),
                    };
                    // its textures: one hairstyle in the folder has them all; with several, they're paired by
                    // number (hair_003 <-> hair_diff_003) or by name (bob.ydd <-> bob_a.ytd)
                    IEnumerable<string> mine;
                    if (ydds.Count == 1) mine = ytds;
                    else
                    {
                        var num = DropNum.Match(Path.GetFileName(y));
                        var stem = Regex.Replace(Path.GetFileNameWithoutExtension(y), @"_[ur]$", "", RegexOptions.IgnoreCase);
                        mine = ytds.Where(t =>
                        {
                            var tn = DropNum.Match(Path.GetFileName(t));
                            if (num.Success && tn.Success) return num.Groups[1].Value == tn.Groups[1].Value;
                            return Path.GetFileName(t).StartsWith(stem, StringComparison.OrdinalIgnoreCase);
                        });
                    }
                    h.Ytds = mine.OrderBy(t => { var m = DropLetter.Match(Path.GetFileName(t)); return m.Success ? m.Groups[1].Value.ToLowerInvariant() : "~"; })
                                 .ThenBy(t => t, StringComparer.OrdinalIgnoreCase).Take(26).ToList();
                    foreach (var t in h.Ytds) { var ti = new FileInfo(t); h.Size += ti.Length; h.Mtime = Math.Max(h.Mtime, new DateTimeOffset(ti.LastWriteTimeUtc).ToUnixTimeSeconds()); }
                    outList.Add(h);
                }
            }
        }
        return outList;
    }

    // the pack's slots ------------------------------------------------------------------------------

    class Slot { public int N; public string Id, Label; public bool Gone; public long Size, Mtime; public int Tex; }

    static List<Slot> LoadSlots(string outDir)
    {
        var list = new List<Slot>();
        var f = Path.Combine(outDir, "hairstyles.json");
        if (!File.Exists(f)) return list;
        try
        {
            foreach (var n in JsonNode.Parse(File.ReadAllText(f))?["slots"]?.AsArray() ?? new JsonArray())
                list.Add(new Slot
                {
                    N = n["n"].GetValue<int>(), Id = n["id"]?.GetValue<string>(), Label = n["label"]?.GetValue<string>(),
                    Gone = n["gone"]?.GetValue<bool>() ?? false, Size = n["size"]?.GetValue<long>() ?? 0,
                    Mtime = n["mtime"]?.GetValue<long>() ?? 0, Tex = n["tex"]?.GetValue<int>() ?? 1,
                });
        }
        catch { }
        return list.OrderBy(s => s.N).ToList();
    }

    static void SaveSlots(string outDir, List<Slot> slots)
    {
        var arr = new JsonArray();
        foreach (var s in slots.OrderBy(s => s.N))
            arr.Add(new JsonObject { ["n"] = s.N, ["id"] = s.Id, ["label"] = s.Label, ["gone"] = s.Gone, ["size"] = s.Size, ["mtime"] = s.Mtime, ["tex"] = s.Tex });
        var root = new JsonObject
        {
            ["about"] = "Hairstyles from the hairstyles/ drop folder and their number in the pack " + PackFull + ". Made by hairkit, don't edit.",
            ["slots"] = arr,
        };
        File.WriteAllText(Path.Combine(outDir, "hairstyles.json"), root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
    }

    static string PackYdd(string outDir, int n) => Path.Combine(outDir, "stream", $"{PackFull}^hair_{n:000}_u.ydd");
    static string PackYtd(string outDir, int n, int t) => Path.Combine(outDir, "stream", $"{PackFull}^hair_diff_{n:000}_{(char)('a' + t)}_uni.ytd");

    public class PackResult
    {
        public List<Src> Srcs = new();
        public int Styles, Added, Gone, Updated;
        public bool Changed;
        public JsonObject ToJson() => new() { ["styles"] = Styles, ["added"] = Added, ["gone"] = Gone, ["updated"] = Updated };
    }

    // works out the pack from the drop folders; with write, also puts it in nzw_hairprops
    static PackResult Pack(List<string> drops, string outDir, bool write)
    {
        var r = new PackResult();
        var found = FindDrop(drops);
        var slots = LoadSlots(outDir);
        var byId = slots.Where(s => s.Id != null).ToDictionary(s => s.Id, s => s);
        var used = new HashSet<Slot>();
        var fresh = new List<(Slot slot, DropHair hair)>();
        var todo = new List<(Slot slot, DropHair hair)>();

        foreach (var h in found)
        {
            if (byId.TryGetValue(h.Id, out var s) && used.Add(s))
            {
                if (s.Gone || s.Size != h.Size || s.Mtime != h.Mtime || !File.Exists(PackYdd(outDir, s.N))) { todo.Add((s, h)); if (!s.Gone) r.Updated++; }
                if (s.Gone) r.Added++;
                s.Gone = false; s.Label = h.Label;
                continue;
            }
            fresh.Add((null, h));
        }
        foreach (var s in slots) if (!used.Contains(s) && !s.Gone) { s.Gone = true; r.Gone++; }
        // new hairstyles take a slot a removed one left, else go on the end
        foreach (var (_, h) in fresh)
        {
            var s = slots.Where(x => x.Gone && !used.Contains(x)).OrderBy(x => x.N).FirstOrDefault();
            if (s == null)
            {
                int n = slots.Count == 0 ? 0 : slots.Max(x => x.N) + 1;
                if (n >= PackMax) { Console.WriteLine($"drop: {h.Label} left out, the pack is full ({PackMax} hairstyles)"); continue; }
                s = new Slot { N = n };
                slots.Add(s);
            }
            used.Add(s);
            s.Id = h.Id; s.Label = h.Label; s.Gone = false;
            todo.Add((s, h));
            r.Added++;
        }
        // removed hairstyles at the end of the pack go; ones in the middle keep their place (and stay
        // wearable) until a new hairstyle takes it, so nobody else's hairstyle number moves
        slots = slots.OrderBy(s => s.N).ToList();
        while (slots.Count > 0 && slots[^1].Gone) slots.RemoveAt(slots.Count - 1);
        r.Styles = slots.Count(s => !s.Gone);
        r.Changed = r.Added > 0 || r.Gone > 0 || r.Updated > 0;

        var drop = found.ToDictionary(h => h.Id, h => h);
        foreach (var s in slots)
        {
            if (!s.Gone && s.Id != null && drop.TryGetValue(s.Id, out var h))
                r.Srcs.Add(new Src
                {
                    Gender = "f", Collection = PackDlc, Local = s.N, Path = h.Ydd, Ytd = h.Ytds.FirstOrDefault(),
                    Size = h.Size, Mtime = h.Mtime, Label = h.Label,
                });
            else if (File.Exists(PackYdd(outDir, s.N)))
            {
                var fi = new FileInfo(PackYdd(outDir, s.N));
                var t = PackYtd(outDir, s.N, 0);
                r.Srcs.Add(new Src
                {
                    Gender = "f", Collection = PackDlc, Local = s.N, Path = fi.FullName, Ytd = File.Exists(t) ? t : null,
                    Size = fi.Length, Mtime = new DateTimeOffset(fi.LastWriteTimeUtc).ToUnixTimeSeconds(), Label = s.Label,
                });
            }
        }
        if (!write) return r;

        Directory.CreateDirectory(Path.Combine(outDir, "stream"));
        foreach (var (s, h) in todo)
        {
            File.Copy(h.Ydd, PackYdd(outDir, s.N), true);
            for (int t = 0; t < 26; t++) { var p = PackYtd(outDir, s.N, t); if (File.Exists(p)) File.Delete(p); }
            int tex = 0;
            foreach (var y in h.Ytds) File.Copy(y, PackYtd(outDir, s.N, tex++), true);
            // no texture file with it (or only an empty one): the textures inside the .ydd go in one
            if (tex == 0 && EmbeddedYtd(h.Ydd, PackYtd(outDir, s.N, 0))) tex = 1;
            if (tex == 0) Console.WriteLine($"drop: {h.Label} has no textures at all, it may show white in game");
            else if (!HasColour(PackYtd(outDir, s.N, 0), h.Ydd))
                Console.WriteLine($"drop: {h.Label} has no colour (diffuse) texture, only normal / spec maps: the download is missing its .ytd, it may show white in game");
            s.Tex = Math.Max(1, tex); s.Size = h.Size; s.Mtime = h.Mtime;
            Console.WriteLine($"drop: {h.Label} -> {PackFull} hairstyle {s.N} ({tex} texture{(tex == 1 ? "" : "s")})");
        }
        // anything of the pack that isn't a slot any more
        foreach (var f in Directory.GetFiles(Path.Combine(outDir, "stream"), PackFull + "^*"))
        {
            var m = Regex.Match(Path.GetFileName(f), @"\^hair_(?:diff_)?(\d{3})", RegexOptions.IgnoreCase);
            if (m.Success && !slots.Any(s => s.N == int.Parse(m.Groups[1].Value))) { File.Delete(f); r.Changed = true; }
        }
        var ymt = Path.Combine(outDir, "stream", PackFull + ".ymt");
        var meta = Path.Combine(outDir, PackFull + ".meta");
        if (slots.Count > 0)
        {
            var data = PackYmt(slots);
            if (!File.Exists(ymt) || !File.ReadAllBytes(ymt).SequenceEqual(data)) { File.WriteAllBytes(ymt, data); r.Changed = true; }
            File.WriteAllText(meta,
                "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ShopPedApparel>\n" +
                $"  <pedName>{PackPed}</pedName>\n  <dlcName>{PackDlc}</dlcName>\n  <fullDlcName>{PackFull}</fullDlcName>\n" +
                "  <eCharacter>SCR_CHAR_MULTIPLAYER_F</eCharacter>\n  <pedOutfits />\n  <pedComponents />\n  <pedProps />\n</ShopPedApparel>\n");
        }
        else
        {
            if (File.Exists(ymt)) { File.Delete(ymt); r.Changed = true; }
            if (File.Exists(meta)) File.Delete(meta);
        }
        SaveSlots(outDir, slots);
        return r;
    }

    // the pack's .ymt (CPedVariationInfo): hair only, one drawable per slot, its textures
    static byte[] PackYmt(List<Slot> slots)
    {
        var sb = new System.Text.StringBuilder();
        sb.Append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<CPedVariationInfo>\n <bHasTexVariations value=\"true\" />\n <bHasDrawblVariations value=\"true\" />\n");
        sb.Append(" <bHasLowLODs value=\"false\" />\n <bIsSuperLOD value=\"false\" />\n");
        sb.Append(" <availComp>255 255 0 255 255 255 255 255 255 255 255 255</availComp>\n");
        sb.Append($" <aComponentData3 itemType=\"CPVComponentData\">\n  <Item>\n   <numAvailTex value=\"{Math.Min(255, slots.Sum(s => s.Tex))}\" />\n   <aDrawblData3 itemType=\"CPVDrawblData\">\n");
        foreach (var s in slots)
        {
            sb.Append("    <Item>\n     <propMask value=\"1\" />\n     <numAlternatives value=\"0\" />\n     <aTexData itemType=\"CPVTextureData\">\n");
            for (int t = 0; t < Math.Max(1, s.Tex); t++) sb.Append("      <Item>\n       <texId value=\"0\" />\n       <distribution value=\"255\" />\n      </Item>\n");
            sb.Append("     </aTexData>\n     <clothData>\n      <ownsCloth value=\"false\" />\n     </clothData>\n    </Item>\n");
        }
        sb.Append("   </aDrawblData3>\n  </Item>\n </aComponentData3>\n <aSelectionSets itemType=\"CPedSelectionSet\" />\n <compInfos itemType=\"CComponentInfo\">\n");
        foreach (var s in slots)
            sb.Append("  <Item>\n   <pedXml_audioID>none</pedXml_audioID>\n   <pedXml_audioID2>none</pedXml_audioID2>\n   <pedXml_expressionMods>0 0 0 0 0</pedXml_expressionMods>\n" +
                      "   <flags value=\"0\" />\n   <inclusions>0</inclusions>\n   <exclusions>0</exclusions>\n   <pedXml_vfxComps>PV_COMP_HEAD</pedXml_vfxComps>\n" +
                      $"   <pedXml_flags value=\"0\" />\n   <pedXml_compIdx value=\"2\" />\n   <pedXml_drawblIdx value=\"{s.N}\" />\n  </Item>\n");
        sb.Append(" </compInfos>\n <propInfo>\n  <numAvailProps value=\"0\" />\n  <aPropMetaData itemType=\"CPedPropMetaData\" />\n  <aAnchors itemType=\"CAnchorProps\" />\n </propInfo>\n");
        sb.Append($" <dlcName>{PackDlc}</dlcName>\n</CPedVariationInfo>\n");
        var doc = new XmlDocument(); doc.LoadXml(sb.ToString());
        var data = XmlMeta.GetData(doc, MetaFormat.RSC, ".");
        var back = new YmtFile(); back.Load(data);   // must load back
        if (back.Meta == null) throw new Exception("the hair pack .ymt did not load back");
        return data;
    }

    // whether a hairstyle has its colour texture, in its .ytd or inside the .ydd
    static bool HasColour(string ytdPath, string yddPath)
    {
        try
        {
            var ytd = new YtdFile(); ytd.Load(File.ReadAllBytes(ytdPath));
            var ydd = new YddFile(); ydd.Load(File.ReadAllBytes(yddPath));
            return PickDiffuse(ytd, ydd) != null;
        }
        catch { return true; }
    }

    // a .ytd made of the textures embedded in a .ydd
    static bool EmbeddedYtd(string yddPath, string ytdPath)
    {
        try
        {
            var ydd = new YddFile(); ydd.Load(File.ReadAllBytes(yddPath));
            var texs = new List<CodeWalker.GameFiles.Texture>();
            var seen = new HashSet<uint>();
            foreach (var d in ydd.Drawables ?? Array.Empty<Drawable>())
                foreach (var t in d.ShaderGroup?.TextureDictionary?.Textures?.data_items ?? Array.Empty<CodeWalker.GameFiles.Texture>())
                    if (t != null && seen.Add(t.NameHash)) texs.Add(t);
            if (texs.Count == 0) return false;
            var td = new TextureDictionary();
            td.BuildFromTextureList(texs);
            var ytd = new YtdFile { TextureDict = td };
            var data = ytd.Save();
            var back = new YtdFile(); back.Load(data);
            if (back.TextureDict?.Textures?.data_items == null) return false;
            File.WriteAllBytes(ytdPath, data);
            return true;
        }
        catch (Exception e) { Console.WriteLine("drop: couldn't take the textures out of " + Path.GetFileName(yddPath) + ": " + e.Message); return false; }
    }
}
