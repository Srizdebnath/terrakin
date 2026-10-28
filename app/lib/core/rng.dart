import 'dart:math';

/// 32-bit multiply with wrap-around, matching JavaScript's Math.imul.
int imul32(int a, int b) => ((a & 0xffffffff) * (b & 0xffffffff)) & 0xffffffff;

/// Order-sensitive 32-bit hash of up to three ints plus a salt. Mirrored
/// exactly in backend/lib/spawn.ts so the server can re-derive any spawn.
int hash32(int a, int b, int c, int salt) {
  var h = imul32(salt & 0xffffffff, 0x9E3779B1);
  h = imul32(h ^ (a & 0xffffffff), 0x85EBCA6B);
  h ^= h >> 13;
  h = imul32(h ^ (b & 0xffffffff), 0xC2B2AE35);
  h ^= h >> 16;
  h = imul32(h ^ (c & 0xffffffff), 0x27D4EB2F);
  h ^= h >> 15;
  return h & 0xffffffff;
}

/// Mulberry32: tiny, fast, and trivially portable PRNG. Used instead of
/// dart:math's Random wherever results must match the backend.
class Mulberry32 implements Random {
  Mulberry32(int seed) : _s = seed & 0xffffffff;
  int _s;

  int nextUint32() {
    _s = (_s + 0x6D2B79F5) & 0xffffffff;
    var t = _s;
    t = imul32(t ^ (t >> 15), t | 1);
    t ^= (t + imul32(t ^ (t >> 7), t | 61)) & 0xffffffff;
    return (t ^ (t >> 14)) & 0xffffffff;
  }

  @override
  double nextDouble() => nextUint32() / 4294967296.0;

  @override
  int nextInt(int max) => (nextDouble() * max).floor();

  @override
  bool nextBool() => nextUint32() & 1 == 1;
}
