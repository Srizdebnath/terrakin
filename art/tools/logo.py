"""Terrakin logo: the mark, the wordmark lockup, a one-colour sticker, and the
app icon built from the mark.

The mark is a pointy-top territory hex (the same orientation as the map's
hexes) with a Mossling peeking up from inside it. Its sprout grows straight
through the top corner and breaks the frame: the Kin is bigger than the land
it lives in. A Monad-purple spark sits off the top-right corner.

Run with fontTools available (only needed to outline the wordmark):
    python art/tools/logo.py && art/tools/render.sh
"""

import math
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ART = Path(__file__).resolve().parent.parent
OUT = ART / "src" / "brand"

INK = "#231A2E"
NIGHT = "#141220"
DUSK = "#1F1B30"
AMBER = "#FFB547"
AMBER_DEEP = "#E08A1E"
PAPER = "#F6EFE2"
MONAD = "#836EF9"
G_BASE, G_SHADE, G_LIGHT = "#5FBF6A", "#3E9150", "#A8E39B"

CX, CY, R = 256, 292, 186  # hex centre and circumradius in a 512 box


def hex_points(cx, cy, r):
    return [(cx + r * math.cos(math.radians(-90 + 60 * k)), cy + r * math.sin(math.radians(-90 + 60 * k))) for k in range(6)]


def pts(p):
    return " ".join(f"{x:.1f},{y:.1f}" for x, y in p)


def spark(x, y, s, colour, stroke=INK):
    """Four-point sparkle."""
    d = (
        f"M{x} {y - s} C{x + s * 0.18} {y - s * 0.18} {x + s * 0.18} {y - s * 0.18} {x + s} {y} "
        f"C{x + s * 0.18} {y + s * 0.18} {x + s * 0.18} {y + s * 0.18} {x} {y + s} "
        f"C{x - s * 0.18} {y + s * 0.18} {x - s * 0.18} {y + s * 0.18} {x - s} {y} "
        f"C{x - s * 0.18} {y - s * 0.18} {x - s * 0.18} {y - s * 0.18} {x} {y - s} Z"
    )
    return f'<path d="{d}" fill="{colour}" stroke="{stroke}" stroke-width="8" stroke-linejoin="round"/>'


