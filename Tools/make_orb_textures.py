"""Generate the round "orb" variant of the glass material into Media/.

    python Tools/make_orb_textures.py

make_textures.py is a byte-for-byte copy of GlassUnitFrames' generator (the
material's owner), so this addon's own textures live here instead. It reuses
that file's primitives (SDF, bands, TGA writer) so the orb is the same
material as the panels, just round: minimap buttons are circles.

Same conventions as make_textures.py: overlays are one RGB colour with the
shape in alpha, masks are white-on-black in RGB and alpha, 64x64, no slicing
(a circle scales uniformly).
"""

import numpy as np

from make_textures import (band, black, coverage, mask, normals, rounded_rect_sdf,
                           white, write_tga)

SIZE = 64
R = SIZE / 2.0 - 0.5          # circle radius: the rounded rect with radius = half size


def orb_sdf(inset=0.5):
    return rounded_rect_sdf(SIZE, SIZE, inset, SIZE / 2.0 - inset)


def orb_rim(k, light):
    """The style-5 rim drawn on a circle.

    Same four layers as glass_rim() (outer lip lit from the top, inner
    catch-light at the bottom, faint slab, glints), but the glints sit on the
    circle at +-45 degrees from the top instead of on rounded-rect corners.
    """
    d = orb_sdf()
    nx, ny = normals(d)
    top, bottom, left = np.maximum(-ny, 0), np.maximum(ny, 0), np.maximum(-nx, 0)
    ys, xs = np.mgrid[0:SIZE, 0:SIZE].astype(np.float64) + 0.5
    outer = band(d, -1.4 * k, -0.3 * k, 0.5) * (0.28 + 0.72 * top ** 0.5 + 0.35 * left ** 1.5 + 0.30 * bottom ** 2)
    inner = band(d, -7.6 * k, -6.6 * k, 0.5) * (0.14 + 0.45 * bottom ** 0.7 + 0.18 * top ** 2)
    vert = 1 - ys / SIZE
    slab = band(d, -7.0 * k, -0.5 * k, 0.6) * (0.05 + 0.13 * vert ** 1.5 + 0.06 * top)
    glint = np.zeros_like(d)
    c, gr = SIZE / 2.0, R - 2.0 * k               # on the arc, just inside the outer lip
    for sx in (-1, 1):
        gx, gy = c + sx * gr * 0.7071, c - gr * 0.7071
        glint += np.exp(-(((xs - gx) ** 2 + (ys - gy) ** 2) / (2 * (2.2 * k) ** 2))) * 0.85
    glint *= band(d, -3.5 * k, -0.2 * k, 0.6)
    rim = white(np.clip(np.maximum.reduce([outer, inner, slab, glint]) * light, 0, 1))
    dark = black(np.clip(band(d, -0.6 * k, 0.3 * k, 0.5) * 0.45 + band(d, -8.8 * k, -7.6 * k, 0.6) * 0.18, 0, 1))
    return rim, dark


def main():
    print("Writing orb textures")
    # Body / icon mask: a full antialiased disc.
    write_tga("orb_mask", mask(coverage(orb_sdf())))
    # Rim at k=1.0: the orb is drawn ~28px from a 64px texture, so the 64px
    # design width lands at ~3px on screen, like rim5 on a panel.
    rim, dark = orb_rim(k=1.0, light=0.85)
    write_tga("orb_rim", rim)
    write_tga("orb_dark", dark)
    # Soft drop shadow: a disc of radius 20 in the 64px square, logistic falloff.
    # Drawn at 1.5x the button so the falloff has room.
    d = rounded_rect_sdf(SIZE, SIZE, 12, 20)
    write_tga("orb_shadow", black(0.5 / (1 + np.exp(d / (4.0 * 0.55)))))


if __name__ == "__main__":
    main()
