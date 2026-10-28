"""Batch 1 Kin: one starter per Affinity. Writes SVG masters to art/src/kin/."""

import math
from pathlib import Path

from style import (
    AFFINITY, INK, blush, eye, flat, ground, highlight, outline, shaded,
    sparkle, stroke_path, svg,
)

OUT = Path(__file__).resolve().parent.parent / "src" / "kin"


def scallop(cx, cy, r, n, bump, start=-90):
    pts = [
        (cx + r * math.cos(math.radians(start + i * 360 / n)),
         cy + r * math.sin(math.radians(start + i * 360 / n)))
        for i in range(n)
    ]
    d = f"M{pts[0][0]:.1f} {pts[0][1]:.1f}"
    for i in range(n):
        a = math.radians(start + (i + 0.5) * 360 / n)
        qx, qy = cx + (r + bump) * math.cos(a), cy + (r + bump) * math.sin(a)
        ex, ey = pts[(i + 1) % n]
        d += f" Q{qx:.1f} {qy:.1f} {ex:.1f} {ey:.1f}"
    return d + " Z"


def mossling():
    base, shade, light = AFFINITY["grove"]
    body = '<ellipse cx="256" cy="310" rx="160" ry="138" {a}/>'
    leaf_l = '<path d="M256 118 C232 62 168 58 150 96 C182 128 228 132 256 118 Z" {a}/>'
    leaf_r = '<path d="M256 118 C284 52 354 50 368 90 C334 124 286 128 256 118 Z" {a}/>'
    moss = "".join(
        f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{shade}"/>'
        for x, y, rx, ry in [(150, 260, 26, 18), (340, 220, 20, 14), (320, 400, 30, 16)]
    )
    return svg(
        ground()
        + stroke_path("M256 186 C256 160 252 140 256 118", 24)
        + stroke_path("M256 186 C256 160 252 140 256 118", 10, shade)
        + shaded(leaf_l, base, shade, 8, -8)
        + shaded(leaf_r, light, base, -8, -8)
        + stroke_path("M252 118 C224 104 196 98 170 98", 6)
        + stroke_path("M262 116 C292 100 322 92 348 92", 6)
        + flat('<ellipse cx="196" cy="438" rx="44" ry="24" {a}/>', shade)
        + flat('<ellipse cx="316" cy="438" rx="44" ry="24" {a}/>', shade)
        + shaded(body, base, shade, -22, -22,
                 moss + highlight(186, 214, 40, 18, -30, light))
        + eye(204, 300) + eye(308, 300)
        + blush(162, 352) + blush(350, 352)
        + stroke_path("M238 352 Q256 370 274 352")
    )


def ripplet():
    base, shade, light = AFFINITY["tide"]
    body = ('<path d="M256 112 C300 186 392 246 392 330 C392 404 332 442 256 442 '
            'C180 442 120 404 120 330 C120 246 212 186 256 112 Z" {a}/>')
    tail = '<path d="M366 372 C414 344 446 352 470 318 C478 380 438 426 376 414 Z" {a}/>'
    flip_l = '<path d="M150 360 C108 352 92 384 110 402 C128 414 150 400 162 384 Z" {a}/>'
    ripples = (stroke_path("M188 398 Q256 424 324 398", 10, light)
               + stroke_path("M214 420 Q256 434 298 420", 8, light))
    return svg(
        ground()
        + shaded(tail, base, shade, -10, -10)
        + shaded(flip_l, base, shade, -8, -8)
        + shaded(body, base, shade, -22, -22,
                 ripples + highlight(214, 220, 34, 16, -50, light))
        + eye(210, 316) + eye(302, 316)
        + f'<ellipse cx="256" cy="372" rx="12" ry="9" fill="{INK}"/>'
        + blush(170, 360) + blush(342, 360)
        + flat('<circle cx="414" cy="176" r="22" {a}/>', light, 8)
        + '<circle cx="407" cy="168" r="6" fill="#FFFFFF"/>'
        + flat('<circle cx="448" cy="130" r="12" {a}/>', light, 7)
    )


