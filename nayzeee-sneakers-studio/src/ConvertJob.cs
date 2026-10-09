namespace NayzeeeSneakerStudio;

sealed class PlanItem
{
    public ShoeSource Source = null!;
    public string Status = "new";          // new | changed | done | removed
    public CatalogueShoe? Existing;
}

sealed class JobResult
{
    public int Converted, Failed, Removed, Skipped;
    public List<string> Errors = new();
}

/// <summary>
/// Compares a scan with the last run's catalogue.json and converts what's new or changed.
/// Shoes that aren't on the server any more are removed from the output.
/// </summary>
sealed class ConvertJob
{
    readonly string root, outRoot;
    readonly Options options;
    readonly Action<string> log;

    public ConvertJob(string root, string outRoot, Options options, Action<string> log)
    {
        this.root = root; this.outRoot = outRoot; this.options = options; this.log = log;
    }

    public string CataloguePath => Path.Combine(outRoot, "catalogue.json");

    public List<PlanItem> Plan(List<ShoeSource> found)
    {
        var cat = Catalogue.Load(CataloguePath);
        var byKey = cat.Shoes.ToDictionary(s => s.Key, s => s);
        var plan = new List<PlanItem>();
        foreach (var s in found)
        {
            var item = new PlanItem { Source = s };
            if (byKey.TryGetValue(s.Key, out var ex))
            {
                item.Existing = ex;
                s.Id = ex.Id;   // keep ids (and prop names) stable between runs
                bool filesThere = File.Exists(Path.Combine(outRoot, "stream", ex.Id, $"nzs_{ex.Id}.ytyp"));
                item.Status = ex.Hash == s.Hash && filesThere ? "done" : "changed";
            }
            plan.Add(item);
        }
        var keys = found.Select(f => f.Key).ToHashSet();
        foreach (var ex in cat.Shoes.Where(c => !keys.Contains(c.Key)))
            plan.Add(new PlanItem
            {
                Status = "removed", Existing = ex,
                Source = new ShoeSource { Key = ex.Key, Id = ex.Id, Label = ex.Label, Gender = ex.Gender, Collection = ex.Collection, Drawable = ex.Drawable, Folder = ex.Source },
            });
        return plan;
    }

    /// <summary>
    /// Converts the shoes in `keys`, keeps the rest as they were, removes shoes that are gone
    /// (when removeMissing), and rewrites the resource's catalogue and fxmanifest.
    /// labels / boxes: overrides per key from the app. progress(done, total, current).
    /// </summary>
    public JobResult Run(List<PlanItem> plan, IList<string> keys, IDictionary<string, string> labels, IDictionary<string, string> boxes,
        bool removeMissing, Action<int, int, string>? progress, string? copyIconsTo = null)
    {
        var res = new JobResult();
        var cat = Catalogue.Load(CataloguePath);
        var entries = cat.Shoes.ToDictionary(s => s.Key, s => s);
        var todo = plan.Where(p => keys.Contains(p.Source.Key) && p.Status != "removed").ToList();
        int i = 0;
        foreach (var p in todo)
        {
            progress?.Invoke(i, todo.Count, p.Source.Label);
            log($"[{++i}/{todo.Count}] {p.Source.Label}  ({p.Source.Key})");
            try
            {
                var label = labels.TryGetValue(p.Source.Key, out var lb) && !string.IsNullOrWhiteSpace(lb) ? lb.Trim()
                          : p.Existing?.Label ?? p.Source.Label;
                string? box = boxes.TryGetValue(p.Source.Key, out var bx) && bx is "shoe" or "heel" or "boot" ? bx : null;
                var entry = Studio.Convert(p.Source, outRoot, options, box, label, log);
                // colour names the owner already changed in game stay as they are
                if (p.Existing != null)
                    foreach (var c in entry.Colours)
                    {
                        var old = p.Existing.Colours.FirstOrDefault(o => o.Letter == c.Letter);
                        if (old != null && !string.IsNullOrWhiteSpace(old.Name)) c.Name = old.Name;
                    }
                entries[p.Source.Key] = entry;
                res.Converted++;
                if (copyIconsTo != null) CopyIcons(entry, copyIconsTo);
            }
            catch (Exception ex)
            {
                res.Failed++;
                res.Errors.Add($"{p.Source.Label}: {ex.Message}");
                log($"  FAILED: {ex.Message}");
            }
        }
        if (removeMissing)
            foreach (var p in plan.Where(p => p.Status == "removed"))
            {
                var id = p.Existing!.Id;
                try { var d = Path.Combine(outRoot, "stream", id); if (Directory.Exists(d)) Directory.Delete(d, true); } catch { }
                foreach (var c in p.Existing.Colours)
                    foreach (var f in new[] { $"nzs_{id}_{c.Letter}.png", $"nzs_{id}_{c.Letter}_box.png" })
                        try { File.Delete(Path.Combine(outRoot, "icons", f)); } catch { }
                entries.Remove(p.Source.Key);
                res.Removed++;
                log($"removed {p.Existing.Label} ({p.Source.Key}): no longer on the server");
            }
        // label edits on shoes that weren't re-converted
        foreach (var (k, v) in labels)
            if (entries.TryGetValue(k, out var e) && !string.IsNullOrWhiteSpace(v)) e.Label = v.Trim();
        res.Skipped = plan.Count(p => p.Status == "done" && !keys.Contains(p.Source.Key));
        cat.Shoes = entries.Values.ToList();
        Studio.WriteResource(outRoot, cat);
        if (copyIconsTo != null) foreach (var e in cat.Shoes) CopyIcons(e, copyIconsTo);
        progress?.Invoke(todo.Count, todo.Count, "");
        return res;
    }

    void CopyIcons(CatalogueShoe e, string dest)
    {
        try
        {
            Directory.CreateDirectory(dest);
            foreach (var c in e.Colours)
                foreach (var f in new[] { $"nzs_{e.Id}_{c.Letter}.png", $"nzs_{e.Id}_{c.Letter}_box.png" })
                {
                    var src = Path.Combine(outRoot, "icons", f);
                    if (File.Exists(src)) File.Copy(src, Path.Combine(dest, f), true);
                }
        }
        catch (Exception ex) { log("  couldn't copy icons: " + ex.Message); }
    }
}
