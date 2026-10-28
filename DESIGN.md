# Terrakin — Visual Design Plan

Art direction in one line: **a naturalist's field journal brought to life** — chunky, friendly
vector creatures with a thick ink outline, laid over a dark, calm map, framed by warm paper-card UI.

## 1. Principles

1. **Readable at thumb size.** Every Kin must read as a silhouette at 48 px on the map.
2. **The player's photo is the hero.** UI frames the Imprint photo; it never competes with it.
3. **Calm map, loud moments.** The map is muted; colour and motion are saved for spawns, bonds and Claims.
4. **No web3 vocabulary on screen.** Wallet details live only in Settings.
5. **Colour never carries meaning alone.** Affinity and Grade always pair colour with an icon or shape.

## 2. Kin art style

| Rule | Spec |
| --- | --- |
| Master format | SVG, `viewBox 0 0 512 512`, creature centred, ~40 px padding |
| Outline | Ink `#231A2E`, 12 px, round joins and caps |
| Shading | Flat cel: base + one shade (≈ -18% lightness) + one highlight; no gradients |
| Eyes | Large, white sclera, ink pupil, one white catch-light (top-left) |
| Shapes | Rounded primitives, big head-to-body ratio (≈ 1:1), short limbs |
| Affinity cue | One signature feature per Affinity (leaf, fin, ember, glyph, facet, bolt, brick) |
| Ground shadow | Ink ellipse at 18% opacity under the feet |
| Export | PNG 256 px (Flame sprites, map) and 512 px (cards, detail) |

## 3. Colour

### 3.1 UI tokens

| Token | Hex | Use |
| --- | --- | --- |
| ink | `#231A2E` | Outlines, primary text on paper |
| night | `#141220` | App background, map base |
| dusk | `#1F1B30` | Surfaces on dark |
| slate | `#3A3452` | Borders, dividers on dark |
| paper | `#F6EFE2` | Cards, sheets |
| paper-shade | `#E6DBC6` | Card insets |
| mist | `#B9B3CC` | Secondary text on dark |
| signal | `#FFB547` | Primary action, highlights |
| danger | `#FF5D6C` | Claim under threat, errors |

### 3.2 Affinities

| Affinity | Base | Shade | Light | Emblem shape | Signature feature |
| --- | --- | --- | --- | --- | --- |
| Grove | `#5FBF6A` | `#3E9150` | `#A8E39B` | Leaf | Leaf sprouts, moss |
| Tide | `#4CB3E6` | `#2E85B8` | `#A9E2FA` | Droplet | Fins, ripples |
| Forge | `#FF8A3D` | `#D9612A` | `#FFC48A` | Flame | Embers, steam |
| Rune | `#C9A26B` | `#9C7A4A` | `#EBD3A8` | Glyph ring | Carved glyphs, stone |
| Prism | `#C77DFF` | `#9A52D6` | `#E8C6FF` | Diamond facet | Crystal facets |
| Volt | `#FFD93D` | `#E0B020` | `#FFF0A0` | Bolt | Bolts, antennae |
| Stone | `#8E9AAF` | `#68748A` | `#C5CEDC` | Brick | Bricks, rivets |

### 3.3 Grades

Grades are shown by **card frame + gem count**, never colour alone.

| Grade | Frame colour | Gems |
| --- | --- | --- |
| Common | `#9AA0B5` | 1 |
| Uncommon | `#5FBF6A` | 2 |
| Rare | `#4CB3E6` | 3 |
| Epic | `#C77DFF` | 4 |
| Mythic | `#FFB547` | 5, animated glint |

Resonance (0–100) shows as a thin arc meter around the Kin portrait.

## 4. Typography

| Role | Font | Weight | Size (sp) |
| --- | --- | --- | --- |
| Display / Kin names | Fredoka (OFL) | 600 | 28 / 22 |
| Headings | Fredoka | 600 | 18 |
| Body | Inter (OFL) | 400 / 600 | 15 / 13 |
| Numbers / stats | Inter tabular | 600 | 13 |

Both bundled in the APK (no runtime font fetching).

## 5. Map look

- Dark custom style: land `#141220`, roads `#2A2540`, parks `#16301F`, water `#132A3D`, labels `#6E6890`.
- Hexes: 1 px outline `#3A3452` at 40%; held Hexes filled with holder colour at 14%; own Hexes outlined `signal`.
- Patron Hex: dashed `signal` outline + ticket badge.
- Spawns: Kin sprite (64 px) bobbing on a soft Affinity-coloured glow disc.
- Waypoints: paper-coloured pin with category glyph; greyed while on Forage cooldown.
- Player: ink-outlined compass arrow with a 40 m interaction ring.

