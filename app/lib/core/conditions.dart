import 'package:flutter/material.dart';

import 'species.dart';

/// In-game weather, bucketed from WMO codes (Open-Meteo).
enum Sky {
  clear('Clear', Icons.wb_sunny_rounded),
  partlyCloudy('Partly cloudy', Icons.wb_cloudy_outlined),
  cloudy('Overcast', Icons.cloud_rounded),
  fog('Fog', Icons.foggy),
  drizzle('Drizzle', Icons.grain_rounded),
  rain('Rain', Icons.water_drop_rounded),
  snow('Snow', Icons.ac_unit_rounded),
  storm('Thunderstorm', Icons.thunderstorm_rounded);

  const Sky(this.label, this.icon);
  final String label;
  final IconData icon;

  static Sky fromWmo(int code) => switch (code) {
        0 => Sky.clear,
        1 || 2 => Sky.partlyCloudy,
        3 => Sky.cloudy,
        45 || 48 => Sky.fog,
        >= 51 && <= 57 => Sky.drizzle,
        >= 61 && <= 67 || >= 80 && <= 82 => Sky.rain,
        >= 71 && <= 77 || 85 || 86 => Sky.snow,
        >= 95 => Sky.storm,
        _ => Sky.cloudy,
      };

  bool get wet => this == drizzle || this == rain || this == storm;
}

/// Everything about the real world right now that the game reacts to.
class Conditions {
  const Conditions({
    required this.sky,
    required this.tempC,
    required this.windKmh,
    required this.daylight,
    required this.twilight,
    this.dayArc = 0.5,
    this.latitude = 0,
  });

  static const unknown =
      Conditions(sky: Sky.partlyCloudy, tempC: 26, windKmh: 5, daylight: 1, twilight: 0);

  Conditions withSky(Sky s) => Conditions(
      sky: s, tempC: tempC, windKmh: windKmh, daylight: daylight, twilight: twilight, dayArc: dayArc, latitude: latitude);

  final Sky sky;
  final double tempC;
  final double windKmh;

  /// 1 in full day, 0 at night, in between around sunrise and sunset.
  final double daylight;

  /// Peaks at 1 at sunrise and sunset (golden hour).
  final double twilight;

  /// 0 at sunrise, 1 at sunset; 1..2 through the night, and below 0 before dawn.
  final double dayArc;

  /// Where the player is; the sun crosses the north sky south of the equator.
  final double latitude;

  bool get isNight => daylight < 0.25;
  bool get isDay => daylight > 0.75;

  String get timeLabel => isNight
      ? 'Night'
      : twilight > 0.5
          ? (daylight > 0.5 ? 'Golden hour' : 'Dusk')
          : 'Day';

  /// Affinities whose Kin are weather-boosted right now.
  Set<Affinity> get boosted => {
        ...switch (sky) {
          Sky.clear => isNight ? {Affinity.rune} : {Affinity.forge, Affinity.grove},
          Sky.partlyCloudy => {Affinity.grove, Affinity.prism},
          Sky.cloudy => {Affinity.stone},
          Sky.fog => {Affinity.stone, Affinity.rune},
          Sky.drizzle => {Affinity.tide, Affinity.grove},
          Sky.rain => {Affinity.tide},
          Sky.snow => {Affinity.stone, Affinity.prism},
          Sky.storm => {Affinity.volt, Affinity.tide},
        },
        if (isNight) Affinity.rune,
        if (twilight > 0.5) Affinity.prism,
        if (windKmh >= 25) Affinity.volt,
        if (tempC >= 32 && !sky.wet) Affinity.forge,
      };

  /// Kin that sulk in this weather.
  Set<Affinity> get dampened => {
        if (sky.wet || sky == Sky.snow) Affinity.forge,
        if (sky == Sky.clear && isDay && tempC >= 34) Affinity.tide,
      };
}
