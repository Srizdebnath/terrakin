import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/conditions.dart';

/// Live weather and daylight for the player's real coordinates, anywhere on
/// Earth: Open-Meteo for weather and sun times (timezone resolved from the
/// coordinates), Nominatim for the place name.
class WeatherService extends ChangeNotifier {
  static const _refresh = Duration(minutes: 10);
  static const _moveRefetchMetres = 4000.0;

  Conditions conditions = Conditions.unknown;
  String? place;
  String? country;
  bool live = false;
  DateTime? fetchedAt;

  /// Debug-only override so every sky can be previewed.
  Sky? debugSky;

  LatLng? _at;
  LatLng? _placeAt;
  int? _wmo;
  double _temp = 26, _wind = 5;
  bool? _isDay;
  List<DateTime> _rises = [], _sets = [];
  Timer? _timer;
  bool _busy = false;

  Conditions get effective => debugSky == null ? conditions : conditions.withSky(debugSky!);

  void start(LatLng p) {
    update(p);
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) {
      _recompute();
      final at = _at;
      if (at != null && (fetchedAt == null || DateTime.now().difference(fetchedAt!) > _refresh)) {
        _fetch(at);
      }
    });
  }

  /// Called on every location fix; only refetches after a real move.
  void update(LatLng p) {
    final at = _at;
    if (at == null || const Distance().as(LengthUnit.Meter, at, p) > _moveRefetchMetres) {
      _fetch(p);
    }
    final pa = _placeAt;
    if (pa == null || const Distance().as(LengthUnit.Meter, pa, p) > 1500) _fetchPlace(p);
  }

  void cycleDebugSky() {
    final i = debugSky == null ? 0 : debugSky!.index + 1;
    debugSky = i >= Sky.values.length ? null : Sky.values[i];
    notifyListeners();
  }

  Future<void> _fetch(LatLng p) async {
    if (_busy) return;
    _busy = true;
    _at = p;
    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': p.latitude.toStringAsFixed(3),
        'longitude': p.longitude.toStringAsFixed(3),
        'current': 'temperature_2m,weather_code,wind_speed_10m,is_day',
        'daily': 'sunrise,sunset',
        'timezone': 'auto',
        'past_days': '1',
        'forecast_days': '2',
      });
      final j = await _getJson(uri);
      final cur = j['current'] as Map<String, dynamic>;
      final offset = Duration(seconds: (j['utc_offset_seconds'] as num).toInt());
      _wmo = (cur['weather_code'] as num).toInt();
      _temp = (cur['temperature_2m'] as num).toDouble();
      _wind = (cur['wind_speed_10m'] as num).toDouble();
      _isDay = cur['is_day'] == 1;
      DateTime? utc(Object? s) =>
          s is String && s.isNotEmpty ? DateTime.parse('${s}Z').subtract(offset) : null;
      final daily = j['daily'] as Map<String, dynamic>;
      _rises = [for (final s in daily['sunrise'] as List) ?utc(s)];
      _sets = [for (final s in daily['sunset'] as List) ?utc(s)];
      fetchedAt = DateTime.now();
      live = true;
      _recompute();
    } catch (e) {
      debugPrint('weather fetch failed: $e');
      _at = null; // retry on the next fix
    } finally {
      _busy = false;
    }
  }

  Future<void> _fetchPlace(LatLng p) async {
    _placeAt = p;
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': p.latitude.toStringAsFixed(4),
        'lon': p.longitude.toStringAsFixed(4),
        'zoom': '14',
        'accept-language': 'en',
      });
      final j = await _getJson(uri);
      final a = (j['address'] as Map?)?.cast<String, dynamic>() ?? const {};
      place = a['suburb'] ?? a['town'] ?? a['city'] ?? a['village'] ?? a['county'] ?? a['state'] ?? j['name'];
      country = (a['country_code'] as String?)?.toUpperCase();
      notifyListeners();
    } catch (e) {
      debugPrint('place lookup failed: $e');
      _placeAt = null;
    }
  }

  void _recompute() {
    final wmo = _wmo;
    if (wmo == null) return;
    final now = DateTime.now().toUtc();
    var daylight = (_isDay ?? true) ? 1.0 : 0.0;
    var twilight = 0.0;
    var arc = daylight > 0.5 ? 0.5 : 1.5;

    // Find the sunrise/sunset pair around now. Polar day or night leaves the
    // lists short, in which case is_day alone decides.
    for (var i = 0; i < _rises.length && i < _sets.length; i++) {
      final rise = _rises[i], set = _sets[i];
      final prevSet = i > 0 && i - 1 < _sets.length ? _sets[i - 1] : set.subtract(const Duration(days: 1));
      final nextRise = i + 1 < _rises.length ? _rises[i + 1] : rise.add(const Duration(days: 1));
      if (now.isBefore(prevSet) || now.isAfter(nextRise)) continue;
      double mins(DateTime a, DateTime b) => b.difference(a).inSeconds / 60;
      if (!now.isBefore(rise) && !now.isAfter(set)) {
        arc = mins(rise, now) / max(1, mins(rise, set));
      } else if (now.isAfter(set)) {
        arc = 1 + mins(set, now) / max(1, mins(set, nextRise));
      } else {
        arc = -mins(now, rise) / max(1, mins(prevSet, rise));
      }
      final toRise = mins(rise, now), toSet = mins(now, set);
      daylight = (min(toRise, toSet) / 60 + 0.5).clamp(0.0, 1.0);
      final edge = min(toRise.abs(), toSet.abs());
      twilight = (1 - edge / 50).clamp(0.0, 1.0);
      if (now.isAfter(set)) {
        final nr = mins(now, nextRise);
        twilight = max(twilight, (1 - nr / 50).clamp(0.0, 1.0));
        daylight = max(daylight, (0.5 - nr / 60).clamp(0.0, 1.0));
      }
      if (arc >= -1 && arc <= 2) break;
    }

    conditions = Conditions(
      sky: Sky.fromWmo(wmo),
      tempC: _temp,
      windKmh: _wind,
      daylight: daylight,
      twilight: twilight,
      dayArc: arc,
      latitude: _at?.latitude ?? 0,
    );
    notifyListeners();
  }

  static Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'Terrakin/1.0 (xyz.terrakin.terrakin)');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}', uri: uri);
      final body = await res.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
