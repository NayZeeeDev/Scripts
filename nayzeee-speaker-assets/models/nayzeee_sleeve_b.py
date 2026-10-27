"""nayzeee_sleeve_b -- record sleeve B for the record shop display (front texture nayzeee_cover_b).

Geometry, cover art and contract notes live in models/_sleeve.py (sleeves a/b/c are identical apart
from the cover texture, so the shop can show three different covers at once).
"""
from models._sleeve import build_sleeve


def build(detail: float):
    return build_sleeve("b")