def emberpup():
    base, shade, light = AFFINITY["forge"]
    flame = ("M256 64 C282 106 314 118 304 162 C298 180 282 156 270 150 "
             "C274 170 264 176 256 156 C248 176 238 170 242 150 "
             "C230 156 214 180 208 162 C198 118 230 106 256 64 Z")
    tail = '<path d="M344 386 C398 388 424 346 412 306 L438 300 C458 356 424 416 350 414 Z" {a}/>'
    tail_flame = ("M424 236 C440 262 458 270 452 296 C446 312 432 302 426 296 "
                  "C424 306 412 308 410 296 C400 276 412 262 424 236 Z")
    head = '<circle cx="256" cy="250" r="116" {a}/>'
    body = '<ellipse cx="256" cy="364" rx="122" ry="80" {a}/>'
    ear_l = '<path d="M170 196 C120 196 100 280 130 322 C152 334 172 300 188 262 Z" {a}/>'
    ear_r = '<path d="M342 196 C392 196 412 280 382 322 C360 334 340 300 324 262 Z" {a}/>'
    return svg(
        ground()
        + flat(f'<path d="{flame}" {{a}}/>', "#FFB547")
        + f'<path d="M256 108 C268 128 282 138 276 156 C268 150 262 146 256 140 C250 146 244 150 236 156 C230 138 244 128 256 108 Z" fill="#FFE08A"/>'
        + shaded(tail, base, shade, -8, -8)
        + flat(f'<path d="{tail_flame}" {{a}}/>', "#FFB547", 10)
        + shaded(body, base, shade, -16, -18, highlight(256, 380, 60, 34, 0, light))
        + flat('<ellipse cx="200" cy="438" rx="34" ry="20" {a}/>', shade)
        + flat('<ellipse cx="312" cy="438" rx="34" ry="20" {a}/>', shade)
        + shaded(head, base, shade, -20, -20, highlight(206, 176, 34, 16, -30, light))
        + flat('<ellipse cx="256" cy="292" rx="54" ry="36" {a}/>', "#FFE3C4", 10)
        + shaded(ear_l, shade, "#B24C1F", 6, -8)
        + shaded(ear_r, shade, "#B24C1F", -6, -8)
        + eye(208, 236, 28, 34) + eye(304, 236, 28, 34)
        + f'<ellipse cx="256" cy="278" rx="15" ry="11" fill="{INK}"/>'
        + stroke_path("M236 300 Q246 312 256 300 Q266 312 276 300", 7)
    )


def glyphlet():
    base, shade, light = AFFINITY["rune"]
    glow = "#FFD45E"
    head = '<rect x="144" y="104" width="224" height="188" rx="36" {a}/>'
    body = '<rect x="178" y="282" width="156" height="124" rx="30" {a}/>'
    arm_l = '<rect x="128" y="296" width="54" height="86" rx="24" {a}/>'
    arm_r = '<rect x="330" y="296" width="54" height="86" rx="24" {a}/>'
    glyph = (f'<circle cx="256" cy="160" r="30" fill="{glow}" opacity="0.35"/>'
             + stroke_path("M256 136 L256 184 M238 150 L256 166 L274 150 M240 178 L272 178",
                           9, "#8A5A12"))
    cracks = (stroke_path("M332 112 L318 136 L334 150", 6)
              + stroke_path("M160 250 L178 262", 6))
    return svg(
        ground()
        + flat('<rect x="190" y="394" width="58" height="44" rx="16" {a}/>', shade)
        + flat('<rect x="264" y="394" width="58" height="44" rx="16" {a}/>', shade)
        + shaded(arm_l, base, shade, -10, -10)
        + shaded(arm_r, base, shade, -10, -10)
        + shaded(body, base, shade, -16, -16,
                 stroke_path("M206 330 L306 330 M206 360 L306 360", 6, shade))
        + shaded(head, base, shade, -20, -20,
                 highlight(186, 132, 30, 12, -20, light))
        + glyph + cracks
        + eye(212, 226, 26, 30, (4, 5)) + eye(300, 226, 26, 30, (4, 5))
        + stroke_path("M240 270 L272 270", 8)
    )


