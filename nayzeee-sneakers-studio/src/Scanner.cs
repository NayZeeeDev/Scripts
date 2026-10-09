using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace NayzeeeSneakerStudio;

/// <summary>One pair of shoes found on the server: a feet drawable and its colourway textures.</summary>
sealed class ShoeSource
{
    public string Key = "";            // gender:collection:drawable, e.g. f:clothes2:002 (empty collection = base game slot)
    public string Gender = "unknown";  // male | female | unknown
    public string Ped = "";            // mp_m_freemode_01 | mp_f_freemode_01 | "" (unknown)
    public string Collection = "";     // the pack's dlc name; "" = replaces a base-game shoe
    public int Drawable;               // drawable number inside the pack
    public bool Skin;                  // _r: skin-tone drawable (bare foot showing)
    public bool Loose;                 // not named for streaming: can't be matched to a drawable automatically
    public string YddPath = "";
    public SortedDictionary<char, string> Textures = new();
    public string Resource = "";       // resource folder name
    public string Folder = "";         // path relative to the scan root
    public string Label = "";          // name guess
    public string Hash = "";           // changes when any of its files change
    public string Id = "";             // shoe id in nayzeee-sneakers (props are nzs_<id>_<letter>)
    public List<string> Notes = new();
}

static class Scanner
{
    static readonly Regex YddName = new(
        @"^(?:(?<ped>mp_[mf]_freemode_01)(?:_(?<dlc>[^\^]+))?)?\^?feet_(?<num>\d{3})_(?<kind>[ur])\.ydd$",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    static readonly HashSet<string> SkipDirs = new(StringComparer.OrdinalIgnoreCase)
        { ".git", "node_modules", "cache", "server-data-cache", "logs", "nayzeee-sneakers-props" };

    static readonly HashSet<string> Generic = new(StringComparer.OrdinalIgnoreCase)
    {
        "stream", "male", "female", "[male]", "[female]", "mp_m_freemode_01", "mp_f_freemode_01", "feet", "shoes",
        "clothing", "clothes", "[clothing]", "[clothes]", "fivem", "singleplayer", "mp", "sp", "mp male", "mp female",
        "mp famele", "optimised", "optimized", "addon", "addons", "replace", "[stream]", "files", "models",
    };

    public static string Slug(string s, int max)
    {
        var sb = new StringBuilder();
        foreach (var ch in s.ToLowerInvariant())
            sb.Append(char.IsAsciiLetterOrDigit(ch) ? ch : '_');
        var r = Regex.Replace(sb.ToString(), "_+", "_").Trim('_');
        if (r.Length > max) r = r[..max].TrimEnd('_');
        return r.Length == 0 ? "pack" : r;
    }

    static string Pretty(string s)
    {
        s = Regex.Replace(s, @"[\[\]\(\)]", " ");
        s = Regex.Replace(s, @"[_\-\.]+", " ").Trim();
        s = Regex.Replace(s, @"\s+", " ");
        return string.Join(" ", s.Split(' ').Select(w => w.Length > 1 && w.All(char.IsLower) ? char.ToUpper(w[0]) + w[1..] : w));
    }

    static string? ResourceRoot(string dir, string root)
    {
        var d = new DirectoryInfo(dir);
        var stop = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar);
        while (d != null && d.FullName.Length >= stop.Length)
        {
            if (File.Exists(Path.Combine(d.FullName, "fxmanifest.lua")) || File.Exists(Path.Combine(d.FullName, "__resource.lua")))
                return d.FullName;
            d = d.Parent;
        }
        return null;
    }

    static IEnumerable<string> Files(string root)
    {
        var stack = new Stack<string>();
        stack.Push(root);
        while (stack.Count > 0)
        {
            var dir = stack.Pop();
            string[] files = Array.Empty<string>(), dirs = Array.Empty<string>();
            try { files = Directory.GetFiles(dir); dirs = Directory.GetDirectories(dir); } catch { }
            foreach (var f in files) yield return f;
            foreach (var d in dirs)
                if (!SkipDirs.Contains(Path.GetFileName(d))) stack.Push(d);
        }
    }

