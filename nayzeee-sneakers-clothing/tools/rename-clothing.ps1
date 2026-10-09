# nayzeee-sneakers-clothing: rename the shoe files you dropped into stream/ to the names this pack needs.
# Run it with RENAME-CLOTHING.bat (double-click). Safe to run again: files that are already right are left alone.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dlc  = 'nayzeee_sneakers'

# Order matters: it has to match the .ymt files in stream/. Don't reorder.
#   Skin = the shoe ships with skin-tone textures (_r.ydd / _whi.ytd)
$shoes = @(
    @{ Ped = 'mp_m_freemode_01'; Folder = '[male]/cup_runner';    Slot = 0; Skin = $false; Textures = 5  },
    @{ Ped = 'mp_m_freemode_01'; Folder = '[male]/fang_5';        Slot = 1; Skin = $false; Textures = 15 },
    @{ Ped = 'mp_m_freemode_01'; Folder = '[male]/backcourt_low'; Slot = 2; Skin = $false; Textures = 3  },
    @{ Ped = 'mp_m_freemode_01'; Folder = '[male]/stack_trainer'; Slot = 3; Skin = $false; Textures = 3  },
    @{ Ped = 'mp_m_freemode_01'; Folder = '[male]/crevis_95';     Slot = 4; Skin = $false; Textures = 9  },
    @{ Ped = 'mp_f_freemode_01'; Folder = '[female]/alice';       Slot = 0; Skin = $false; Textures = 26 },
    @{ Ped = 'mp_f_freemode_01'; Folder = '[female]/bianca';      Slot = 1; Skin = $true;  Textures = 18 },
    @{ Ped = 'mp_f_freemode_01'; Folder = '[female]/maisie';      Slot = 2; Skin = $true;  Textures = 16 },
    @{ Ped = 'mp_f_freemode_01'; Folder = '[female]/omnia';       Slot = 3; Skin = $false; Textures = 9  },
    @{ Ped = 'mp_f_freemode_01'; Folder = '[female]/mia';         Slot = 4; Skin = $false; Textures = 4  }
)

$problems = 0
function Say($colour, $text) { Write-Host $text -ForegroundColor $colour }

Write-Host ''
Say Cyan '  NAYZEEE SNEAKERS - clothing pack'
Write-Host ''

foreach ($s in $shoes) {
    $dir = Join-Path (Join-Path $root 'stream') $s.Folder
    $name = $s.Folder
    if (-not (Test-Path -LiteralPath $dir)) { Say Red "  [x] $name  folder is missing"; $problems++; continue }

    $num    = '{0:D3}' -f $s.Slot
    $prefix = "$($s.Ped)_$dlc^"
    $kind   = if ($s.Skin) { 'r' } else { 'u' }
    $race   = if ($s.Skin) { 'whi' } else { 'uni' }

    $ydds = @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Extension -eq '.ydd' })
    $ytds = @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Extension -eq '.ytd' })

    if ($ydds.Count -eq 0 -and $ytds.Count -eq 0) { Say DarkGray "  [ ] $name  empty, skipped"; continue }
    if ($ydds.Count -ne 1) { Say Red "  [x] $name  needs exactly 1 .ydd, found $($ydds.Count)"; $problems++; continue }

    # model
    $want = "$prefix" + "feet_$($num)_$kind.ydd"
    if ($ydds[0].Name -cne $want) { Rename-Item -LiteralPath $ydds[0].FullName -NewName $want }

    # textures: keep each one's colour letter (feet_diff_003_c_uni.ytd -> c). Anything without a letter
    # is put after them in name order.
    $lettered = @(); $rest = @()
    foreach ($t in $ytds) {
        if ($t.Name -match '_([a-z])_(uni|whi|bla|chi|lat|ara|bal|jam|kor|ita|pak)\.ytd$') {
            $lettered += [pscustomobject]@{ File = $t; Letter = $Matches[1] }
        } else { $rest += $t }
    }
    $ordered = @($lettered | Sort-Object Letter | ForEach-Object { $_.File }) + @($rest | Sort-Object Name)

    $dupes = @($lettered | Group-Object Letter | Where-Object { $_.Count -gt 1 })
    if ($dupes.Count -gt 0) {
        Say Red "  [x] $name  two textures share the letter '$($dupes[0].Name)' - remove one and run again"
        $problems++; continue
    }

    # two passes so a file never gets renamed onto a name another file still has
    $tmp = @()
    for ($i = 0; $i -lt $ordered.Count; $i++) {
        $t = "__nzs_tmp_$i.ytd"
        Rename-Item -LiteralPath $ordered[$i].FullName -NewName $t
        $tmp += $t
    }
    for ($i = 0; $i -lt $tmp.Count; $i++) {
        $letter = [char](97 + $i)
        $final  = "$prefix" + "feet_diff_$($num)_$($letter)_$race.ytd"
        Rename-Item -LiteralPath (Join-Path $dir $tmp[$i]) -NewName $final
    }

    if ($ordered.Count -ne $s.Textures) {
        Say Yellow "  [!] $name  $($ordered.Count) textures, the pack expects $($s.Textures)"
        $problems++
    } else {
        Say Green "  [ok] $name  feet_$num + $($ordered.Count) textures"
    }
}

Write-Host ''
if ($problems -eq 0) { Say Green '  All done. Restart the resource and clear your FiveM cache.' }
else { Say Yellow "  Finished with $problems thing(s) to check (see above)." }
Write-Host ''