def shardlet():
    base, shade, light = AFFINITY["prism"]
    gem = '<polygon points="256,128 362,196 384,320 304,434 208,434 128,320 150,196" {a}/>'
    spikes = [
        '<polygon points="214,170 196,92 244,148" {a}/>',
        '<polygon points="244,150 262,54 284,150" {a}/>',
        '<polygon points="282,150 330,96 306,172" {a}/>',
    ]
    facets = (
        f'<polygon points="256,128 330,198 256,236 182,198" fill="{light}"/>'
        f'<polygon points="182,198 256,236 208,434 128,320 150,196" fill="{base}" opacity="0.0"/>'
        + stroke_path("M182 198 L256 236 L330 198 M256 236 L256 270", 5, shade)
    )
    return svg(
        ground()
        + "".join(shaded(s, light if i == 1 else base, shade, -6, -6) for i, s in enumerate(spikes))
        + flat('<ellipse cx="214" cy="440" rx="30" ry="16" {a}/>', shade)
        + flat('<ellipse cx="298" cy="440" rx="30" ry="16" {a}/>', shade)
        + shaded(gem, base, shade, -22, -18, facets)
        + eye(214, 322, 28, 34) + eye(298, 322, 28, 34)
        + stroke_path("M244 372 Q256 382 268 372", 7)
        + sparkle(402, 156, 26) + sparkle(104, 236, 18)
    )


def sparkit():
    base, shade, light = AFFINITY["volt"]
    fluff = f'<path d="{scallop(256, 316, 130, 16, 22)}" {{a}}/>'
    wing_l = '<polygon points="136,280 70,236 104,292 60,312 128,330" {a}/>'
    wing_r = '<polygon points="376,280 442,236 408,292 452,312 384,330" {a}/>'
    bulb = '<circle cx="318" cy="96" r="26" {a}/>'
    return svg(
        ground()
        + shaded(wing_l, base, shade, -6, -6)
        + shaded(wing_r, base, shade, -6, -6)
        + stroke_path("M262 196 C262 140 290 116 312 112", 12)
        + f'<circle cx="318" cy="96" r="48" fill="{light}" opacity="0.6"/>'
        + flat(bulb, "#FFF6C8", 10)
        + stroke_path("M362 70 L382 60 M366 104 L388 110 M330 48 L338 28", 7, "#E0B020")
        + flat('<ellipse cx="208" cy="444" rx="32" ry="18" {a}/>', shade)
        + flat('<ellipse cx="304" cy="444" rx="32" ry="18" {a}/>', shade)
        + shaded(fluff, base, shade, -20, -20,
                 highlight(198, 236, 36, 16, -35, light)
                 + f'<ellipse cx="256" cy="380" rx="70" ry="44" fill="{light}"/>')
        + eye(210, 304) + eye(302, 304)
        + stroke_path("M240 354 Q256 368 272 354", 7)
        + blush(166, 344) + blush(346, 344)
    )


def pebblet():
    base, shade, light = AFFINITY["stone"]
    body = '<ellipse cx="256" cy="316" rx="160" ry="128" {a}/>'
    bricks = (stroke_path("M96 236 L416 236 M96 272 L416 272", 6, shade)
              + stroke_path("M200 200 L200 236 M300 196 L300 236 M150 236 L150 272 "
                            "M250 236 L250 272 M350 236 L350 272", 6, shade))
    bolt = '<rect x="240" y="162" width="32" height="24" rx="6" {a}/>'
    lid = (f'<path d="M172 294 Q206 270 240 294 L240 300 L172 300 Z" fill="{base}"/>'
           f'<path d="M272 294 Q306 270 340 294 L340 300 L272 300 Z" fill="{base}"/>'
           + stroke_path("M174 296 Q206 280 238 296", 8)
           + stroke_path("M274 296 Q306 280 338 296", 8))
    return svg(
        ground(rx=150)
        + flat(bolt, light, 10)
        + stroke_path("M248 162 L264 162", 6)
        + shaded('<ellipse cx="108" cy="350" rx="30" ry="22" {a}/>', base, shade, -6, -6)
        + shaded('<ellipse cx="404" cy="350" rx="30" ry="22" {a}/>', base, shade, -6, -6)
        + shaded(body, base, shade, -22, -20, bricks + highlight(170, 222, 30, 12, -25, light))
        + eye(206, 310, 30, 34, (3, 9)) + eye(306, 310, 30, 34, (3, 9))
        + lid
        + stroke_path("M240 372 Q256 380 272 372", 7)
        + blush(158, 362) + blush(354, 362)
    )


KIN = {
    "mossling": mossling, "ripplet": ripplet, "emberpup": emberpup,
    "glyphlet": glyphlet, "shardlet": shardlet, "sparkit": sparkit,
    "pebblet": pebblet,
}

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in KIN.items():
        (OUT / f"{name}.svg").write_text(fn())
    print(f"wrote {len(KIN)} Kin to {OUT}")
