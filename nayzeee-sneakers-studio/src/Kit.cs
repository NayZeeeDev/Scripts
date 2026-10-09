using System.Text.Json;

namespace NayzeeeSneakerStudio;

/// <summary>
/// Server mode. nayzeee-sneakers starts this itself (server/sneakerkit.js) with every started resource
/// in a roots file, and reads the "@{json}" lines it prints:
///   scan  --out &lt;props&gt; --roots-file &lt;f&gt;               what's new, changed or gone since the last build
///   build --out &lt;props&gt; --roots-file &lt;f&gt; [--all]       converts new + changed (or everything) and removes
///                                                         props of shoes that are gone
/// Options: --tex 256|512|1024, --icons &lt;inventory image folder&gt;, --keep &lt;folder of in-game photos&gt;
/// </summary>
static class Kit
{
    static readonly JsonSerializerOptions Line = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    static void Emit(string kind, object data)
    {
        Console.WriteLine("@" + JsonSerializer.Serialize(new { kind, data }, Line));
        Console.Out.Flush();
    }

    public static bool Wants(string[] a) => a.Length > 0 && (a[0] == "scan" || a[0] == "build") && a.Contains("--roots-file");

    public static int Run(string[] a)
    {
        string? Arg(string n) { var i = Array.IndexOf(a, n); return i >= 0 && i + 1 < a.Length ? a[i + 1] : null; }
        var outRoot = Arg("--out");
        var rootsFile = Arg("--roots-file");
        if (outRoot == null || rootsFile == null || !File.Exists(rootsFile))
        {
            Emit("error", new { message = "sneakerkit needs --out and --roots-file" });
            return 2;
        }
        var opt = new Options();
        if (int.TryParse(Arg("--tex"), out var tex)) opt.TextureSize = Math.Clamp(tex, 128, 1024);
        if (int.TryParse(Arg("--tris"), out var tris)) opt.MaxTriangles = Math.Clamp(tris, 2000, 100000);
        var icons = Arg("--icons");
        if (icons != null && !Directory.Exists(icons)) icons = null;

        try
        {
            var roots = File.ReadAllLines(rootsFile);
            var job = new ConvertJob("", outRoot, opt, Console.WriteLine) { KeepDir = Arg("--keep") };
            // plain downloads (feet_000_u.ydd) aren't on the server as-is, so in server mode they're left alone
            var found = Scanner.ScanRoots(roots, Console.WriteLine).Where(s => !s.Loose && s.Gender != "unknown").ToList();
            var plan = job.Plan(found);
            var fresh = plan.Where(p => p.Status == "new").Select(p => p.Source.Key).ToList();
            var changed = plan.Where(p => p.Status == "changed").Select(p => p.Source.Key).ToList();
            var removed = plan.Where(p => p.Status == "removed").Select(p => p.Source.Key).ToList();

            if (a[0] == "scan")
            {
                Emit("scan", new { found = found.Count, @new = fresh, changed, removed });
                return 0;
            }

            var pick = a.Contains("--all") ? plan.Where(p => p.Status != "removed").Select(p => p.Source.Key).ToList()
                                           : fresh.Concat(changed).ToList();
            var res = job.Run(plan, pick, new Dictionary<string, string>(), new Dictionary<string, string>(), removeMissing: true,
                (i, n, label) => { if (i < n) Emit("progress", new { i = i + 1, n, key = label }); }, icons);
            var props = Catalogue.Load(job.CataloguePath).Shoes.Count;
            Emit("done", new { built = res.Converted, tried = pick.Count, removed = res.Removed, failed = res.Failed, props, errors = res.Errors });
            return res.Failed > 0 && res.Converted == 0 && pick.Count > 0 ? 3 : 0;
        }
        catch (Exception ex)
        {
            Emit("error", new { message = ex.Message });
            Console.Error.WriteLine(ex);
            return 1;
        }
    }
}
