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

    /// <summary>Started as tools/sneakerkit (not as the PC app).</summary>
    public static bool IsKit() =>
        Path.GetFileNameWithoutExtension(Environment.ProcessPath ?? "").StartsWith("sneakerkit", StringComparison.OrdinalIgnoreCase);

    static string Ask(string prompt)
    {
        Console.Write(prompt);
        try { return (Console.ReadLine() ?? "").Trim().Trim('"'); } catch { return ""; }
    }

    static int Finish(int code)
    {
        Console.WriteLine();
        Ask("Press Enter to close.");
        return code;
    }

    /// <summary>
    /// Double-clicked: find the server's resources folder from where this file sits
    /// (resources/.../nayzeee-sneakers/tools/sneakerkit/win-x64), scan it and build the props into
    /// nayzeee-sneakers-props, next to nayzeee-sneakers. Same result as the server's own build.
    /// </summary>
    public static int Interactive()
    {
        Console.WriteLine("sneakerkit - nayzeee-sneakers");
        Console.WriteLine("Turns the shoes in your clothing packs into props for nayzeee-sneakers.");
        Console.WriteLine("(Your server does this by itself when it starts. This is the same thing, by hand.)");
        Console.WriteLine();

        var dir = new DirectoryInfo(Path.GetDirectoryName(Environment.ProcessPath ?? AppContext.BaseDirectory)!);
        DirectoryInfo? res = dir;
        while (res != null && !File.Exists(Path.Combine(res.FullName, "fxmanifest.lua"))) res = res.Parent;
        DirectoryInfo? root = res?.Parent;
        for (var d = res?.Parent; d != null; d = d.Parent)
            if (d.Name.Equals("resources", StringComparison.OrdinalIgnoreCase)) { root = d; break; }

        if (root != null) Console.WriteLine($"Server resources: {root.FullName}");
        var typed = Ask(root != null ? "Press Enter to scan it, or paste a different folder: " : "Paste your server's resources folder: ");
        if (typed.Length > 0) root = new DirectoryInfo(typed);
        if (root == null || !root.Exists)
        {
            Console.WriteLine("That folder doesn't exist.");
            return Finish(2);
        }

        // where the props go: an existing nayzeee-sneakers-props, else next to nayzeee-sneakers
        string? outRoot = null;
        try { outRoot = Directory.EnumerateDirectories(root.FullName, "nayzeee-sneakers-props", SearchOption.AllDirectories).FirstOrDefault(); } catch { }
        outRoot ??= Path.Combine(res?.Parent?.FullName ?? root.FullName, "nayzeee-sneakers-props");

        Scanner.ExtraSkip.Add("nayzeee-sneakers-clothing");   // the bundled shoes already have props
        if (res != null) Scanner.ExtraSkip.Add(res.Name);
        var keep = res != null ? Path.Combine(res.FullName, "shots") : null;
        var icons = Scanner.FindInventoryImages(root.FullName);

        Console.WriteLine();
        Console.WriteLine("Looking for shoes...");
        var opt = new Options();
        var job = new ConvertJob("", outRoot, opt, _ => { }) { KeepDir = keep };
        var found = Scanner.ScanRoots(new[] { root.FullName }).Where(x => !x.Loose && x.Gender != "unknown").ToList();
        var plan = job.Plan(found);
        int fresh = plan.Count(p => p.Status == "new"), changed = plan.Count(p => p.Status == "changed"), gone = plan.Count(p => p.Status == "removed");
        Console.WriteLine($"Found {found.Count} shoes: {fresh} new, {changed} changed, {gone} gone, {plan.Count(p => p.Status == "done")} already done.");
        Console.WriteLine($"Props go to:  {outRoot}");
        if (icons != null) Console.WriteLine($"Icons go to:  {icons}");
        if (fresh + changed + gone == 0)
        {
            Console.WriteLine();
            Console.WriteLine("Everything is up to date.");
            return Finish(0);
        }
        Console.WriteLine();
        var all = Ask($"Press Enter to build {fresh + changed} shoe(s){(gone > 0 ? $" and remove {gone}" : "")}, or type ALL to rebuild every shoe: ")
            .Equals("all", StringComparison.OrdinalIgnoreCase);
        var pick = all ? plan.Where(p => p.Status != "removed").Select(p => p.Source.Key).ToList()
                       : plan.Where(p => p.Status is "new" or "changed").Select(p => p.Source.Key).ToList();
        Console.WriteLine();
        var res2 = job.Run(plan, pick, new Dictionary<string, string>(), new Dictionary<string, string>(), removeMissing: true,
            (i, n, label) => { if (i < n) Console.WriteLine($"  [{i + 1}/{n}] {label}"); }, icons);
        Console.WriteLine();
        Console.WriteLine($"Done: built {res2.Converted}, removed {res2.Removed}{(res2.Failed > 0 ? $", {res2.Failed} failed" : "")}.");
        foreach (var e in res2.Errors) Console.WriteLine("  ! " + e);
        Console.WriteLine("Now restart your server (or in the server console: refresh, then ensure nayzeee-sneakers-props).");
        return Finish(res2.Failed > 0 && res2.Converted == 0 ? 3 : 0);
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