def mark(mono=None):
    """The mark in a 512 box. [mono] draws everything in one colour on
    transparent (for stickers and emoji), keeping shapes readable by gaps."""
    outer = hex_points(CX, CY, R)
    inner = hex_points(CX, CY, R - 20)
    ink = mono or INK
    if mono:
        frame = f'<polygon points="{pts(outer)}" fill="none" stroke="{mono}" stroke-width="30" stroke-linejoin="round"/>'
    else:
        frame = (
            f'<polygon points="{pts(outer)}" fill="{DUSK}" stroke="{INK}" stroke-width="44" stroke-linejoin="round"/>'
            f'<polygon points="{pts(outer)}" fill="{DUSK}" stroke="{AMBER}" stroke-width="26" stroke-linejoin="round"/>'
            # Faint map hexes in the background, like the territory grid.
            + "".join(
                f'<polygon points="{pts(hex_points(CX + dx, CY + dy, 46))}" fill="none" stroke="{AMBER}" '
                f'stroke-opacity="0.13" stroke-width="4" stroke-linejoin="round"/>'
                for dx, dy in [(-80, -46), (0, -92), (80, -46), (-80, 46), (80, 46), (0, 0)]
            )
        )

    # Mossling body rising from the bottom of the hex, clipped to the inside.
    body_c = (CX, CY + 96)
    body = f'<ellipse cx="{body_c[0]}" cy="{body_c[1]}" rx="150" ry="132"'
    if mono:
        creature = (
            f'<clipPath id="in"><polygon points="{pts(inner)}"/></clipPath>'
            f'<g clip-path="url(#in)">{body} fill="{mono}"/>'
            # Eyes as cut-outs.
            f'<ellipse cx="{CX - 50}" cy="{CY + 70}" rx="26" ry="32" fill="#000" fill-opacity="0"/></g>'
        )
        eyes = (
            f'<ellipse cx="{CX - 50}" cy="{CY + 66}" rx="24" ry="30" fill="#FFFFFF"/>'
            f'<ellipse cx="{CX + 50}" cy="{CY + 66}" rx="24" ry="30" fill="#FFFFFF"/>'
        )
        creature += eyes
    else:
        creature = (
            f'<clipPath id="in"><polygon points="{pts(inner)}"/></clipPath>'
            f'<clipPath id="bd">{body}/></clipPath>'
            f'<g clip-path="url(#in)">'
            f'{body} fill="{G_SHADE}"/>'
            f'<g clip-path="url(#bd)"><g transform="translate(-20 -20)">{body} fill="{G_BASE}"/></g>'
            f'<ellipse cx="{CX - 96}" cy="{CY + 40}" rx="34" ry="15" fill="{G_LIGHT}" transform="rotate(-28 {CX - 96} {CY + 40})"/>'
            f'<ellipse cx="{CX + 92}" cy="{CY + 118}" rx="26" ry="14" fill="{G_SHADE}"/></g>'
            f'{body} fill="none" stroke="{INK}" stroke-width="12"/>'
            # Eyes, looking up at the sprout.
            + "".join(
                f'<ellipse cx="{x}" cy="{CY + 70}" rx="30" ry="36" fill="#FFFFFF" stroke="{INK}" stroke-width="10"/>'
                f'<ellipse cx="{x + 3}" cy="{CY + 62}" rx="18" ry="24" fill="{INK}"/>'
                f'<circle cx="{x - 5}" cy="{CY + 52}" r="7.5" fill="#FFFFFF"/>'
                for x in (CX - 52, CX + 52)
            )
            + f'<ellipse cx="{CX - 104}" cy="{CY + 118}" rx="20" ry="10" fill="#FF8FA3" opacity="0.6"/>'
            f'<ellipse cx="{CX + 104}" cy="{CY + 118}" rx="20" ry="10" fill="#FF8FA3" opacity="0.6"/>'
            f'<path d="M{CX - 16} {CY + 116} Q{CX} {CY + 132} {CX + 16} {CY + 116}" fill="none" stroke="{INK}" '
            f'stroke-width="8" stroke-linecap="round"/>'
            "</g>"
        )

    # Sprout: stem from the head straight up through the top corner, leaves
    # outside the frame.
    top = CY - R  # y of the top corner
    stem = f"M{CX} {CY - 34} C{CX - 4} {CY - 90} {CX + 6} {top + 40} {CX} {top - 22}"
    left = f"M{CX} {top - 22} C{CX - 26} {top - 86} {CX - 104} {top - 90} {CX - 124} {top - 46} C{CX - 90} {top - 10} {CX - 34} {top - 6} {CX} {top - 22} Z"
    right = f"M{CX} {top - 22} C{CX + 30} {top - 96} {CX + 112} {top - 100} {CX + 130} {top - 54} C{CX + 96} {top - 14} {CX + 36} {top - 8} {CX} {top - 22} Z"
    if mono:
        sprout = (
            f'<path d="{stem}" fill="none" stroke="{mono}" stroke-width="22" stroke-linecap="round"/>'
            f'<path d="{left}" fill="{mono}"/><path d="{right}" fill="{mono}"/>'
        )
    else:
        sprout = (
            f'<path d="{stem}" fill="none" stroke="{INK}" stroke-width="26" stroke-linecap="round"/>'
            f'<path d="{stem}" fill="none" stroke="{G_SHADE}" stroke-width="12" stroke-linecap="round"/>'
            f'<clipPath id="lf"><path d="{left}"/></clipPath><clipPath id="rf"><path d="{right}"/></clipPath>'
            f'<path d="{left}" fill="{G_SHADE}"/><g clip-path="url(#lf)"><g transform="translate(8 -10)"><path d="{left}" fill="{G_BASE}"/></g></g>'
            f'<path d="{right}" fill="{G_BASE}"/><g clip-path="url(#rf)"><g transform="translate(-8 -10)"><path d="{right}" fill="{G_LIGHT}"/></g></g>'
            f'<path d="{left}" fill="none" stroke="{INK}" stroke-width="12" stroke-linejoin="round"/>'
            f'<path d="{right}" fill="none" stroke="{INK}" stroke-width="12" stroke-linejoin="round"/>'
            f'<path d="M{CX - 6} {top - 26} C{CX - 40} {top - 44} {CX - 74} {top - 50} {CX - 100} {top - 48}" fill="none" stroke="{INK}" stroke-width="6" stroke-linecap="round"/>'
            f'<path d="M{CX + 6} {top - 28} C{CX + 44} {top - 50} {CX + 80} {top - 58} {CX + 108} {top - 56}" fill="none" stroke="{INK}" stroke-width="6" stroke-linecap="round"/>'
        )

    sparkle = spark(426, 118, 40, mono or MONAD, stroke=mono or INK) + (
        "" if mono else f'<circle cx="426" cy="118" r="9" fill="#FFFFFF"/>' + spark(468, 186, 18, AMBER)
    )
    return frame + creature + sprout + sparkle


