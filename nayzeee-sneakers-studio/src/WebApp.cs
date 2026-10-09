using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace NayzeeeSneakerStudio;

sealed class Settings
{
    public string Root { get; set; } = "";
    public string Out { get; set; } = "";
    public int TextureSize { get; set; } = 512;
    public int MaxTriangles { get; set; } = 24000;
    public bool CopyIcons { get; set; } = true;
    public bool RemoveMissing { get; set; } = true;

    static string PathFor()
    {
        var local = Path.Combine(AppContext.BaseDirectory, "studio-settings.json");
        try { File.AppendAllText(local, ""); return local; }
        catch { }
        var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "NayZeee Sneaker Studio");
        Directory.CreateDirectory(dir);
        return Path.Combine(dir, "studio-settings.json");
    }

    public static Settings Load()
    {
        try { var t = File.ReadAllText(PathFor()); return t.Length > 0 ? JsonSerializer.Deserialize<Settings>(t, Catalogue.Json) ?? new() : new(); }
        catch { return new(); }
    }

    public void Save() { try { File.WriteAllText(PathFor(), JsonSerializer.Serialize(this, Catalogue.Json)); } catch { } }
}

/// <summary>
/// The studio app: a small local web server on 127.0.0.1 and a page in the browser. Nothing
/// leaves the machine; the page only talks to this process.
/// </summary>
static class WebApp
{
    static Settings settings = Settings.Load();
    static List<PlanItem> plan = new();
    static readonly ConcurrentDictionary<string, byte[]> previews = new();
    static readonly SemaphoreSlim renderGate = new(2);
    static readonly object jobLock = new();
    static JobState job = new();

    sealed class JobState
    {
        public bool Running; public int Done, Total; public string Current = "";
        public List<string> Log = new(); public JobResult? Result; public string? Error;
    }

    public static int Run(int port, bool openBrowser)
    {
        var listener = new TcpListener(IPAddress.Loopback, port > 0 ? port : 7710);
        try { listener.Start(); }
        catch { listener = new TcpListener(IPAddress.Loopback, 0); listener.Start(); }
        var url = $"http://127.0.0.1:{((IPEndPoint)listener.LocalEndpoint).Port}/";
        Console.WriteLine();
        Console.WriteLine("  NAYZEEE SNEAKER STUDIO");
        Console.WriteLine("  Open " + url + " in your browser (it should open by itself).");
        Console.WriteLine("  Keep this window open while you use it. Close it to quit.");
        Console.WriteLine();
        if (openBrowser)
            try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { }
        while (true)
        {
            var client = listener.AcceptTcpClient();
            _ = Task.Run(() => Handle(client));
        }
    }

    // ------------------------------------------------------------ http

    static async Task Handle(TcpClient client)
    {
        using (client)
        {
            try
            {
                var stream = client.GetStream();
                var (method, target, body) = await ReadRequest(stream);
                if (method == null) return;
                var (status, type, data) = await Route(method, target, body);
                var head = $"HTTP/1.1 {status}\r\nContent-Type: {type}\r\nContent-Length: {data.Length}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n";
                await stream.WriteAsync(Encoding.ASCII.GetBytes(head));
                await stream.WriteAsync(data);
            }
            catch { }
        }
    }

