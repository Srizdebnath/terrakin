import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Turns raw GPS fixes into a steady position.
///
/// - Kalman smoothing: each fix pulls the estimate in proportion to how much
///   we trust it (its accuracy) versus how far we could have walked since.
/// - Outliers: fixes much worse than our estimate, or ones implying an
///   impossible speed, are dropped. Several in a row are accepted, since then
///   the phone really did move (tunnel exit, cold start, car).
/// - Standing still: while the phone reports no motion, process noise stays
///   tiny, so jitter barely moves the dot.
class GpsFilter {
  static const _walkMps = 3.0; // brisk walk; how fast the truth can drift
  static const _stillMps = 0.3;
  static const _maxMps = 60.0; // faster than this between fixes is a glitch
  static const _poorFix = 65.0;
  static const _metersPerDegLat = 111320.0;

  double? _lat, _lng; // estimate
  double _variance = -1; // m², <0 until the first fix
  DateTime? _at;
  int _rejected = 0;
  double _speedMps = 0;

  LatLng? get position => _lat == null ? null : LatLng(_lat!, _lng!);

  /// Estimated 1-sigma error of [position] in metres.
  double get accuracy => _variance < 0 ? 999 : math.sqrt(_variance);

  /// Smoothed ground speed; single-fix spikes don't trip the driving lock.
  double get speedKmh => _speedMps * 3.6;

  void reset() {
    _lat = _lng = _at = null;
    _variance = -1;
    _rejected = 0;
    _speedMps = 0;
  }

  /// Feeds one raw fix. Returns false when it was rejected as noise.
  bool add(double lat, double lng, double accuracy, DateTime at, {double speedMps = -1}) {
    final acc = math.max(accuracy, 3.0);
    if (_variance < 0) {
      _lat = lat;
      _lng = lng;
      _variance = acc * acc;
      _at = at;
      return true;
    }

    final dt = math.max(at.difference(_at!).inMilliseconds / 1000.0, 0.05);
    final jump = _meters(lat, lng);
    final implied = math.max(0.0, jump - acc - accuracy) / dt;
    // Indoors every fix may be ±80 m; only drop ones much worse than what we have.
    final bad = implied > _maxMps || (acc > math.max(_poorFix, 3 * accuracy + 20) && jump > acc);
    if (bad && ++_rejected < 4) return false;
    if (bad) {
      // The world moved under us: restart from this fix.
      _rejected = 0;
      _lat = lat;
      _lng = lng;
      _variance = acc * acc;
      _at = at;
      _speedMps = 0;
      return true;
    }
    _rejected = 0;

    final reported = speedMps >= 0 ? speedMps : jump / dt;
    _speedMps += 0.35 * (reported - _speedMps);
    final q = _speedMps < 0.5 ? _stillMps : _walkMps;

    _variance += dt * q * q;
    final k = _variance / (_variance + acc * acc);
    _lat = _lat! + k * (lat - _lat!);
    _lng = _lng! + k * (lng - _lng!);
    _variance = (1 - k) * _variance;
    _at = at;
    return true;
  }

  double _meters(double lat, double lng) {
    final dy = (lat - _lat!) * _metersPerDegLat;
    final dx = (lng - _lng!) * _metersPerDegLat * math.cos(_lat! * math.pi / 180);
    return math.sqrt(dx * dx + dy * dy);
  }
}