def svg(body, w=512, h=512, bg=None):
    rect = f'<rect width="{w}" height="{h}" fill="{bg}"/>' if bg else ""
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">{rect}{body}</svg>\n'


def wordmark(text, size, x, y, fill, stroke):
    """[text] in Fredoka Bold as outlined paths, left edge at x, baseline y."""
    font = instancer.instantiateVariableFont(TTFont(ART / "fonts" / "Fredoka.ttf"), {"wght": 700, "wdth": 100})
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = size / font["head"].unitsPerEm
    out, cursor = [], x
    for ch in text:
        name = cmap[ord(ch)]
        pen = SVGPathPen(glyphs)
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, cursor, y)))
        out.append(pen.getCommands())
        cursor += glyphs[name].width * scale + size * 0.02  # a touch of tracking
    d = " ".join(out)
    return (
        f'<path d="{d}" fill="none" stroke="{stroke}" stroke-width="{size * 0.16:.1f}" stroke-linejoin="round"/>'
        f'<path d="{d}" fill="{fill}"/>'
    ), cursor - x


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    m = mark()
    (OUT / "logo-mark.svg").write_text(svg(m))
    (OUT / "logo-mark-mono.svg").write_text(svg(mark(mono=PAPER)))
    (OUT / "logo-mark-mono-dark.svg").write_text(svg(mark(mono=INK)))

    # App icon: full bleed night square; foreground: the mark scaled into the
    # adaptive-icon safe zone (66%).
    (OUT / "app-icon.svg").write_text(svg(f'<g transform="translate(256 262) scale(0.86) translate(-256 -262)">{m}</g>', bg=NIGHT))
    (OUT / "app-icon-foreground.svg").write_text(svg(f'<g transform="translate(256 262) scale(0.62) translate(-256 -262)">{m}</g>'))

    # Horizontal lockup: mark + TERRAKIN + tagline, on night and transparent.
    word, wlen = wordmark("TERRAKIN", 150, 0, 0, AMBER, INK)
    tag, tlen = wordmark("own the map", 54, 0, 0, PAPER, INK)
    w, h = 1360, 512
    lock = (
        f'<g transform="translate(20 0)">{m}</g>'
        f'<g transform="translate(540 300)">{word}</g>'
        f'<g transform="translate({540 + (wlen - tlen) / 2:.1f} 392)" opacity="0.85">{tag}</g>'
    )
    (OUT / "logo-lockup.svg").write_text(svg(lock, w, h, bg=NIGHT))
    (OUT / "logo-lockup-transparent.svg").write_text(svg(lock, w, h))
    print("wrote", ", ".join(sorted(p.name for p in OUT.glob("*.svg"))))


if __name__ == "__main__":
    main()
