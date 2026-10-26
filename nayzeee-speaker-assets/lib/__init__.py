"""nayzeee prop pipeline library (numpy + Pillow only).

Modules:
  mesh       procedural geometry (primitives, transforms, UVs, normals, tangents)
  materials  material registry: GTA shader + textures + PBR equivalents
  textures   procedural texture generators and the shared texture registry
  fonts      Lexend font access (Pillow fonts, text outlines for 3D lettering)
  dds        BC1/BC3 encoder/decoder and DDS writer/reader
  spec       ModelSpec, Anchor, LodSettings, collision shapes (Box/Cylinder/Sphere/Capsule)
  cwxml      CodeWalker XML writers (.ydr.xml, .ytd.xml, .ytyp.xml)
  glb        glTF 2.0 binary writer
  validate   re-parses the XML the way CodeWalker reads it
"""
