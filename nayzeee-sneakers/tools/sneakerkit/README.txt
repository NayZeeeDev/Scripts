SNEAKERKIT - nayzeee-sneakers
=============================

You do NOT need to run this yourself. The server runs it in the background (on start, and from
/sneakerstudio > 3D props).

If your server can't run it (no add_unsafe_child_process_permission), do it by hand instead:
double-click sneakerkit.exe (win-x64) inside your server's resources. It finds the resources folder by
itself, scans every clothing pack and builds the props into nayzeee-sneakers-props, right next to
nayzeee-sneakers, and copies the icons into ox_inventory. Then restart the server.

It finds every shoe your clothing packs stream (mp_m_freemode_01_<pack>^feet_007_u.ydd and its
feet_diff_007_a_uni.ytd colourways) in your started resources, and turns each colourway into a prop
packed to sit in its shoe box, with inventory icons. They go into nayzeee-sneakers-props, next to
nayzeee-sneakers, which the server then restarts.

  linux-x64/sneakerkit      for Linux servers
  win-x64/sneakerkit.exe    for Windows servers


On Linux the file must be executable. The script sets that itself; if your host blocks it, run:
  chmod +x resources/[nayzeee]/nayzeee-sneakers/tools/sneakerkit/linux-x64/sneakerkit
