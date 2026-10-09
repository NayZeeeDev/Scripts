using System.Globalization;
using System.Numerics;
using System.Text;
using System.Xml;
using CodeWalker.GameFiles;

namespace NayzeeeSneakerStudio;

/// <summary>A texture ready to embed in a prop.</summary>
sealed class PropTexture
{
    public string Name = "";
    public byte[] Dds = Array.Empty<byte>();
    public TextureFormat Format;
    public int W, H, Levels;
}

/// <summary>
/// Writes props as CodeWalker XML and compiles them with CodeWalker's own importer, the same
/// path as "Import XML" in CodeWalker. Textures are embedded, so a prop needs no .ytd.
/// </summary>
static class PropWriter
{
    static string F(float v)
    {
        var s = v.ToString("0.######", CultureInfo.InvariantCulture);
        return s == "-0" ? "0" : s;
    }

    static string V3(string tag, Vector3 p) => $"<{tag} x=\"{F(p.X)}\" y=\"{F(p.Y)}\" z=\"{F(p.Z)}\" />";

    static (Vector3 lo, Vector3 hi, Vector3 c, float r) Bounds(Mesh m)
    {
        var (lo, hi) = m.Bounds();
        var c = (lo + hi) / 2;
        return (lo, hi, c, (hi - c).Length());
    }

    static string Collision(Vector3 lo, Vector3 hi, Vector3 c, float r)
    {
        var size = hi - lo;
        float vol = size.X * size.Y * size.Z;
        var inertia = new Vector3((size.Y * size.Y + size.Z * size.Z) / 12, (size.X * size.X + size.Z * size.Z) / 12, (size.X * size.X + size.Y * size.Y) / 12);
        string Common(string ind) => string.Join("\n", new[]
        {
            V3("BoxMin", lo), V3("BoxMax", hi), V3("BoxCenter", c), V3("SphereCenter", c),
            $"<SphereRadius value=\"{F(r)}\" />", "<Margin value=\"0.005\" />", $"<Volume value=\"{F(vol)}\" />",
            V3("Inertia", inertia), "<MaterialIndex value=\"0\" />", "<MaterialColourIndex value=\"0\" />",
            "<ProceduralID value=\"0\" />", "<RoomID value=\"0\" />", "<PedDensity value=\"0\" />",
            "<UnkFlags value=\"0\" />", "<PolyFlags value=\"0\" />", "<UnkType value=\"1\" />",
        }.Select(l => ind + l));
        return $@" <Bounds type=""Composite"">
{Common("  ")}
  <Children>
   <Item type=""Box"">
{Common("    ")}
    <CompositeTransform>
     1 0 0 0
     0 1 0 0
     0 0 1 0
     0 0 0 1
    </CompositeTransform>
    <CompositeFlags1>MAP_WEAPON, MAP_DYNAMIC, MAP_ANIMAL, MAP_COVER, MAP_VEHICLE</CompositeFlags1>
    <CompositeFlags2>VEHICLE_NOT_BVH, VEHICLE_BVH, PED, RAGDOLL, ANIMAL, ANIMAL_RAGDOLL, OBJECT, PLANT, PROJECTILE, EXPLOSION, FORKLIFT_FORKS, TEST_WEAPON, TEST_CAMERA, TEST_AI, TEST_SCRIPT, TEST_VEHICLE_WHEEL, GLASS</CompositeFlags2>
   </Item>
  </Children>
 </Bounds>
";
    }

