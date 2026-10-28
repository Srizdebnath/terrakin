import 'package:flutter/painting.dart';

import '../core/conditions.dart';
import 'world_data.dart';

/// World colours for the current light and weather. Day is a bright storybook
/// meadow; night drops to the DESIGN.md night tones; weather greys it down.
class Palette {
  Palette._(this.ground, this.land, this.roads, this.waterEdge, this.roof, this.wallLight,
      this.wallDark, this.edge, this.crown, this.crownLight, this.trunk, this.skyTop,
      this.skyHorizon, this.stars);

  final Map<Ground, Color> ground;
  final Color land;
  final Map<Road, Color> roads;
  final Color waterEdge, roof, wallLight, wallDark, edge, crown, crownLight, trunk;
  final Color skyTop, skyHorizon;

  /// 0..1 star visibility.
  final double stars;

  static final _day = Palette._(
    {
      Ground.residential: const Color(0xFFADD493),
      Ground.urban: const Color(0xFFC6D2B0),
      Ground.farmland: const Color(0xFFC2DB84),
      Ground.grass: const Color(0xFF8CCD6F),
      Ground.park: const Color(0xFF72C068),
      Ground.wood: const Color(0xFF58A95C),
      Ground.wetland: const Color(0xFF7DC2A0),
      Ground.sand: const Color(0xFFEADBA6),
      Ground.pitch: const Color(0xFF68C47A),
      Ground.water: const Color(0xFF4CB3E6),
    },
    const Color(0xFF9BD27F),
    {
      Road.rail: const Color(0xFF9C93B3),
      Road.path: const Color(0xFFE9DCB6),
      Road.minor: const Color(0xFFF7F1E2),
      Road.medium: const Color(0xFFFFF6DC),
      Road.major: const Color(0xFFFFEDBE),
    },
    const Color(0xFFA9E2FA),
    const Color(0xFFF4EFFA),
    const Color(0xFFD8CFEA),
    const Color(0xFFAEA3C9),
    const Color(0xFF8A7FA6),
    const Color(0xFF4E9E57),
    const Color(0xFF7CC66E),
    const Color(0xFF8A5A3C),
    const Color(0xFF4FA8EE),
    const Color(0xFFD3EEFF),
    0,
  );

  static final _night = Palette._(
    {
      Ground.residential: const Color(0xFF22343A),
      Ground.urban: const Color(0xFF2A3142),
      Ground.farmland: const Color(0xFF283A2E),
      Ground.grass: const Color(0xFF1F3A2E),
      Ground.park: const Color(0xFF1B392A),
      Ground.wood: const Color(0xFF163125),
      Ground.wetland: const Color(0xFF1C3838),
      Ground.sand: const Color(0xFF39384A),
      Ground.pitch: const Color(0xFF1E3E30),
      Ground.water: const Color(0xFF112C4C),
    },
    const Color(0xFF1D3134),
    {
      Road.rail: const Color(0xFF4A4060),
      Road.path: const Color(0xFF34314E),
      Road.minor: const Color(0xFF3D3960),
      Road.medium: const Color(0xFF4A4572),
      Road.major: const Color(0xFF5D5486),
    },
    const Color(0xFF2E5C85),
    const Color(0xFF433C60),
    const Color(0xFF35304F),
    const Color(0xFF26223A),
    const Color(0xFF1A1628),
    const Color(0xFF1C4632),
    const Color(0xFF2B5D42),
    const Color(0xFF3A2A28),
    const Color(0xFF07061A),
    const Color(0xFF2B2558),
    1,
  );

  static Palette of(Conditions c) {
    final t = c.daylight.clamp(0.0, 1.0);
    final grey = switch (c.sky) {
      Sky.clear => 0.0,
      Sky.partlyCloudy => 0.06,
      Sky.cloudy => 0.22,
      Sky.fog => 0.35,
      Sky.drizzle => 0.28,
      Sky.rain => 0.38,
      Sky.snow => 0.15,
      Sky.storm => 0.55,
    };
    final snow = c.sky == Sky.snow ? 0.5 : 0.0;
    Color g(Color day, Color night) {
      var col = Color.lerp(night, day, t)!;
      if (snow > 0) col = Color.lerp(col, const Color(0xFFEFF3F8), snow * (0.4 + 0.6 * t))!;
      return _grade(col, grey);
    }

    final overcastTop = Color.lerp(const Color(0xFF1A1A2A), const Color(0xFF8E9AAF), t)!;
    final stormTop = Color.lerp(const Color(0xFF0E0E1A), const Color(0xFF4A4E66), t)!;
    var skyTop = Color.lerp(_night.skyTop, _day.skyTop, t)!;
    var skyHorizon = Color.lerp(_night.skyHorizon, _day.skyHorizon, t)!;
    skyHorizon = Color.lerp(skyHorizon, const Color(0xFFFFB27A), c.twilight * 0.75)!;
    skyTop = Color.lerp(skyTop, const Color(0xFF6A5AA8), c.twilight * 0.35)!;
    final skyGrey = grey * 1.6;
    if (c.sky == Sky.storm) {
      skyTop = Color.lerp(skyTop, stormTop, 0.85)!;
      skyHorizon = Color.lerp(skyHorizon, Color.lerp(stormTop, const Color(0xFF9A9AB0), 0.4), 0.8)!;
    } else if (skyGrey > 0) {
      skyTop = Color.lerp(skyTop, overcastTop, (skyGrey).clamp(0, 0.9))!;
      skyHorizon = Color.lerp(skyHorizon, Color.lerp(overcastTop, const Color(0xFFE6E8EE), 0.5),
          (skyGrey * 0.8).clamp(0, 0.85))!;
    }

    return Palette._(
      {for (final k in Ground.values) k: g(_day.ground[k]!, _night.ground[k]!)},
      g(_day.land, _night.land),
      {for (final k in Road.values) k: g(_day.roads[k]!, _night.roads[k]!)},
      g(_day.waterEdge, _night.waterEdge),
      g(_day.roof, _night.roof),
      g(_day.wallLight, _night.wallLight),
      g(_day.wallDark, _night.wallDark),
      g(_day.edge, _night.edge),
      g(_day.crown, _night.crown),
      g(_day.crownLight, _night.crownLight),
      g(_day.trunk, _night.trunk),
      skyTop,
      skyHorizon,
      (1 - t) * (c.sky == Sky.clear || c.sky == Sky.partlyCloudy ? 1 : 0.15),
    );
  }

  /// Desaturates and darkens towards a cool grey.
  static Color _grade(Color c, double amount) {
    if (amount <= 0) return c;
    final l = 0.3 * c.r + 0.59 * c.g + 0.11 * c.b;
    final greyed = Color.from(alpha: 1, red: l * 0.95, green: l * 0.97, blue: l * 1.05 > 1 ? 1 : l * 1.05);
    final mixed = Color.lerp(c, greyed, amount * 0.85)!;
    return Color.lerp(mixed, const Color(0xFF000000), amount * 0.35)!;
  }
}