    static string GuessGender(string path)
    {
        var p = path.ToLowerInvariant().Replace('\\', '/');
        if (Regex.IsMatch(p, @"(female|famele|women|woman|mp_f_|\bf\b|\[f\])")) return "female";
        if (Regex.IsMatch(p, @"(\bmale\b|\[male\]|/male|men\b|mp_m_)")) return "male";
        return "unknown";
    }

    public static List<ShoeSource> Scan(string root, Action<string>? log = null) => ScanRoots(new[] { root }, log);

    /// <summary>Scans several folders (the server passes one per started resource) as one server.</summary>
    public static List<ShoeSource> ScanRoots(IEnumerable<string> roots, Action<string>? log = null)
    {
        var list = roots.Where(r => !string.IsNullOrWhiteSpace(r)).Select(r => Path.GetFullPath(r.Trim()))
                        .Where(Directory.Exists).Distinct().ToList();
        var found = new List<ShoeSource>();
        var seen = new Dictionary<string, ShoeSource>();
        foreach (var root in list) ScanOne(root, found, seen);

        // labels shared by several shoes get their number, so they can be told apart
        foreach (var grp in found.GroupBy(f => f.Label).Where(g => g.Count() > 1))
            foreach (var s in grp) s.Label = $"{s.Label} {s.Drawable:000}";
        // ids must be unique too
        foreach (var grp in found.GroupBy(f => f.Id).Where(g => g.Count() > 1))
        {
            int n = 1;
            foreach (var s in grp.Skip(1)) s.Id += "_" + (++n);
        }
        log?.Invoke(list.Count == 1 ? $"Found {found.Count} shoe drawables in {list[0]}" : $"Found {found.Count} shoe drawables in {list.Count} resources");
        return found.OrderBy(f => f.Gender).ThenBy(f => f.Collection).ThenBy(f => f.Drawable).ToList();
    }