## 6. Screens

| Screen | Key elements |
| --- | --- |
| Splash / login | Logo over a slow parallax of Kin silhouettes; Google / email / phone buttons |
| Map (home) | Full-bleed map; top: level + Stride; bottom: radar, Atlas, bag, Circle buttons |
| Bond camera | Live camera, Affinity hint chip, shutter; label match shows a green leaf tick |
| Tether | Kin over the frozen photo; shrinking ring, then glyph trace; attempt pips |
| Bond result | Paper card flips in: Imprint photo, Kin, Grade gems, Resonance arc; Share button |
| Atlas | Grid of species slots by Affinity tab; undiscovered = ink silhouette |
| Kin detail | Large art, stats, Stride progress to Ascension, Imprint photo, origin Hex |
| Hex sheet | Bottom sheet: holder, Claim Strength bar, defenders, Patron offer |
| Boons | Ticket-style cards, QR on tap with 60 s ring timer |
| Profile / settings | Badges, stats; wallet + "Testnet" label tucked at the bottom |

## 7. Motion

- Spawn idle: 2 px bob, 1.6 s loop; glow pulse 2.4 s.
- Bond success: card flip 400 ms, gems pop in 80 ms apart, confetti in Affinity colours.
- Hex captured: colour wipe across the hex 600 ms + haptic.
- All motion respects the system "reduce motion" setting.

## 8. Asset inventory (v1)

| Asset | Count | Format | Status |
| --- | --- | --- | --- |
| Kin base forms (MVP starters, 1 per Affinity) | 7 | SVG → PNG 256/512 | Batch 1 |
| Kin base forms (rest of roster) | 35 | SVG → PNG | Later batches |
| Kin ascended forms | 42 | SVG → PNG | Per Cycle |
| Affinity emblems | 7 | SVG → PNG 128 | Batch 1 |
| Grade gems | 5 | SVG → PNG 64 | Batch 1 |
| Map markers (player, Waypoint, Patron, Beacon) | 4 | SVG → PNG 128 | Batch 1 |
| App icon + logo | 2 | SVG → PNG 512, adaptive icon layers | Batch 1 |
| Tether ring parts | 3 | Drawn in code (Flame) | In code |
| UI icons | ~20 | Material Symbols Rounded (font) | Package |

## 9. Kin roster (42)

| Affinity | Species (base forms) |
| --- | --- |
| Grove | **Mossling**, Burrowroot, Fernkit, Thornback, Bloomwisp, Oakmantle |
| Tide | **Ripplet**, Shellmop, Brookfin, Drizzlit, Mistray, Tidecrown |
| Forge | **Emberpup**, Kettlecat, Charbun, Steamhorn, Cindermoth, Hearthwyrm |
| Rune | **Glyphlet**, Pillarkin, Stonescribe, Lampwarden, Sigilowl, Relicorn |
| Prism | **Shardlet**, Hueling, Lumifox, Mosaicrab, Glintwing, Spectrel |
| Volt | **Sparkit**, Railrunner, Zappod, Circuitail, Boltjay, Ampereon |
| Stone | **Pebblet**, Cobblepaw, Bricksnout, Girderbat, Plazagon, Rebarox |

Bold = batch 1 starters.

### Batch 1 character briefs

| Kin | Body | Signature |
| --- | --- | --- |
| Mossling | Round green blob, stubby feet | Two-leaf sprout on head, moss patches |
| Ripplet | Teardrop body, tail fin | Head fin, bubble, ripple belly |
| Emberpup | Pup with floppy ears | Flame tuft head + flame tail tip |
| Glyphlet | Little carved-stone golem, cube head | Glowing glyph on forehead, cracks |
| Shardlet | Gem-bodied critter | Faceted crystal crest, sparkle |
| Sparkit | Squirrel-like, big tail | Bolt-shaped tail, antenna spark |
| Pebblet | Round pebble with tiny arms | Brick pattern back, sprout of rebar |

## 10. Folder layout

```
terrakin/
  DESIGN.md
  art/
    src/            # hand-written SVG masters
      kin/ emblems/ grades/ markers/ brand/
    tools/          # render + contact-sheet scripts
  app/              # Flutter project (later)
    assets/images/  # rendered PNGs land here
```
