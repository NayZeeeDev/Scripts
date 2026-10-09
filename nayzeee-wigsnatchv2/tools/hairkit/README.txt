HAIRKIT - Wig Snatch V2
=======================

You do NOT need to run this for your server's own hair packs.
The server runs it by itself: /wigstudio > 3D wigs.

You only run it once, on your own Windows PC that has GTA V installed, to turn
GTA's base game + DLC hairstyles into props:

  1. Open this folder:  nayzeee-wigsnatchv2\tools\hairkit\win-x64
  2. Double-click hairkit.exe
     (If Windows says "Windows protected your PC": More info > Run anyway.)
  3. It finds GTA V by itself. Press Enter. (Or paste your GTA V folder, the one with GTA5.exe.)
  4. Press Enter to start and wait a few minutes. Don't close the window.
  5. When it says "Done", a folder called nzw_hairprops is next to nayzeee-wigsnatchv2.
  6. Upload nzw_hairprops to your server's resources folder (next to nayzeee-wigsnatchv2),
     replacing the old one, and restart the server.

Prefer Command Prompt? Open it (Start > type cmd > Enter), then run these two lines,
changing the paths to yours:

  cd /d "C:\path\to\nayzeee-wigsnatchv2\tools\hairkit\win-x64"
  hairkit.exe game --gta "C:\Program Files\Rockstar Games\Grand Theft Auto V" --out "C:\path\to\nzw_hairprops"

GTA V is usually in one of these:
  Rockstar launcher:  C:\Program Files\Rockstar Games\Grand Theft Auto V
  Steam:              C:\Program Files (x86)\Steam\steamapps\common\Grand Theft Auto V
  Epic Games:         C:\Program Files\Epic Games\GTAV
