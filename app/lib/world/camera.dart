import 'dart:math';
import 'dart:ui';

/// Third-person orbit camera over the local metre frame. Yaw 0 looks north;
/// zoom 0 is close and low (more horizon), 1 is high and steep.
class WorldCamera {
  double tx = 0, ty = 0;
  double yaw = 0;
  double zoom = 0.3;
  Size size = const Size(400, 800);

  static const near = 2.0;
  static const fov = 70 * pi / 180;

  late double pitch, dist, f, cx, cy;
  late double camX, camY, camZ;
  late double _rX, _rY, _uX, _uY, _uZ, _fX, _fY, _fZ;

  /// View-space output of [view].
  double vx = 0, vy = 0, vz = 0;

  void update(Size s) {
    size = s;
    pitch = _lerp(28, 60, zoom) * pi / 180;
    dist = _lerp(85, 300, zoom);
    f = (s.height / 2) / tan(fov / 2);
    cx = s.width / 2;
    cy = s.height * 0.68;
    final sy = sin(yaw), cyw = cos(yaw), sp = sin(pitch), cp = cos(pitch);
    camX = tx - sy * dist * cp;
    camY = ty - cyw * dist * cp;
    camZ = dist * sp;
    _rX = cyw;
    _rY = -sy;
    _fX = sy * cp;
    _fY = cyw * cp;
    _fZ = -sp;
    _uX = sy * sp;
    _uY = cyw * sp;
    _uZ = cp;
  }

  void view(double x, double y, double z) {
    final dx = x - camX, dy = y - camY, dz = z - camZ;
    vx = dx * _rX + dy * _rY;
    vy = dx * _uX + dy * _uY + dz * _uZ;
    vz = dx * _fX + dy * _fY + dz * _fZ;
  }

  double sx(double vx, double vz) => cx + f * vx / vz;
  double sy(double vy, double vz) => cy - f * vy / vz;

  /// Screen position, or null when the point is behind the camera.
  Offset? project(double x, double y, [double z = 0]) {
    view(x, y, z);
    if (vz < near) return null;
    return Offset(sx(vx, vz), sy(vy, vz));
  }

  /// Pixels per metre at view depth [depth].
  double scaleAt(double depth) => f / depth;

  double depthOf(double x, double y, [double z = 0]) {
    view(x, y, z);
    return vz;
  }

  double get horizonY => cy - f * tan(pitch);

  /// Distance from the target to the ground point at the screen's top edge (or
  /// the horizon), used to size the draw radius.
  double get groundReach {
    final top = max(horizonY + 4, 0.0);
    final below = pitch - atan((cy - top) / f);
    if (below <= 0.01) return 2000;
    return min(2000, camZ / tan(below) - dist * cos(pitch));
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
