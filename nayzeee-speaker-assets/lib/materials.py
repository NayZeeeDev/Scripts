"""Material registry: GTA shader + textures + PBR equivalents.

Every mesh part names a material.  A material knows
  * which GTA V shader draws it (``shader``) and the texture name bound to each
    sampler (textures live in the shared txd ``nayzeee_audio_texture``),
  * shader parameter overrides (GTA names, e.g. ``specularIntensityMult``),
  * a PBR description for the glTF previews / image renderer,
  * the default texture repeat size in metres (``tile``) used by UV helpers,
  * the collision material used by collision shapes that do not set one.

Model files can add their own materials:

    from lib import materials as mats
    mats.register(mats.Material("my_red_plastic", "normal_spec",
        textures={"DiffuseSampler": "my_red_d", "BumpSampler": "nz_plastic_n", "SpecSampler": "nz_plastic_s"},
        params={"specularIntensityMult": 0.5},
        pbr=mats.PBR(base_color=(0.6, 0.05, 0.05), roughness=0.45)))

Shader parameter order and defaults below follow the game's shader
definitions (as used by CodeWalker / Sollumz); parameter names are validated
against CodeWalker's ShadersGen9Conversion.xml by lib.validate.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, Optional, Tuple

# --------------------------------------------------------------------------- GTA shaders
POS_NRM_COL_UV = ("Position", "Normal", "Colour0", "TexCoord0")
POS_NRM_COL_UV_TAN = ("Position", "Normal", "Colour0", "TexCoord0", "Tangent")


@dataclass(frozen=True)
class ShaderDef:
    """A GTA V shader as written into the ydr ShaderGroup.

    name/file : ShaderFX Name and FileName (e.g. 'normal_spec', 'normal_spec.sps').
    bucket    : RenderBucket (0 opaque, 1 alpha, 2 decal, 3 cutout).
    layout    : vertex components this shader needs (GTAV1 declaration).
    samplers  : texture parameters in file order.
    params    : (name, (x, y, z, w)) vector parameters in file order with defaults.
    """
    name: str
    file: str
    bucket: int
    layout: Tuple[str, ...]
    samplers: Tuple[str, ...]
    params: Tuple[Tuple[str, Tuple[float, float, float, float]], ...]

    @property
    def param_names(self):
        return [p for p, _ in self.params]

    @property
    def needs_tangents(self) -> bool:
        return "Tangent" in self.layout


_ANIM = (("globalAnimUV1", (0.0, 1.0, 0.0, 0.0)), ("globalAnimUV0", (1.0, 0.0, 0.0, 0.0)))

SHADERS: Dict[str, ShaderDef] = {s.file: s for s in [
    ShaderDef("default", "default.sps", 0, POS_NRM_COL_UV, ("DiffuseSampler",), (
        ("matMaterialColorScale", (1.0, 0.0, 0.0, 1.0)),
        ("HardAlphaBlend", (1.0, 0.0, 0.0, 0.0)),
        ("useTessellation", (0.0, 0.0, 0.0, 0.0)),
        ("wetnessMultiplier", (1.0, 0.0, 0.0, 0.0)),
    ) + _ANIM),
    ShaderDef("spec", "spec.sps", 0, POS_NRM_COL_UV, ("DiffuseSampler", "SpecSampler"), (
        ("HardAlphaBlend", (1.0, 0.0, 0.0, 0.0)),
        ("useTessellation", (0.0, 0.0, 0.0, 0.0)),
        ("wetnessMultiplier", (1.0, 0.0, 0.0, 0.0)),
        ("specMapIntMask", (1.0, 0.0, 0.0, 0.0)),
        ("specularIntensityMult", (1.0, 0.0, 0.0, 0.0)),
        ("specularFalloffMult", (100.0, 0.0, 0.0, 0.0)),
        ("specularFresnel", (0.97, 0.0, 0.0, 0.0)),
    ) + _ANIM),
    ShaderDef("normal_spec", "normal_spec.sps", 0, POS_NRM_COL_UV_TAN,
              ("DiffuseSampler", "BumpSampler", "SpecSampler"), (
        ("HardAlphaBlend", (1.0, 0.0, 0.0, 0.0)),
        ("useTessellation", (0.0, 0.0, 0.0, 0.0)),
        ("wetnessMultiplier", (1.0, 0.0, 0.0, 0.0)),
        ("bumpiness", (1.0, 0.0, 0.0, 0.0)),
        ("specMapIntMask", (1.0, 0.0, 0.0, 0.0)),
        ("specularIntensityMult", (1.0, 0.0, 0.0, 0.0)),
        ("specularFalloffMult", (100.0, 0.0, 0.0, 0.0)),
        ("specularFresnel", (0.75, 0.0, 0.0, 0.0)),
    )),
    ShaderDef("emissive", "emissive.sps", 0, POS_NRM_COL_UV, ("DiffuseSampler",), (
        ("matMaterialColorScale", (1.0, 0.0, 0.0, 1.0)),
        ("HardAlphaBlend", (1.0, 0.0, 0.0, 0.0)),
        ("useTessellation", (0.0, 0.0, 0.0, 0.0)),
        ("emissiveMultiplier", (1.0, 0.0, 0.0, 0.0)),
    ) + _ANIM),
    ShaderDef("emissivestrong", "emissivestrong.sps", 0, POS_NRM_COL_UV, ("DiffuseSampler",), (
        ("matMaterialColorScale", (1.0, 0.0, 0.0, 1.0)),
        ("HardAlphaBlend", (1.0, 0.0, 0.0, 0.0)),
        ("useTessellation", (0.0, 0.0, 0.0, 0.0)),
        ("emissiveMultiplier", (16.0, 0.0, 0.0, 0.0)),
    ) + _ANIM),
    ShaderDef("decal", "decal.sps", 2, POS_NRM_COL_UV, ("DiffuseSampler",), (
        ("useTessellation", (0.0, 0.0, 0.0, 0.0)),
        ("wetnessMultiplier", (1.0, 0.0, 0.0, 0.0)),
        ("specularIntensityMult", (0.0, 0.0, 0.0, 0.0)),
        ("specularFalloffMult", (100.0, 0.0, 0.0, 0.0)),
        ("specularFresnel", (0.97, 0.0, 0.0, 0.0)),
    )),
    ShaderDef("normal_spec_decal", "normal_spec_decal.sps", 2, POS_NRM_COL_UV_TAN,
              ("DiffuseSampler", "BumpSampler", "SpecSampler"), (
        ("useTessellation", (0.0, 0.0, 0.0, 0.0)),
        ("wetnessMultiplier", (1.0, 0.0, 0.0, 0.0)),
        ("bumpiness", (1.0, 0.0, 0.0, 0.0)),
        ("specMapIntMask", (1.0, 0.0, 0.0, 0.0)),
        ("specularIntensityMult", (1.0, 0.0, 0.0, 0.0)),
        ("specularFalloffMult", (15.0, 0.0, 0.0, 0.0)),
        ("specularFresnel", (0.97, 0.0, 0.0, 0.0)),
    ) + _ANIM),
]}


def shader(name_or_file: str) -> ShaderDef:
    """Look up a shader by name ('normal_spec') or file ('normal_spec.sps')."""
    key = name_or_file if name_or_file.endswith(".sps") else name_or_file + ".sps"
    if key not in SHADERS:
        raise KeyError(f"unknown shader {name_or_file!r}; known: {sorted(SHADERS)}")
    return SHADERS[key]


# --------------------------------------------------------------------------- PBR description
@dataclass
class PBR:
    """glTF metallic-roughness description of a material.

    base_color is linear RGB multiplied with the diffuse texture (keep it at 1
    when the texture carries the colour).  emissive is linear RGB; strength is
    emitted as KHR_materials_emissive_strength.  alpha_mode: OPAQUE|BLEND|MASK.
    """
    base_color: Tuple[float, float, float] = (1.0, 1.0, 1.0)
    metallic: float = 0.0
    roughness: float = 0.5
    emissive: Tuple[float, float, float] = (0.0, 0.0, 0.0)
    emissive_strength: float = 1.0
    alpha_mode: str = "OPAQUE"
    double_sided: bool = False
    normal_scale: float = 1.0


# --------------------------------------------------------------------------- Material
COLLISION_MATERIALS = {
    # GTA V materials.dat indices (BoundMaterial Type)
    "DEFAULT": 0, "METAL_SOLID_SMALL": 55, "METAL_SOLID_MEDIUM": 56, "METAL_HOLLOW_SMALL": 58,
    "METAL_HOLLOW_MEDIUM": 59, "WOOD_SOLID_SMALL": 69, "WOOD_SOLID_MEDIUM": 70, "WOOD_SOLID_POLISHED": 72,
    "PLASTIC": 86, "PLASTIC_HOLLOW": 87, "PLASTIC_HIGH_DENSITY": 88, "FIBREGLASS_HOLLOW": 92, "RUBBER": 93,
    "RUBBER_HOLLOW": 94, "CARPET_SOLID": 97, "CARDBOARD_SHEET": 103, "CARDBOARD_BOX": 104, "PAPER": 105,
    "LEATHER": 109, "GLASS_OPAQUE": 114, "EMISSIVE_PLASTIC": 132,
}


@dataclass
class Material:
    """A named surface: GTA shader binding + PBR equivalent.

    name      : registry key used by mesh parts (lowercase, no spaces).
    shader    : GTA shader name ('normal_spec', 'spec', 'default', 'emissive', 'decal', ...).
    textures  : {sampler: texture name} -- names must be registered in lib.textures.
    params    : shader parameter overrides {gta_param_name: float | (x,y,z,w)}.
    pbr       : PBR description for glTF / renderer.
    tile      : metres covered by one texture repeat (UV helpers use it).
    collision : default collision material name (see COLLISION_MATERIALS).
    """
    name: str
    shader: str
    textures: Dict[str, str] = field(default_factory=dict)
    params: Dict[str, object] = field(default_factory=dict)
    pbr: PBR = field(default_factory=PBR)
    tile: float = 0.25
    collision: str = "PLASTIC"
    description: str = ""

    @property
    def shader_def(self) -> ShaderDef:
        return shader(self.shader)

    def shader_params(self):
        """Full ordered parameter list [(name, 'Texture', texname) | (name, 'Vector', (x,y,z,w))]."""
        sd = self.shader_def
        out = []
        for s in sd.samplers:
            if s not in self.textures:
                raise KeyError(f"material {self.name!r}: shader {sd.name} needs a texture for {s}")
            out.append((s, "Texture", self.textures[s]))
        lower = {k.lower(): v for k, v in self.params.items()}
        for pname, default in sd.params:
            v = lower.get(pname.lower(), default)
            if isinstance(v, (int, float)):
                v = (float(v), 0.0, 0.0, 0.0)
            v = tuple(float(x) for x in v) + (0.0,) * (4 - len(tuple(v)))
            out.append((pname, "Vector", v[:4]))
        unknown = set(lower) - {p.lower() for p, _ in sd.params}
        if unknown:
            raise KeyError(f"material {self.name!r}: {sorted(unknown)} are not parameters of {sd.file}")
        return out

    def texture_names(self):
        return list(self.textures.values())

    @property
    def diffuse(self) -> Optional[str]:
        return self.textures.get("DiffuseSampler")

    @property
    def normal(self) -> Optional[str]:
        return self.textures.get("BumpSampler")

    @property
    def spec(self) -> Optional[str]:
        return self.textures.get("SpecSampler")


_REGISTRY: Dict[str, Material] = {}


def register(mat: Material, replace: bool = False) -> Material:
    """Add a material to the registry (model files may call this at import)."""
    if mat.name in _REGISTRY and not replace:
        raise KeyError(f"material {mat.name!r} already registered (pass replace=True)")
    shader(mat.shader)  # validates the shader name
    _REGISTRY[mat.name] = mat
    return mat


def get(name: str) -> Material:
    if name not in _REGISTRY:
        raise KeyError(f"unknown material {name!r}; known: {sorted(_REGISTRY)}")
    return _REGISTRY[name]


def names():
    return list(_REGISTRY)


def all_materials():
    return list(_REGISTRY.values())


def _ns(name, diffuse, normal, spec, tile, pbr, collision="PLASTIC", description="", **params):
    return register(Material(name, "normal_spec",
                             {"DiffuseSampler": diffuse, "BumpSampler": normal, "SpecSampler": spec},
                             params, pbr, tile, collision, description))


# --------------------------------------------------------------------------- starter set
# Plastics -------------------------------------------------------------------
_ns("matte_black_plastic", "nz_plastic_black_d", "nz_plastic_n", "nz_plastic_s", 0.12,
    PBR(roughness=0.62), "PLASTIC", "Moulded near-black ABS with a fine orange-peel texture.",
    specularIntensityMult=0.32, specularFalloffMult=38.0, specularFresnel=0.9, bumpiness=0.7)
_ns("satin_graphite", "nz_plastic_graphite_d", "nz_plastic_n", "nz_plastic_s", 0.12,
    PBR(roughness=0.42), "PLASTIC", "Satin dark-grey plastic for main housings.",
    specularIntensityMult=0.55, specularFalloffMult=70.0, specularFresnel=0.92, bumpiness=0.6)
_ns("gloss_black_plastic", "nz_plastic_black_d", "nz_plastic_n", "nz_plastic_s", 0.12,
    PBR(roughness=0.16), "PLASTIC", "Piano-gloss black trim.",
    specularIntensityMult=1.0, specularFalloffMult=260.0, specularFresnel=0.96, bumpiness=0.15)
_ns("teal_plastic", "nz_plastic_teal_d", "nz_plastic_n", "nz_plastic_s", 0.12,
    PBR(roughness=0.38), "PLASTIC", "nayzeee teal accent plastic (#08afa2).",
    specularIntensityMult=0.6, specularFalloffMult=80.0, specularFresnel=0.92, bumpiness=0.5)
_ns("white_plastic", "nz_plastic_white_d", "nz_plastic_n", "nz_plastic_s", 0.12,
    PBR(roughness=0.4), "PLASTIC", "Off-white plastic (buttons, stylus guards).",
    specularIntensityMult=0.5, specularFalloffMult=70.0, specularFresnel=0.92, bumpiness=0.5)

# Rubber ---------------------------------------------------------------------
_ns("rubber", "nz_rubber_d", "nz_rubber_n", "nz_spec_low", 0.06,
    PBR(roughness=0.86), "RUBBER", "Soft-touch black rubber (feet, bumpers, corners).",
    specularIntensityMult=0.18, specularFalloffMult=14.0, specularFresnel=0.8, bumpiness=0.8)
_ns("rubber_grip", "nz_rubber_d", "nz_rubber_knurl_n", "nz_spec_low", 0.03,
    PBR(roughness=0.82), "RUBBER", "Diamond-knurled rubber for handle grips and knob sides.",
    specularIntensityMult=0.2, specularFalloffMult=16.0, specularFresnel=0.8, bumpiness=1.0)

# Grilles --------------------------------------------------------------------
_ns("speaker_grille_metal", "nz_grille_hex_d", "nz_grille_hex_n", "nz_grille_hex_s", 0.064,
    PBR(metallic=0.55, roughness=0.42), "METAL_SOLID_SMALL",
    "Powder-coated steel grille with hexagonal perforations (holes read as dark).",
    specularIntensityMult=0.7, specularFalloffMult=55.0, specularFresnel=0.9, bumpiness=1.0)
_ns("speaker_grille_round", "nz_grille_round_d", "nz_grille_round_n", "nz_grille_round_s", 0.064,
    PBR(metallic=0.55, roughness=0.42), "METAL_SOLID_SMALL",
    "Powder-coated steel grille with staggered round holes.",
    specularIntensityMult=0.7, specularFalloffMult=55.0, specularFresnel=0.9, bumpiness=1.0)
_ns("fabric_grille_dark", "nz_fabric_d", "nz_fabric_n", "nz_fabric_s", 0.05,
    PBR(roughness=0.95), "CARPET_SOLID", "Charcoal acoustic cloth, plain weave.",
    specularIntensityMult=0.12, specularFalloffMult=8.0, specularFresnel=0.7, bumpiness=1.2)

# Metals ---------------------------------------------------------------------
_ns("brushed_aluminium", "nz_brushed_d", "nz_brushed_n", "nz_brushed_s", 0.15,
    PBR(metallic=1.0, roughness=0.32), "METAL_SOLID_SMALL",
    "Linear brushed aluminium (brushing runs along the texture U axis).",
    specularIntensityMult=1.0, specularFalloffMult=160.0, specularFresnel=0.97, bumpiness=0.6)
_ns("brushed_aluminium_radial", "nz_radial_d", "nz_radial_n", "nz_radial_s", 1.0,
    PBR(metallic=1.0, roughness=0.3), "METAL_SOLID_SMALL",
    "Concentric (spun) brushed aluminium for knob caps / platter rims; map with uv_radial().",
    specularIntensityMult=1.0, specularFalloffMult=180.0, specularFresnel=0.97, bumpiness=0.8)
register(Material("chrome", "spec", {"DiffuseSampler": "nz_chrome_d", "SpecSampler": "nz_spec_full"},
                  {"specularIntensityMult": 1.0, "specularFalloffMult": 420.0, "specularFresnel": 0.98},
                  PBR(metallic=1.0, roughness=0.07), 1.0, "METAL_SOLID_SMALL",
                  "Polished chrome (spindle, tonearm tube, antenna)."))
_ns("gunmetal", "nz_gunmetal_d", "nz_metal_fine_n", "nz_gunmetal_s", 0.12,
    PBR(metallic=0.9, roughness=0.38), "METAL_SOLID_SMALL", "Dark bead-blasted gunmetal.",
    specularIntensityMult=0.8, specularFalloffMult=110.0, specularFresnel=0.95, bumpiness=0.6)

# Wood / textiles --------------------------------------------------------------
_ns("walnut", "nz_walnut_d", "nz_walnut_n", "nz_walnut_s", 0.6,
    PBR(roughness=0.45), "WOOD_SOLID_POLISHED", "Satin-lacquered walnut veneer (grain along U).",
    specularIntensityMult=0.45, specularFalloffMult=60.0, specularFresnel=0.93, bumpiness=0.6)
_ns("felt_black", "nz_felt_d", "nz_felt_n", "nz_spec_low", 0.08,
    PBR(roughness=1.0), "CARPET_SOLID", "Black felt slipmat.",
    specularIntensityMult=0.05, specularFalloffMult=4.0, specularFresnel=0.6, bumpiness=1.0)

# Records ----------------------------------------------------------------------
_ns("vinyl_black", "nz_vinyl_d", "nz_vinyl_n", "nz_vinyl_s", 1.0,
    PBR(roughness=0.16), "PLASTIC",
    "Glossy black vinyl; the grooves texture spans the whole 12in disc -> map with uv_radial(0.1515).",
    specularIntensityMult=1.0, specularFalloffMult=230.0, specularFresnel=0.95, bumpiness=1.0)
_ns("vinyl_label", "nayzeee_vinyl_label", "nz_paper_n", "nz_spec_low", 1.0,
    PBR(roughness=0.6), "PAPER",
    "Printed centre label. Texture nayzeee_vinyl_label is runtime-replaceable; map with uv_radial(0.050).",
    specularIntensityMult=0.25, specularFalloffMult=22.0, specularFresnel=0.85, bumpiness=0.35)
for _c in "abc":
    _ns(f"sleeve_cover_{_c}", f"nayzeee_cover_{_c}", "nz_paper_n", "nz_paper_s", 1.0,
        PBR(roughness=0.5), "CARDBOARD_SHEET",
        f"Record sleeve front print; texture nayzeee_cover_{_c} is runtime-replaceable (UV 0..1).",
        specularIntensityMult=0.3, specularFalloffMult=30.0, specularFresnel=0.88, bumpiness=0.4)
_ns("sleeve_card", "nz_sleeve_card_d", "nz_paper_n", "nz_paper_s", 0.32,
    PBR(roughness=0.7), "CARDBOARD_SHEET", "Black card stock for sleeve back/edges.",
    specularIntensityMult=0.18, specularFalloffMult=18.0, specularFresnel=0.85, bumpiness=0.5)

# Light emitters ---------------------------------------------------------------
for _n, _tex, _col, _mult in (("led_teal", "nz_led_teal_e", (0.05, 0.72, 0.65), 6.0),
                              ("led_amber", "nz_led_amber_e", (1.0, 0.55, 0.12), 6.0),
                              ("led_red", "nz_led_red_e", (1.0, 0.12, 0.12), 6.0),
                              ("led_white", "nz_led_white_e", (0.9, 0.95, 1.0), 5.0)):
    register(Material(_n, "emissive", {"DiffuseSampler": _tex}, {"emissiveMultiplier": _mult},
                      PBR(base_color=_col, roughness=0.3, emissive=_col, emissive_strength=_mult),
                      1.0, "EMISSIVE_PLASTIC", f"Emissive indicator / light strip ({_n})."))
register(Material("vu_meter_amber", "emissive", {"DiffuseSampler": "nz_vu_amber_e"}, {"emissiveMultiplier": 1.6},
                  PBR(roughness=0.5, emissive=(1.0, 1.0, 1.0), emissive_strength=1.6), 1.0, "EMISSIVE_PLASTIC",
                  "Back-lit amber VU meter face (UV 0..1 over the face, 2:1 aspect)."))

# Glass / screens --------------------------------------------------------------
register(Material("screen_glass_dark", "spec", {"DiffuseSampler": "nz_glass_dark_d", "SpecSampler": "nz_spec_full"},
                  {"specularIntensityMult": 1.0, "specularFalloffMult": 320.0, "specularFresnel": 0.97},
                  PBR(base_color=(1.0, 1.0, 1.0), roughness=0.05), 0.3, "GLASS_OPAQUE",
                  "Opaque smoked glass for displays / dust covers."))

# Printed graphics (decals: draw as a quad 0.3-0.5 mm above the surface) ---------
register(Material("print_decal", "decal", {"DiffuseSampler": "nz_print_atlas"}, {},
                  PBR(roughness=0.5, alpha_mode="BLEND"), 1.0, "PLASTIC",
                  "Silkscreen prints / logos from the nz_print_atlas (use textures.atlas_rect())."))