    static void ScanOne(string root, List<ShoeSource> found, Dictionary<string, ShoeSource> seen)
    {
        var all = Files(root).ToList();
        var ytdsByDir = all.Where(f => f.EndsWith(".ytd", StringComparison.OrdinalIgnoreCase))
                           .GroupBy(f => Path.GetDirectoryName(f)!).ToDictionary(g => g.Key, g => g.ToList());

        foreach (var ydd in all.Where(f => f.EndsWith(".ydd", StringComparison.OrdinalIgnoreCase)))
        {
            var name = Path.GetFileName(ydd);
            var m = YddName.Match(name);
            if (!m.Success) continue;
            var dir = Path.GetDirectoryName(ydd)!;
            var resRoot = ResourceRoot(dir, root);
            var s = new ShoeSource
            {
                YddPath = ydd,
                Drawable = int.Parse(m.Groups["num"].Value),
                Skin = m.Groups["kind"].Value.Equals("r", StringComparison.OrdinalIgnoreCase),
                Resource = resRoot != null ? Path.GetFileName(resRoot) : Path.GetFileName(dir),
                Folder = Path.GetRelativePath(Path.GetDirectoryName(root) ?? root, dir).Replace('\\', '/'),
            };
            var ped = m.Groups["ped"].Value.ToLowerInvariant();
            if (ped.Length > 0)
            {
                s.Ped = ped;
                s.Gender = ped.StartsWith("mp_m") ? "male" : "female";
                s.Collection = m.Groups["dlc"].Success ? m.Groups["dlc"].Value.ToLowerInvariant() : "";
            }
            else
            {
                // a raw download (feet_000_u.ydd): fine to convert, but the drawable it ends up as on the
                // server has to be picked in game
                s.Loose = true;
                s.Gender = GuessGender(s.Folder);
                s.Ped = s.Gender == "male" ? "mp_m_freemode_01" : s.Gender == "female" ? "mp_f_freemode_01" : "";
                s.Collection = "@" + Slug(s.Folder, 60);
                s.Notes.Add("Not named for streaming, so it isn't on the server as-is. Link it to its drawable in the in-game studio.");
            }

            // colourway textures: same prefix and number, next to the model (or anywhere in the resource)
            var prefix = name[..name.IndexOf("feet_", StringComparison.OrdinalIgnoreCase)];
            var texRe = new Regex("^" + Regex.Escape(prefix) + @"feet_diff_" + m.Groups["num"].Value + @"_(?<l>[a-z])_(?<race>[a-z]{3})\.ytd$", RegexOptions.IgnoreCase);
            IEnumerable<string> candidates = ytdsByDir.TryGetValue(dir, out var here) ? here : Enumerable.Empty<string>();
            if (!candidates.Any(c => texRe.IsMatch(Path.GetFileName(c))) && resRoot != null)
                candidates = ytdsByDir.Where(kv => kv.Key.StartsWith(resRoot, StringComparison.OrdinalIgnoreCase)).SelectMany(kv => kv.Value);
            foreach (var c in candidates)
            {
                var tm = texRe.Match(Path.GetFileName(c));
                if (tm.Success)
                {
                    var l = char.ToLowerInvariant(tm.Groups["l"].Value[0]);
                    if (!s.Textures.ContainsKey(l)) s.Textures[l] = c;
                }
            }
            if (s.Textures.Count == 0) s.Notes.Add("No colourway textures (feet_diff_..._a_uni.ytd) found next to it.");

            var g = s.Gender == "male" ? "m" : s.Gender == "female" ? "f" : "u";
            s.Key = $"{g}:{s.Collection}:{s.Drawable:000}";
            if (seen.TryGetValue(s.Key, out var first))
            {
                first.Notes.Add($"Also found in {s.Folder} (ignored).");
                continue;
            }
            seen[s.Key] = s;

            // label: the closest folder that isn't a generic one
            var label = "";
            var dd = new DirectoryInfo(dir);
            while (dd != null && dd.FullName.Length >= root.Length)
            {
                if (!Generic.Contains(dd.Name.Trim())) { label = dd.Name; break; }
                if (resRoot != null && dd.FullName == resRoot) { label = dd.Name; break; }
                dd = dd.Parent;
            }
            s.Label = Pretty(string.IsNullOrEmpty(label) ? s.Resource : label);

            var col = s.Collection.StartsWith("@") ? Slug(s.Label, 18) : (s.Collection.Length > 0 ? Slug(s.Collection, 18) : "base");
            s.Id = $"{col}_{g}{s.Drawable:000}";

            using var sha = SHA1.Create();
            var sig = string.Join("|", new[] { ydd }.Concat(s.Textures.Values).Select(f =>
            { var fi = new FileInfo(f); return $"{fi.Name}:{fi.Length}:{fi.LastWriteTimeUtc.Ticks}"; }));
            s.Hash = Convert.ToHexString(sha.ComputeHash(Encoding.UTF8.GetBytes(sig)))[..12].ToLowerInvariant();
            found.Add(s);
        }
    }

    /// <summary>The inventory's image folder, if there's one under the scan root.</summary>
    public static string? FindInventoryImages(string root)
    {
        foreach (var (res, sub) in new[] { ("ox_inventory", "web/images"), ("qb-inventory", "html/images"), ("ps-inventory", "html/images"), ("lj-inventory", "html/images") })
        {
            try
            {
                foreach (var d in Directory.EnumerateDirectories(root, res, SearchOption.AllDirectories))
                {
                    var p = Path.Combine(d, sub);
                    if (Directory.Exists(p)) return p;
                }
            }
            catch { }
        }
        return null;
    }
}
