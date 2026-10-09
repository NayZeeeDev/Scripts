# cwtool

Minimal command-line wrapper around [CodeWalker.Core](https://github.com/dexyfex/CodeWalker)
(dexyfex) that converts CodeWalker XML to the legacy RSC7 binaries FiveM streams,
and loads binaries back for inspection. CodeWalker.Core targets netstandard2.0 and
builds fine on Linux/macOS/Windows with the .NET 8 SDK.

```bash
git clone --depth 1 https://github.com/dexyfex/CodeWalker ../CodeWalker   # expected at tools/CodeWalker
dotnet build -c Release
dotnet bin/Release/net8.0/cwtool.dll ydr  <in.ydr.xml>  <ddsFolder> <out.ydr>
dotnet bin/Release/net8.0/cwtool.dll ytd  <in.ytd.xml>  <ddsFolder> <out.ytd>
dotnet bin/Release/net8.0/cwtool.dll ytyp <in.ytyp.xml> <out.ytyp>
dotnet bin/Release/net8.0/cwtool.dll inspect <file.ydr|.ytd|.ytyp> [reexport.xml]
```

`ddsFolder` is the folder holding the `.dds` files referenced by `<FileName>` in
the XML (CodeWalker's convention: a folder named like the asset next to the XML).
