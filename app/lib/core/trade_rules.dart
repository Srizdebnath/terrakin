import 'dart:math';

/// Kin trading: two players stand within [tradeRangeMetres] of each other and
/// swap Kin. The journey unsettles a traded Kin, so every stat shifts by up to
/// ±[tradeSwing], and the shifts pile up across trades within [modFloor]..[modCeil].
const tradeRangeMetres = 8.0;
const tradeSwing = 0.15;
const modFloor = 0.7;
const modCeil = 1.3;

/// Phone GPS is often off by a few metres, so allow a little slack on top of
/// the 8 m, scaled by how sure both fixes are and capped at 5 m.
double gpsAllowance(double accA, double accB) => min(5.0, (accA + accB) / 4);

bool withinTradeRange(double metres, double accA, double accB) =>
    metres <= tradeRangeMetres + gpsAllowance(accA, accB);

/// Per-stat multipliers (hp, atk, def, spd) for one trade, the same on both
/// phones because the seed mixes both players' nonces and both Kin ids.
List<double> rollTradeShift(int seed, String kinUid) {
  final rng = Random(seed ^ fnv32(kinUid));
  return List.generate(4, (_) => 1 + (rng.nextDouble() * 2 - 1) * tradeSwing);
}

List<double> applyShift(List<double> mods, List<double> shift) =>
    [for (var i = 0; i < 4; i++) (mods[i] * shift[i]).clamp(modFloor, modCeil)];

/// Order-independent seed: both phones get the same value.
int tradeSeed(String nonceA, String nonceB, String uidA, String uidB) {
  final parts = [nonceA, nonceB]..sort();
  final uids = [uidA, uidB]..sort();
  return fnv32('${parts.join('|')}#${uids.join('|')}');
}

/// Stable 32-bit FNV-1a (String.hashCode is not guaranteed across devices).
int fnv32(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}