    /// <summary>The prop's .ydr.xml. textures[mat] is the texture each material shows.</summary>
    static string Xml(string name, Mesh m, PropTexture[] textures, bool collision)
    {
        var (lo, hi, c, r) = Bounds(m);
        var used = Enumerable.Range(0, m.Tris).Select(t => m.M[t]).Distinct().OrderBy(x => x).ToList();
        var sb = new StringBuilder();
        sb.Append($@"<?xml version=""1.0"" encoding=""UTF-8""?>
<Drawable>
 <Name>{name}</Name>
 {V3("BoundingSphereCenter", c)}
 <BoundingSphereRadius value=""{F(r)}"" />
 {V3("BoundingBoxMin", lo)}
 {V3("BoundingBoxMax", hi)}
 <LodDistHigh value=""9998"" />
 <LodDistMed value=""9998"" />
 <LodDistLow value=""9998"" />
 <LodDistVlow value=""9998"" />
 <FlagsHigh value=""1"" />
 <FlagsMed value=""0"" />
 <FlagsLow value=""0"" />
 <FlagsVlow value=""0"" />
 <ShaderGroup>
  <TextureDictionary>
");
        foreach (var tex in used.Select(u => textures[u]).DistinctBy(t => t.Name))
            sb.Append($@"   <Item>
    <Name>{tex.Name}</Name>
    <Unk32 value=""128"" />
    <Usage>DIFFUSE</Usage>
    <UsageFlags>UNK24</UsageFlags>
    <ExtraFlags value=""0"" />
    <Width value=""{tex.W}"" />
    <Height value=""{tex.H}"" />
    <MipLevels value=""{tex.Levels}"" />
    <Format>{tex.Format}</Format>
    <FileName>{tex.Name}.dds</FileName>
   </Item>
");
        sb.Append("  </TextureDictionary>\n  <Shaders>\n");
        foreach (var u in used)
            sb.Append($@"   <Item>
    <Name>default</Name>
    <FileName>default.sps</FileName>
    <RenderBucket value=""0"" />
    <Parameters>
     <Item name=""DiffuseSampler"" type=""Texture"">
      <Name>{textures[u].Name}</Name>
     </Item>
     <Item name=""matMaterialColorScale"" type=""Vector"" x=""1"" y=""0"" z=""0"" w=""1"" />
     <Item name=""HardAlphaBlend"" type=""Vector"" x=""1"" y=""0"" z=""0"" w=""0"" />
     <Item name=""useTessellation"" type=""Vector"" x=""0"" y=""0"" z=""0"" w=""0"" />
     <Item name=""wetnessMultiplier"" type=""Vector"" x=""1"" y=""0"" z=""0"" w=""0"" />
     <Item name=""globalAnimUV0"" type=""Vector"" x=""1"" y=""0"" z=""0"" w=""0"" />
     <Item name=""globalAnimUV1"" type=""Vector"" x=""0"" y=""1"" z=""0"" w=""0"" />
    </Parameters>
   </Item>
");
        sb.Append(" </Shaders>\n </ShaderGroup>\n <DrawableModelsHigh>\n  <Item>\n   <RenderMask value=\"255\" />\n   <Flags value=\"0\" />\n   <HasSkin value=\"0\" />\n   <BoneIndex value=\"0\" />\n   <Unknown1 value=\"0\" />\n   <Geometries>\n");

        for (int s = 0; s < used.Count; s++)
        {
            var tris = Enumerable.Range(0, m.Tris).Where(t => m.M[t] == used[s]).ToList();
            // a geometry can index at most 65535 vertices: split big ones
            for (int start = 0; start < tris.Count;)
            {
                var map = new Dictionary<int, int>();
                var order = new List<int>();
                var idx = new List<int>();
                int t = start;
                for (; t < tris.Count; t++)
                {
                    int need = 0;
                    for (int k = 0; k < 3; k++) if (!map.ContainsKey(m.I[tris[t] * 3 + k])) need++;
                    if (order.Count + need > 65000) break;
                    for (int k = 0; k < 3; k++)
                    {
                        int v = m.I[tris[t] * 3 + k];
                        if (!map.TryGetValue(v, out int nv)) { nv = order.Count; map[v] = nv; order.Add(v); }
                        idx.Add(nv);
                    }
                }
                start = t;
                var glo = new Vector3(float.MaxValue); var ghi = new Vector3(float.MinValue);
                foreach (var v in order) { glo = Vector3.Min(glo, m.P[v]); ghi = Vector3.Max(ghi, m.P[v]); }
                sb.Append($@"    <Item>
     <ShaderIndex value=""{s}"" />
     <BoundingBoxMin x=""{F(glo.X)}"" y=""{F(glo.Y)}"" z=""{F(glo.Z)}"" w=""0"" />
     <BoundingBoxMax x=""{F(ghi.X)}"" y=""{F(ghi.Y)}"" z=""{F(ghi.Z)}"" w=""0"" />
     <VertexBuffer>
      <Flags value=""0"" />
      <Layout type=""GTAV1"">
       <Position />
       <Normal />
       <Colour0 />
       <TexCoord0 />
      </Layout>
      <Data>
");
                foreach (var v in order)
                {
                    var p = m.P[v]; var n = m.N[v]; var uv = m.T[v];
                    sb.Append($"          {F(p.X)} {F(p.Y)} {F(p.Z)}   {F(n.X)} {F(n.Y)} {F(n.Z)}   255 255 255 255   {F(uv.X)} {F(uv.Y)}\n");
                }
                sb.Append("      </Data>\n     </VertexBuffer>\n     <IndexBuffer>\n      <Data>\n");
                for (int k = 0; k < idx.Count; k += 24)
                    sb.Append("          " + string.Join(" ", idx.Skip(k).Take(24)) + "\n");
                sb.Append("      </Data>\n     </IndexBuffer>\n    </Item>\n");
            }
        }
        sb.Append("   </Geometries>\n  </Item>\n </DrawableModelsHigh>\n");
        if (collision) sb.Append(Collision(lo, hi, c, r));
        sb.Append("</Drawable>\n");
        return sb.ToString();
    }

    /// <summary>Builds a .ydr (binary) for the mesh, loads it back to check it, returns the bytes.</summary>
    public static byte[] Ydr(string name, Mesh m, PropTexture[] textures, string tempDir, bool collision = true)
    {
        var dir = Path.Combine(tempDir, name);
        Directory.CreateDirectory(dir);
        foreach (var t in textures.DistinctBy(t => t.Name))
            File.WriteAllBytes(Path.Combine(dir, t.Name + ".dds"), t.Dds);
        try
        {
            var ydr = XmlYdr.GetYdr(Xml(name, m, textures, collision), dir);
            var bytes = ydr.Save();
            var back = RpfFile.GetResourceFile<YdrFile>((byte[])bytes.Clone());
            if (back?.Drawable?.DrawableModels?.High == null) throw new Exception("the built prop didn't load back");
            return bytes;
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch { }
        }
    }

    /// <summary>A .ytyp (binary) registering the props. Textures are embedded, so no txd.</summary>
    public static byte[] Ytyp(string ytypName, IEnumerable<(string name, Mesh mesh)> props, float lodDist = 100f)
    {
        var sb = new StringBuilder("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<CMapTypes>\n  <extensions/>\n  <archetypes>\n");
        foreach (var (name, mesh) in props)
        {
            var (lo, hi, c, r) = Bounds(mesh);
            sb.Append($@"    <Item type=""CBaseArchetypeDef"">
      <lodDist value=""{F(lodDist)}""/>
      <flags value=""32""/>
      <specialAttribute value=""0""/>
      <bbMin x=""{F(lo.X)}"" y=""{F(lo.Y)}"" z=""{F(lo.Z)}""/>
      <bbMax x=""{F(hi.X)}"" y=""{F(hi.Y)}"" z=""{F(hi.Z)}""/>
      <bsCentre x=""{F(c.X)}"" y=""{F(c.Y)}"" z=""{F(c.Z)}""/>
      <bsRadius value=""{F(r)}""/>
      <hdTextureDist value=""50""/>
      <name>{name}</name>
      <textureDictionary/>
      <clipDictionary/>
      <drawableDictionary/>
      <physicsDictionary/>
      <assetType>ASSET_TYPE_DRAWABLE</assetType>
      <assetName>{name}</assetName>
      <extensions/>
    </Item>
");
        }
        sb.Append($"  </archetypes>\n  <name>{ytypName}</name>\n  <dependencies/>\n  <compositeEntityTypes/>\n</CMapTypes>\n");
        var doc = new XmlDocument();
        doc.LoadXml(sb.ToString());
        var fmt = XmlMeta.GetXMLFormat(ytypName + ".ytyp.xml", out _);
        var data = XmlMeta.GetData(doc, fmt, ytypName) ?? throw new Exception("couldn't build " + ytypName + ".ytyp");
        var check = new YtypFile();
        check.Load((byte[])data.Clone());
        if (check.AllArchetypes == null || check.AllArchetypes.Length == 0) throw new Exception("the built .ytyp has no archetypes");
        return data;
    }
}
