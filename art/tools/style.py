"""Shared drawing helpers for Terrakin SVG art (see DESIGN.md section 2)."""

INK = "#231A2E"
SW = 12  # outline width at 512 px

AFFINITY = {
    "grove": ("#5FBF6A", "#3E9150", "#A8E39B"),
    "tide": ("#4CB3E6", "#2E85B8", "#A9E2FA"),
    "forge": ("#FF8A3D", "#D9612A", "#FFC48A"),
    "rune": ("#C9A26B", "#9C7A4A", "#EBD3A8"),
    "prism": ("#C77DFF", "#9A52D6", "#E8C6FF"),
    "volt": ("#FFD93D", "#E0B020", "#FFF0A0"),
    "stone": ("#8E9AAF", "#68748A", "#C5CEDC"),
}

_clip_counter = [0]


def _cid():
    _clip_counter[0] += 1
    return f"c{_clip_counter[0]}"


def svg(body, size=512):
    _clip_counter[0] = 0
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" '
        f'width="{size}" height="{size}">\n{body}\n</svg>\n'
    )


def outline(shape, width=SW):
    return shape.format(
        a=f'fill="none" stroke="{INK}" stroke-width="{width}" '
        f'stroke-linejoin="round" stroke-linecap="round"'
    )


def shaded(shape, base, shade, dx=-18, dy=-20, extra=""):
    """Cel-shaded fill: shade everywhere, base shifted up-left, clipped, then outline.

    `shape` is an SVG element string with an `{a}` placeholder for attributes.
    `extra` is drawn inside the clip (patterns, highlights) before the outline.
    """
    cid = _cid()
    return (
        f'<clipPath id="{cid}">{shape.format(a="")}</clipPath>'
        f'{shape.format(a=f"fill=\"{shade}\"")}'
        f'<g clip-path="url(#{cid})"><g transform="translate({dx} {dy})">'
        f'{shape.format(a=f"fill=\"{base}\"")}</g>{extra}</g>'
        f"{outline(shape)}"
    )


def flat(shape, fill, width=SW):
    return shape.format(
        a=f'fill="{fill}" stroke="{INK}" stroke-width="{width}" '
        f'stroke-linejoin="round" stroke-linecap="round"'
    )


def ground(cx=256, cy=458, rx=130, ry=18):
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{INK}" opacity="0.18"/>'


def highlight(cx, cy, rx, ry, rot, color):
    return (
        f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{color}" '
        f'transform="rotate({rot} {cx} {cy})"/>'
    )


def eye(cx, cy, rx=32, ry=38, look=(5, 7)):
    px, py = cx + look[0], cy + look[1]
    return (
        f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="#FFFFFF" '
        f'stroke="{INK}" stroke-width="10"/>'
        f'<ellipse cx="{px}" cy="{py}" rx="{rx * 0.6:.1f}" ry="{ry * 0.66:.1f}" fill="{INK}"/>'
        f'<circle cx="{px - rx * 0.28:.1f}" cy="{py - ry * 0.3:.1f}" r="{rx * 0.24:.1f}" fill="#FFFFFF"/>'
    )


def stroke_path(d, width=8, color=INK):
    return (
        f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}" '
        f'stroke-linecap="round" stroke-linejoin="round"/>'
    )


def blush(cx, cy, rx=20, ry=10):
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="#FF8FA3" opacity="0.55"/>'


def sparkle(cx, cy, r, fill="#FFFFFF", width=6):
    k = r * 0.28
    d = (
        f"M{cx} {cy - r} Q{cx + k} {cy - k} {cx + r} {cy} Q{cx + k} {cy + k} {cx} {cy + r} "
        f"Q{cx - k} {cy + k} {cx - r} {cy} Q{cx - k} {cy - k} {cx} {cy - r} Z"
    )
    return flat(f'<path d="{d}" {{a}}/>', fill, width)
