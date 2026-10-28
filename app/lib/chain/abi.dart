import 'dart:convert';
import 'dart:typed_data';

/// Minimal Solidity ABI encoding/decoding for the handful of Terrakin calls.
/// Selectors are precomputed with `cast sig` (see game_chain.dart).
class Abi {
  static final _mod = BigInt.one << 256;

  static String word(BigInt v) {
    final x = v.isNegative ? v + _mod : v;
    return x.toRadixString(16).padLeft(64, '0');
  }

  static String uint(int v) => word(BigInt.from(v));
  static String boolean(bool v) => uint(v ? 1 : 0);
  static String address(String a) => strip(a).toLowerCase().padLeft(64, '0');
  static String bytes32(String hex) => strip(hex).padRight(64, '0');

  /// Length-prefixed, right-padded dynamic bytes (for `string` and `bytes`).
  static String dynBytes(Uint8List b) {
    final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    final padded = hex.padRight(((hex.length + 63) ~/ 64) * 64, '0');
    return uint(b.length) + padded;
  }

  static String string(String s) => dynBytes(Uint8List.fromList(utf8.encode(s)));
  static String hexBytes(String hex) => dynBytes(fromHex(hex));

  static String strip(String hex) => hex.startsWith('0x') ? hex.substring(2) : hex;

  static Uint8List fromHex(String hex) {
    final h = strip(hex);
    return Uint8List.fromList([for (var i = 0; i + 1 < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);
  }

  /// Encodes `selector(args…)` where [heads] are already-encoded words for
  /// static args, with `null` marking each dynamic arg whose encoded tail is
  /// taken in order from [tails].
  static String call(String selector, List<String?> heads, [List<String> tails = const []]) {
    final headLen = heads.fold<int>(0, (n, h) => n + (h == null ? 64 : h.length)) ~/ 2;
    var offset = headLen;
    var t = 0;
    final head = StringBuffer();
    for (final h in heads) {
      if (h == null) {
        head.write(uint(offset));
        offset += tails[t++].length ~/ 2;
      } else {
        head.write(h);
      }
    }
    return '$selector$head${tails.join()}';
  }
}

/// Cursor over ABI-encoded return data.
class AbiReader {
  AbiReader(String hex) : _h = Abi.strip(hex);
  final String _h;

  int get words => _h.length ~/ 64;

  BigInt big(int i) => BigInt.parse(_h.substring(i * 64, i * 64 + 64), radix: 16);
  int uint(int i) => big(i).toInt();
  bool boolean(int i) => big(i) != BigInt.zero;
  String address(int i) => '0x${_h.substring(i * 64 + 24, i * 64 + 64)}';
  String bytes32(int i) => '0x${_h.substring(i * 64, i * 64 + 64)}';

  /// Signed integer of any width up to 256 bits.
  int signed(int i, int bits) {
    final v = big(i).toUnsigned(bits).toSigned(bits);
    return v.toInt();
  }

  /// Dynamic string whose offset (in bytes) sits in head word [i].
  String string(int i, {int base = 0}) {
    final at = base + uint(i) ~/ 32;
    final len = uint(at);
    final hex = _h.substring((at + 1) * 64, (at + 1) * 64 + len * 2);
    return utf8.decode(Abi.fromHex(hex), allowMalformed: true);
  }

  /// Start word of a dynamic array whose offset sits in head word [i]; the
  /// array length is at the returned index and items follow it.
  int arrayAt(int i, {int base = 0}) => base + uint(i) ~/ 32;
}
