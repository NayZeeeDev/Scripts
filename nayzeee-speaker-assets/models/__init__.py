"""Model registry.

Every ``models/<name>.py`` (not starting with "_") is a model.  It must define

    def build(detail: float) -> lib.spec.ModelSpec

and return a spec whose ``name`` equals the module name.  ``detail`` is 1.0 for
the High LOD and ``spec.lod.med_detail`` (default 0.35) for the Medium LOD;
primitives in lib.mesh already scale their segment counts by it, so most
models never need to read the value.  Set ``export=False`` on the spec for
image-only models (GLB + layout, no ydr/ytyp entry).

Registering a model = dropping the file in this folder.
"""
from __future__ import annotations

import importlib
import os
import pkgutil

from lib import mesh
from lib.spec import ModelSpec

_DIR = os.path.dirname(os.path.abspath(__file__))


def names():
    """All model names (sorted)."""
    return sorted(m.name for m in pkgutil.iter_modules([_DIR]) if not m.name.startswith("_"))


def load(name: str):
    mod = importlib.import_module(f"models.{name}")
    if not callable(getattr(mod, "build", None)):
        raise AttributeError(f"models/{name}.py has no build(detail) function")
    return mod


def build(name: str, detail: float = 1.0) -> ModelSpec:
    """Build model ``name`` at ``detail`` (sets the global mesh detail factor)."""
    mod = load(name)
    with mesh.detail(detail):
        spec = mod.build(detail)
    if not isinstance(spec, ModelSpec):
        raise TypeError(f"models/{name}.py build() must return lib.spec.ModelSpec")
    if spec.name != name:
        raise ValueError(f"models/{name}.py returned spec.name={spec.name!r}; it must equal the module name")
    return spec
