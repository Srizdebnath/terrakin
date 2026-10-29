import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../core/gps_filter.dart';

enum LocationState { starting, live, denied, off }

/// Foreground-only location (SRS 7.5). Falls back to a fixed point when
/// permission is missing so the world still renders.
class LocationService extends ChangeNotifier {
  static const fallback = LatLng(22.5448, 88.3426); // Victoria Memorial, Kolkata

  LatLng position = fallback;
  double speedKmh = 0;
  double accuracy = 999;
  LocationState state = LocationState.starting;
  StreamSubscription<Position>? _sub;
  StreamSubscription<ServiceStatus>? _service;
  bool _starting = false;
  final _filter = GpsFilter();

  Future<void> start() async {
    // Follow the GPS toggle so the game recovers on its own. Some OEM builds
    // also report the service as off for a moment right after a cold start.
    _service ??= Geolocator.getServiceStatusStream().listen((s) {
      if (s == ServiceStatus.enabled) {
        start();
      } else {
        _sub?.cancel();
        _sub = null;
        _set(LocationState.off);
      }
    }, onError: (_) {});
    if (_sub != null || _starting) return;
    _starting = true;
    try {
      await _open();
    } finally {
      _starting = false;
    }
  }

  Future<void> _open() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Future.delayed(const Duration(milliseconds: 800));
      if (_sub != null) return;
      if (!await Geolocator.isLocationServiceEnabled()) {
        _set(LocationState.off);
        return;
      }
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      _set(LocationState.denied);
      return;
    }
    _sub = Geolocator.getPositionStream(
      // Every fix, once a second: the filter needs the raw stream to average.
      locationSettings: defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(accuracy: LocationAccuracy.best, intervalDuration: const Duration(seconds: 1))
          : const LocationSettings(accuracy: LocationAccuracy.best),
    ).listen((p) {
      final trusted = p.speedAccuracy > 0 && p.speedAccuracy < 1.5;
      if (!_filter.add(p.latitude, p.longitude, p.accuracy, p.timestamp, speedMps: trusted ? p.speed : -1)) return;
      position = _filter.position!;
      speedKmh = _filter.speedKmh;
      accuracy = _filter.accuracy;
      state = LocationState.live;
      notifyListeners();
    }, onError: (Object e) {
      // GPS switched off mid-session; the service stream restarts us.
      _filter.reset();
      _sub?.cancel();
      _sub = null;
      _set(e is LocationServiceDisabledException ? LocationState.off : LocationState.denied);
    });
  }

  void _set(LocationState s) {
    state = s;
    notifyListeners();
  }

  bool get live => state == LocationState.live;

  /// SRS FR-SPN-07: no spawns above 25 km/h.
  bool get tooFast => speedKmh > 25;

  double distanceTo(LatLng p) => const Distance().as(LengthUnit.Meter, position, p);

  @override
  void dispose() {
    _sub?.cancel();
    _service?.cancel();
    super.dispose();
  }
}
