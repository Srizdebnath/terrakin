"""Affinity emblems, Grade gems, map markers and brand mark. Writes to art/src/<group>/."""

from pathlib import Path

from style import AFFINITY, INK, flat, shaded, stroke_path

SRC = Path(__file__).resolve().parent.parent / "src"
PAPER, NIGHT, DUSK, SIGNAL = "#F6EFE2", "#141220", "#1F1B30", "#FFB547"

GRADES = {
    "common": ("#9AA0B5", "#737A92", "#CDD1DE"),
    "uncommon": ("#5FBF6A", "#3E9150", "#A8E39B"),
    "rare": ("#4CB3E6", "#2E85B8", "#A9E2FA"),
    "epic": ("#C77DFF", "#9A52D6", "#E8C6FF"),
    "mythic": ("#FFB547", "#E08A1E", "#FFE08A"),
}


def doc(body, size):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" '
            f'width="{size}" height="{size}">{body}</svg>\n')


# Emblem glyphs, drawn in paper colour on a 128 px badge centred at 64,64.
GLYPHS = {
    "grove": '<path d="M40 88 C40 56 60 38 92 36 C92 68 74 88 40 88 Z" {a}/>'
             '<path d="M40 88 L74 54" fill="none" stroke="#231A2E" stroke-width="6" stroke-linecap="round"/>',
    "tide": '<path d="M64 32 C76 52 88 62 88 78 C88 92 77 100 64 100 C51 100 40 92 40 78 C40 62 52 52 64 32 Z" {a}/>',
    "forge": '<path d="M64 30 C78 50 92 58 88 80 C86 94 76 100 64 100 C52 100 42 94 40 80 '
             'C38 66 48 60 52 50 C56 60 60 62 62 62 C60 50 60 42 64 30 Z" {a}/>',
    "rune": '<circle cx="64" cy="64" r="28" {a}/>'
            '<path d="M64 46 L64 82 M52 56 L64 66 L76 56 M54 78 L74 78" fill="none" '
            'stroke="#231A2E" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>',
    "prism": '<polygon points="64,30 92,58 64,100 36,58" {a}/>'
             '<path d="M36 58 L92 58 M52 58 L64 100 L76 58" fill="none" stroke="#231A2E" '
             'stroke-width="5" stroke-linejoin="round"/>',
    "volt": '<polygon points="72,28 40,70 62,70 54,100 88,56 66,56" {a}/>',
    "stone": '<rect x="34" y="40" width="60" height="22" rx="4" {a}/>'
             '<rect x="32" y="66" width="27" height="22" rx="4" {a}/>'
             '<rect x="69" y="66" width="27" height="22" rx="4" {a}/>',
}


def emblem(aff):
    base, shade, _ = AFFINITY[aff]
    badge = shaded('<circle cx="64" cy="64" r="54" {a}/>', base, shade, -6, -6)
    glyph = GLYPHS[aff].replace("{a}", f'fill="{PAPER}" stroke="{INK}" stroke-width="6" stroke-linejoin="round"')
    return doc(badge.replace('stroke-width="12"', 'stroke-width="7"') + glyph, 128)


def gem(grade):
    base, shade, light = GRADES[grade]
    body = '<polygon points="32,6 56,22 50,50 32,60 14,50 8,22" {a}/>'
    top = f'<polygon points="32,6 48,20 32,28 16,20" fill="{light}"/>'
    g = shaded(body, base, shade, -4, -4, top).replace('stroke-width="12"', 'stroke-width="5"')
    return doc(g + stroke_path("M16 20 L32 28 L48 20 M32 28 L32 58", 3, shade)
               + '<circle cx="24" cy="18" r="3" fill="#FFFFFF"/>', 64)


def markers():
    out = {}
    out["player"] = doc(
        f'<circle cx="64" cy="64" r="56" fill="{SIGNAL}" opacity="0.18"/>'
        + flat('<circle cx="64" cy="64" r="30" {a}/>', PAPER, 7)
        + flat('<polygon points="64,40 82,80 64,70 46,80" {a}/>', SIGNAL, 6), 128)
    pin = '<path d="M64 120 C64 120 22 76 22 50 C22 26 41 8 64 8 C87 8 106 26 106 50 C106 76 64 120 64 120 Z" {a}/>'
    out["waypoint"] = doc(
        flat(pin, PAPER, 7)
        + flat('<circle cx="64" cy="50" r="18" {a}/>', SIGNAL, 6), 128)
    ticket = ('<path d="M38 34 H90 V44 A8 8 0 0 0 90 60 V70 H38 V60 A8 8 0 0 0 38 44 Z" {a}/>')
    out["patron"] = doc(
        flat(pin, SIGNAL, 7)
        + flat(ticket, PAPER, 5)
        + stroke_path("M62 38 V66", 4).replace('stroke-linecap="round"', 'stroke-dasharray="4 5"'), 128)
    out["beacon"] = doc(
        f'<circle cx="64" cy="58" r="52" fill="{SIGNAL}" opacity="0.22"/>'
        + f'<circle cx="64" cy="58" r="34" fill="{SIGNAL}" opacity="0.30"/>'
        + flat('<rect x="44" y="96" width="40" height="18" rx="5" {a}/>', DUSK, 6)
        + flat('<path d="M48 96 L44 50 C44 34 84 34 84 50 L80 96 Z" {a}/>', "#FFE08A", 6)
        + flat('<rect x="50" y="18" width="28" height="16" rx="6" {a}/>', DUSK, 6)
        + flat('<path d="M64 52 C72 62 74 70 70 78 C66 84 62 84 58 78 C54 70 56 62 64 52 Z" {a}/>', SIGNAL, 4),
        128)
    return out


def brand():
    import kin
    mossling = kin.mossling()
    inner = mossling[mossling.index(">", mossling.index("<svg")) + 1:mossling.rindex("</svg>")]
    hexagon = "256,52 432,154 432,358 256,460 80,358 80,154"
    icon = doc(
        f'<rect width="512" height="512" fill="{NIGHT}"/>'
        f'<polygon points="{hexagon}" fill="{DUSK}" stroke="{SIGNAL}" stroke-width="18" stroke-linejoin="round"/>'
        f'<g transform="translate(256 270) scale(0.62) translate(-256 -290)">{inner}</g>', 512)
    # Adaptive icon foreground: transparent, content inside the 66% safe zone.
    fg = doc(
        f'<g transform="translate(256 256) scale(0.66) translate(-256 -256)">'
        f'<polygon points="{hexagon}" fill="{DUSK}" stroke="{SIGNAL}" stroke-width="18" stroke-linejoin="round"/>'
        f'<g transform="translate(256 270) scale(0.62) translate(-256 -290)">{inner}</g></g>', 512)
    return {"app-icon": icon, "app-icon-foreground": fg}


if __name__ == "__main__":
    groups = {
        "emblems": {a: emblem(a) for a in AFFINITY},
        "grades": {g: gem(g) for g in GRADES},
        "markers": markers(),
        "brand": brand(),
    }
    for group, files in groups.items():
        (SRC / group).mkdir(parents=True, exist_ok=True)
        for name, content in files.items():
            (SRC / group / f"{name}.svg").write_text(content)
    print("wrote", {g: len(f) for g, f in groups.items()})
