using System.Text;

namespace NayzeeeSneakerStudio;

static class Program
{
    static int Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        try
        {
            if (Kit.Wants(args)) return Kit.Run(args);
            if (args.Length > 0 && args[0] == "scan") return Scan(args);
            if (args.Length > 0 && args[0] == "convert") return ConvertCli(args);
            if (args.Length > 0 && args[0] == "preview") return PreviewCli(args);
            int port = 0;
            if (args.Length > 1 && args[0] == "--port") int.TryParse(args[1], out port);
            return WebApp.Run(port, !args.Contains("--no-browser"));
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex);
            return 1;
        }
    }

    // nzstudio scan <server folder>
    static int Scan(string[] a)
    {
        foreach (var s in Scanner.Scan(a[1], Console.WriteLine))
        {
            Console.WriteLine($"{s.Key,-32} {s.Id,-28} {s.Textures.Count,2} colours  {s.Label}  [{s.Folder}]");
            foreach (var n in s.Notes) Console.WriteLine("    ! " + n);
        }
        return 0;
    }

    // nzstudio preview <server folder> <key> <out.png>
    static int PreviewCli(string[] a)
    {
        var s = Scanner.Scan(a[1]).First(x => x.Key == a[2] || x.Id == a[2]);
        File.WriteAllBytes(a[3], Textures.Png(Studio.Preview(s, new Options())));
        return 0;
    }

    // nzstudio convert <server folder> <output resource folder> [key or id ...]
    static int ConvertCli(string[] a)
    {
        var root = a[1]; var outRoot = a[2];
        var only = a.Skip(3).ToHashSet();
        var job = new ConvertJob(root, outRoot, new Options(), Console.WriteLine);
        var plan = job.Plan(Scanner.Scan(root, Console.WriteLine));
        var pick = plan.Where(p => p.Status is "new" or "changed").Select(p => p.Source.Key).ToList();
        if (only.Count > 0) pick = plan.Where(p => only.Contains(p.Source.Key) || only.Contains(p.Source.Id)).Select(p => p.Source.Key).ToList();
        var res = job.Run(plan, pick, new Dictionary<string, string>(), new Dictionary<string, string>(), removeMissing: true, null);
        Console.WriteLine($"done: {res.Converted} converted, {res.Failed} failed, {res.Removed} removed");
        return res.Failed > 0 ? 2 : 0;
    }
}
