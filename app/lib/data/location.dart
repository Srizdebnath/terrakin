import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

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

  Future<void> start() async {
    if (_sub != null) return;
    if (!await Geolocator.isLocationServiceEnabled()) {
      _set(LocationState.off);
      return;
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
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 2,
      ),
    ).listen((p) {
      position = LatLng(p.latitude, p.longitude);
      speedKmh = p.speed < 0 ? 0 : p.speed * 3.6;
      accuracy = p.accuracy;
      state = LocationState.live;
      notifyListeners();
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
    super.dispose();
  }
}
