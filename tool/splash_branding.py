#!/usr/bin/env python3
"""Writes the splash's "Libri" wordmark as Android vector drawables.

The system splash on Android 12 and later cannot draw text, so the name
near the bottom of F1 is the outlines of "Libri" in the bundled Bricolage
Grotesque Bold at 22 dp, centered in the 200 by 80 dp branding image. Run
from the project root after changing the font or the size:

    python3 tool/splash_branding.py

Needs fontTools (pip install fonttools).
"""

import re
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

FONT = Path('assets/fonts/bricolage-grotesque/BricolageGrotesque-Bold.ttf')
RES = Path('android/app/src/main/res')
TEXT = 'Libri'
SIZE = 22.0  # dp, as on F1
TRACKING = -0.01 * SIZE  # F1's letter-spacing of -0.01em
BOX = (200, 80)  # the branding image's size in dp
FILLS = {'drawable': '#17181B', 'drawable-night': '#EEF0F2'}


def kerning(font, first, second):
    """The GPOS pair adjustment between two glyphs, in font units."""
    if 'GPOS' not in font:
        return 0
    for lookup in font['GPOS'].table.LookupList.Lookup:
        if lookup.LookupType != 2:
            continue
        for table in lookup.SubTable:
            if first not in table.Coverage.glyphs:
                continue
            if table.Format == 1:
                pairs = table.PairSet[table.Coverage.glyphs.index(first)]
                for record in pairs.PairValueRecord:
                    if record.SecondGlyph == second and record.Value1:
                        return record.Value1.XAdvance or 0
            elif table.Format == 2:
                class1 = table.ClassDef1.classDefs.get(first, 0)
                class2 = table.ClassDef2.classDefs.get(second, 0)
                value = table.Class1Record[class1].Class2Record[class2].Value1
                if value and value.XAdvance:
                    return value.XAdvance
    return 0


def main():
    font = TTFont(FONT)
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = SIZE / font['head'].unitsPerEm
    names = [cmap[ord(c)] for c in TEXT]
    placed, x = [], 0.0
    for i, name in enumerate(names):
        placed.append((name, x))
        x += glyphs[name].width
        if i + 1 < len(names):
            x += kerning(font, name, names[i + 1]) + TRACKING / scale
    bounds = BoundsPen(glyphs)
    for name, gx in placed:
        glyphs[name].draw(TransformPen(bounds, (1, 0, 0, 1, gx, 0)))
    xmin, ymin, xmax, ymax = bounds.bounds
    width, height = (xmax - xmin) * scale, (ymax - ymin) * scale
    tx = (BOX[0] - width) / 2 - xmin * scale
    ty = (BOX[1] - height) / 2 + ymax * scale
    pen = SVGPathPen(glyphs)
    for name, gx in placed:
        glyphs[name].draw(
            TransformPen(pen, (scale, 0, 0, -scale, gx * scale + tx, ty))
        )
    data = re.sub(r'(\d\.\d{2})\d+', r'\1', pen.getCommands())
    for folder, fill in FILLS.items():
        (RES / folder / 'splash_branding.xml').write_text(
            f'''<?xml version="1.0" encoding="utf-8"?>
<!-- "Libri" in Bricolage Grotesque Bold at {SIZE:g} dp, as outlines, for the
     splash (F1): the system splash's branding image at the bottom on
     Android 12 and later, and the launch background before that. Made by
     tool/splash_branding.py from the bundled font; do not edit by hand. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="{BOX[0]}dp"
    android:height="{BOX[1]}dp"
    android:viewportWidth="{BOX[0]}"
    android:viewportHeight="{BOX[1]}">
    <path
        android:fillColor="{fill}"
        android:pathData="{data}"/>
</vector>
'''
        )
    print(f'wrote {len(FILLS)} drawables, ink {width:.1f} by {height:.1f} dp')


if __name__ == '__main__':
    main()
