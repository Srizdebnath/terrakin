import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Turns raw GPS fixes into a steady position.
///
/// - Kalman smoothing: each fix pulls the estimate in proportion to how much
///   we trust it (its accuracy) versus how far we could have walked since.
/// - Walking vs standing: random jitter scatters fixes on every side of the
///   estimate, while walking leaves them all on one side (ahead). We average
///   the innovation as a vector: when it stops cancelling out, the player is
///   moving and the estimate is allowed to keep up.
/// - Speed: the phone's Doppler speed when it gives one, otherwise how far
///   the fixes travelled over the last ~15 s minus their error. Dividing a
///   single 1 s jump by 1 s turns ±20 m of jitter into "70 km/h".
/// - Outliers: fixes much worse than our estimate, or ones implying an
///   impossible speed, are dropped. Several in a row are accepted, since then
///   the phone really did move (tunnel exit, cold start, car).
class GpsFilter {
  static const _walkMps = 3.0; // brisk walk; how fast the truth can drift
  static const _stillMps = 0.6;
  static const _maxMps = 60.0; // faster than this between fixes is a glitch
  static const _poorFix = 65.0;
  static const _window = Duration(seconds: 15);
  static const _metersPerDegLat = 111320.0;

  double? _lat, _lng; // estimate
  double _variance = -1; // m², <0 until the first fix
  DateTime? _at;
  int _rejected = 0;
  double _speedMps = 0;
  double _driftN = 0, _driftE = 0; // averaged innovation, metres
  final _recent = <(DateTime, double, double, double)>[]; // raw fixes in the window

  LatLng? get position => _lat == null ? null : LatLng(_lat!, _lng!);

  /// Estimated 1-sigma error of [position] in metres.
  double get accuracy => _variance < 0 ? 999 : math.sqrt(_variance);

  /// Smoothed ground speed; jitter and single-fix spikes don't trip the driving lock.
  double get speedKmh => _speedMps * 3.6;

  void reset() {
    _lat = _lng = _at = null;
    _variance = -1;
    _rejected = 0;
    _speedMps = 0;
    _driftN = _driftE = 0;
    _recent.clear();
  }

  /// Feeds one raw fix. [speedMps] is the phone's own speed, or negative when
  /// it has none worth trusting. Returns false when the fix was rejected as noise.
  bool add(double lat, double lng, double accuracy, DateTime at, {double speedMps = -1}) {
    final acc = math.max(accuracy, 3.0);
    if (_variance < 0) {
      _restart(lat, lng, acc, at);
      return true;
    }

    final dt = math.max(at.difference(_at!).inMilliseconds / 1000.0, 0.05);
    final (n, e) = _offset(lat, lng);
    final jump = math.sqrt(n * n + e * e);
    final implied = math.max(0.0, jump - acc - this.accuracy) / dt;
    // Indoors every fix may be ±80 m; only drop ones much worse than what we have.
    final bad = implied > _maxMps || (acc > math.max(_poorFix, 3 * this.accuracy + 20) && jump > acc);
    if (bad && ++_rejected < 4) return false;
    if (bad) {
      // The world moved under us: restart from this fix.
      _restart(lat, lng, acc, at);
      return true;
    }
    _rejected = 0;

    _recent.add((at, lat, lng, acc));
    while (_recent.length > 2 && at.difference(_recent.first.$1) > _window) {
      _recent.removeAt(0);
    }
    final reported = speedMps >= 0 ? speedMps : _windowSpeed();
    if (reported != null) _speedMps += 0.3 * (reported - _speedMps);

    _driftN += 0.25 * (n - _driftN);
    _driftE += 0.25 * (e - _driftE);
    final drifting = math.sqrt(_driftN * _driftN + _driftE * _driftE) > 0.4 * acc;
    final q = drifting || _speedMps > 0.6 ? _walkMps : _stillMps;

    _variance += dt * q * q;
    final k = _variance / (_variance + acc * acc);
    _lat = _lat! + k * (lat - _lat!);
    _lng = _lng! + k * (lng - _lng!);
    _variance = (1 - k) * _variance;
    // The estimate moved by k of the innovation; so did what's left of it.
    _driftN *= 1 - k;
    _driftE *= 1 - k;
    _at = at;
    return true;
  }

  void _restart(double lat, double lng, double acc, DateTime at) {
    _lat = lat;
    _lng = lng;
    _variance = acc * acc;
    _at = at;
    _rejected = 0;
    _speedMps = 0;
    _driftN = _driftE = 0;
    _recent
      ..clear()
      ..add((at, lat, lng, acc));
  }

  /// Distance covered by the raw fixes across the window, less what their
  /// error could explain. Null until the window spans a few seconds.
  double? _windowSpeed() {
    final (t0, lat0, lng0, acc0) = _recent.first;
    final (t1, lat1, lng1, acc1) = _recent.last;
    final dt = t1.difference(t0).inMilliseconds / 1000.0;
    if (dt < 5) return null;
    final dy = (lat1 - lat0) * _metersPerDegLat;
    final dx = (lng1 - lng0) * _metersPerDegLat * math.cos(lat0 * math.pi / 180);
    final d = math.sqrt(dx * dx + dy * dy);
    return math.max(0.0, d - 0.5 * (acc0 + acc1)) / dt;
  }

  /// (north, east) metres from the estimate to a point.
  (double, double) _offset(double lat, double lng) => (
        (lat - _lat!) * _metersPerDegLat,
        (lng - _lng!) * _metersPerDegLat * math.cos(_lat! * math.pi / 180),
      );
}
