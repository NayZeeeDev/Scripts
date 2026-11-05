-----------------------------------------------------------------
-- The converter (chainkit). Left as it is: nothing here needs
-- changing on a normal server. Which clothing packs to convert is
-- Config.ScanResources in config.lua.
-----------------------------------------------------------------

Config.Convert = {
    Enabled      = true,
    DropFolder   = 'chains',       -- inside this resource: chains/<Chain Name>/teef_000_u.ydd + teef_diff_000_a_*.ytd ...
    ScanResources = Config.ScanResources or {},
    AutoScan     = true,           -- check what's new on start (shows in the studio)
    AutoBuild    = true,           -- and build it right away
    TextureSize  = 1024,           -- max texture size of the props
    IconSize     = 256,            -- chainkit draws an icon for every chain (the studio can take nicer ones)
    LodDistance  = 60,
    Kit = {
        linux   = 'tools/chainkit/linux-x64/chainkit',
        windows = 'tools/chainkit/win-x64/chainkit.exe',
    },
}