    static async Task<(string?, string, byte[])> ReadRequest(NetworkStream s)
    {
        var buf = new List<byte>();
        var one = new byte[1];
        while (true)
        {
            int n = await s.ReadAsync(one);
            if (n == 0) return (null, "", Array.Empty<byte>());
            buf.Add(one[0]);
            int c = buf.Count;
            if (c >= 4 && buf[c - 4] == '\r' && buf[c - 3] == '\n' && buf[c - 2] == '\r' && buf[c - 1] == '\n') break;
            if (c > 65536) return (null, "", Array.Empty<byte>());
        }
        var lines = Encoding.UTF8.GetString(buf.ToArray()).Split("\r\n");
        var parts = lines[0].Split(' ');
        int len = 0;
        foreach (var l in lines.Skip(1))
            if (l.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase)) int.TryParse(l[15..].Trim(), out len);
        var body = new byte[len];
        int read = 0;
        while (read < len) { int n = await s.ReadAsync(body.AsMemory(read)); if (n == 0) break; read += n; }
        return (parts[0], parts.Length > 1 ? parts[1] : "/", body);
    }

    static (string, string, byte[]) Json(object o) => ("200 OK", "application/json; charset=utf-8", JsonSerializer.SerializeToUtf8Bytes(o, Catalogue.Json));
    static (string, string, byte[]) Fail(string msg) => ("400 Bad Request", "application/json; charset=utf-8", JsonSerializer.SerializeToUtf8Bytes(new { error = msg }, Catalogue.Json));

    static string Mime(string p) => Path.GetExtension(p).ToLowerInvariant() switch
    {
        ".html" => "text/html; charset=utf-8", ".css" => "text/css; charset=utf-8", ".js" => "application/javascript; charset=utf-8",
        ".woff2" => "font/woff2", ".png" => "image/png", ".svg" => "image/svg+xml", _ => "application/octet-stream",
    };

    static byte[]? Asset(string path)
    {
        var asm = Assembly.GetExecutingAssembly();
        using var st = asm.GetManifestResourceStream("web/" + path.TrimStart('/'));
        if (st == null) return null;
        using var ms = new MemoryStream();
        st.CopyTo(ms);
        return ms.ToArray();
    }

    static async Task<(string, string, byte[])> Route(string method, string target, byte[] body)
    {
        var path = target.Split('?')[0];
        var query = target.Contains('?') ? System.Web.HttpUtility.ParseQueryString(target[(target.IndexOf('?') + 1)..]) : new System.Collections.Specialized.NameValueCollection();
        JsonNode? json = null;
        if (body.Length > 0) try { json = JsonNode.Parse(body); } catch { }

        if (!path.StartsWith("/api/"))
        {
            var file = path == "/" ? "index.html" : Uri.UnescapeDataString(path.TrimStart('/'));
            var data = Asset(file);
            return data == null ? ("404 Not Found", "text/plain", Encoding.UTF8.GetBytes("not found")) : ("200 OK", Mime(file), data);
        }

        switch (path)
        {
            case "/api/state":
                return Json(new { settings, inventory = Guess(settings.Root), version = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) });

            case "/api/dirs":
                return Json(Dirs(query["path"]));

            case "/api/scan":
                {
                    var root = json?["root"]?.GetValue<string>()?.Trim() ?? "";
                    var outDir = json?["out"]?.GetValue<string>()?.Trim() ?? "";
                    if (!Directory.Exists(root)) return Fail("That server folder doesn't exist.");
                    if (outDir.Length == 0) outDir = Path.Combine(root, "nayzeee-sneakers-props");
                    settings.Root = root; settings.Out = outDir;
                    if (json?["textureSize"] is JsonNode ts) settings.TextureSize = ts.GetValue<int>();
                    if (json?["maxTriangles"] is JsonNode mt) settings.MaxTriangles = mt.GetValue<int>();
                    settings.Save();
                    var found = await Task.Run(() => Scanner.Scan(root));
                    var job2 = new ConvertJob(root, outDir, OptionsNow(), _ => { });
                    plan = job2.Plan(found);
                    return Json(new
                    {
                        root, @out = outDir, inventory = Guess(root),
                        items = plan.Select(p => new
                        {
                            key = p.Source.Key, id = p.Source.Id, status = p.Status,
                            label = p.Existing?.Label ?? p.Source.Label, gender = p.Source.Gender,
                            collection = p.Source.Collection, drawable = p.Source.Drawable, loose = p.Source.Loose,
                            skin = p.Source.Skin, colours = p.Status == "removed" ? p.Existing!.Colours.Count : p.Source.Textures.Count,
                            box = p.Existing?.Box, folder = p.Source.Folder, notes = p.Source.Notes, hash = p.Source.Hash,
                            icon = p.Existing != null && p.Existing.Colours.Count > 0 ? $"nzs_{p.Existing.Id}_{p.Existing.Colours[0].Letter}.png" : null,
                        }),
                    });
                }

            case "/api/preview":
                {
                    var key = query["key"] ?? "";
                    var item = plan.FirstOrDefault(p => p.Source.Key == key);
                    if (item == null) return ("404 Not Found", "text/plain", Array.Empty<byte>());
                    // already converted: show its icon
                    if (item.Existing != null && item.Status != "changed")
                    {
                        var c = item.Existing.Colours.FirstOrDefault();
                        var ico = c == null ? null : Path.Combine(settings.Out, "icons", $"nzs_{item.Existing.Id}_{c.Letter}.png");
                        if (ico != null && File.Exists(ico)) return ("200 OK", "image/png", File.ReadAllBytes(ico));
                    }
                    if (item.Status == "removed") return ("404 Not Found", "text/plain", Array.Empty<byte>());
                    var cacheKey = key + "|" + item.Source.Hash;
                    if (!previews.TryGetValue(cacheKey, out var png))
                    {
                        await renderGate.WaitAsync();
                        try
                        {
                            png = previews.GetOrAdd(cacheKey, _ => Textures.Png(Studio.Preview(item.Source, OptionsNow(), 220)));
                        }
                        catch { return ("500 Internal Server Error", "text/plain", Array.Empty<byte>()); }
                        finally { renderGate.Release(); }
                    }
                    return ("200 OK", "image/png", png);
                }

            case "/api/icon":
                {
                    var f = Path.GetFileName(query["file"] ?? "");
                    var p = Path.Combine(settings.Out, "icons", f);
                    return File.Exists(p) ? ("200 OK", "image/png", File.ReadAllBytes(p)) : ("404 Not Found", "text/plain", Array.Empty<byte>());
                }

            case "/api/convert":
                {
                    lock (jobLock) { if (job.Running) return Fail("A conversion is already running."); }
                    var keys = json?["keys"]?.AsArray().Select(k => k!.GetValue<string>()).ToList() ?? new();
                    var labels = json?["labels"]?.AsObject().ToDictionary(kv => kv.Key, kv => kv.Value?.GetValue<string>() ?? "") ?? new();
                    var boxes = json?["boxes"]?.AsObject().ToDictionary(kv => kv.Key, kv => kv.Value?.GetValue<string>() ?? "") ?? new();
                    settings.RemoveMissing = json?["removeMissing"]?.GetValue<bool>() ?? settings.RemoveMissing;
                    settings.CopyIcons = json?["copyIcons"]?.GetValue<bool>() ?? settings.CopyIcons;
                    settings.Save();
                    var inv = settings.CopyIcons ? Scanner.FindInventoryImages(settings.Root) : null;
                    lock (jobLock) job = new JobState { Running = true, Total = keys.Count };
                    var snapshot = plan;
                    _ = Task.Run(() =>
                    {
                        try
                        {
                            var j = new ConvertJob(settings.Root, settings.Out, OptionsNow(), line => { lock (jobLock) { job.Log.Add(line); if (job.Log.Count > 600) job.Log.RemoveAt(0); } });
                            var res = j.Run(snapshot, keys, labels, boxes, settings.RemoveMissing,
                                (d, t, cur) => { lock (jobLock) { job.Done = d; job.Total = t; job.Current = cur; } }, inv);
                            if (inv != null) lock (jobLock) job.Log.Add($"Copied the icons into {inv}");
                            lock (jobLock) { job.Result = res; job.Running = false; }
                        }
                        catch (Exception ex) { lock (jobLock) { job.Error = ex.Message; job.Running = false; } }
                    });
                    return Json(new { ok = true });
                }

            case "/api/job":
                lock (jobLock)
                    return Json(new { job.Running, job.Done, job.Total, job.Current, log = job.Log.ToList(), result = job.Result == null ? null : new { job.Result.Converted, job.Result.Failed, job.Result.Removed, job.Result.Skipped, job.Result.Errors }, job.Error, @out = settings.Out });

            case "/api/open":
                {
                    var p = json?["path"]?.GetValue<string>() ?? settings.Out;
                    if (Directory.Exists(p))
                        try { Process.Start(new ProcessStartInfo(p) { UseShellExecute = true }); } catch { }
                    return Json(new { ok = true });
                }
        }
        return ("404 Not Found", "text/plain", Array.Empty<byte>());
    }

    static Options OptionsNow() => new() { TextureSize = settings.TextureSize, MaxTriangles = settings.MaxTriangles };

    static string? Guess(string root) => Directory.Exists(root) ? Scanner.FindInventoryImages(root) : null;

    static object Dirs(string? path)
    {
        if (string.IsNullOrWhiteSpace(path) || !Directory.Exists(path))
        {
            var drives = DriveInfo.GetDrives().Where(d => d.IsReady).Select(d => d.RootDirectory.FullName).ToList();
            var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            return new { path = "", parent = (string?)null, dirs = drives.Concat(new[] { home }).ToList(), server = false };
        }
        var full = Path.GetFullPath(path);
        List<string> dirs;
        try { dirs = Directory.GetDirectories(full).Where(d => !Path.GetFileName(d).StartsWith('.')).OrderBy(d => d, StringComparer.OrdinalIgnoreCase).ToList(); }
        catch { dirs = new(); }
        bool server = Directory.Exists(Path.Combine(full, "resources")) || File.Exists(Path.Combine(full, "server.cfg"));
        return new { path = full, parent = Directory.GetParent(full)?.FullName, dirs, server };
    }
}
