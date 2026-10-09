SNEAKERKIT - nayzeee-sneakers
=============================

You do NOT need to run this yourself. The server runs it: /sneakerstudio > 3D props.

It finds every shoe your clothing packs stream (mp_m_freemode_01_<pack>^feet_007_u.ydd and its
feet_diff_007_a_uni.ytd colourways) in your started resources, and turns each colourway into a prop
packed to sit in its shoe box, with inventory icons. They go into nayzeee-sneakers-props, next to
nayzeee-sneakers, which the server then restarts.

  linux-x64/sneakerkit      for Linux servers
  win-x64/sneakerkit.exe    for Windows servers


On Linux the file must be executable. The script sets that itself; if your host blocks it, run:
  chmod +x resources/[nayzeee]/nayzeee-sneakers/tools/sneakerkit/linux-x64/sneakerkit
