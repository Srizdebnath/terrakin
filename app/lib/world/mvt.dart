import 'dart:convert';
import 'dart:typed_data';

/// Minimal Mapbox Vector Tile (v2) decoder: just enough protobuf to read the
/// OpenMapTiles layers the world renderer uses. Pure Dart so it can run in an
/// isolate.
class MvtFeature {
  MvtFeature(this.type, this.tags, this.rings);

  /// 1 point, 2 line, 3 polygon.
  final int type;
  final Map<String, Object?> tags;

  /// Tile-space coordinates (x, y interleaved, 0..extent, y down). For
  /// polygons each entry is one ring; for lines each entry is one line.
  final List<Int32List> rings;
}

class MvtLayer {
  MvtLayer(this.name, this.extent, this.features);
  final String name;
  final int extent;
  final List<MvtFeature> features;
}

Map<String, MvtLayer> decodeMvt(Uint8List bytes, {Set<String>? only}) {
  final out = <String, MvtLayer>{};
  final r = _Reader(bytes);
  while (r.more) {
    final key = r.varint();
    if (key >> 3 == 3 && key & 7 == 2) {
      final layer = _layer(r.sub(), only);
      if (layer != null) out[layer.name] = layer;
    } else {
      r.skip(key & 7);
    }
  }
  return out;
}

MvtLayer? _layer(_Reader r, Set<String>? only) {
  String? name;
  var extent = 4096;
  final keys = <String>[];
  final values = <Object?>[];
  final rawFeatures = <_Reader>[];
  while (r.more) {
    final key = r.varint();
    switch (key >> 3) {
      case 1:
        name = r.string();
        if (only != null && !only.contains(name)) return null;
      case 2:
        rawFeatures.add(r.sub());
      case 3:
        keys.add(r.string());
      case 4:
        values.add(_value(r.sub()));
      case 5:
        extent = r.varint();
      default:
        r.skip(key & 7);
    }
  }
  if (name == null) return null;
  return MvtLayer(name, extent, [for (final f in rawFeatures) _feature(f, keys, values)]);
}

Object? _value(_Reader r) {
  Object? v;
  while (r.more) {
    final key = r.varint();
    switch (key >> 3) {
      case 1:
        v = r.string();
      case 2:
        v = r.float32();
      case 3:
        v = r.float64();
      case 4:
      case 5:
        v = r.varint();
      case 6:
        final n = r.varint();
        v = (n >> 1) ^ -(n & 1);
      case 7:
        v = r.varint() != 0;
      default:
        r.skip(key & 7);
    }
  }
  return v;
}

MvtFeature _feature(_Reader r, List<String> keys, List<Object?> values) {
  var type = 0;
  final tags = <String, Object?>{};
  List<int> geom = const [];
  while (r.more) {
    final key = r.varint();
    switch (key >> 3) {
      case 2:
        final p = r.packed();
        for (var i = 0; i + 1 < p.length; i += 2) {
          tags[keys[p[i]]] = values[p[i + 1]];
        }
      case 3:
        type = r.varint();
      case 4:
        geom = r.packed();
      default:
        r.skip(key & 7);
    }
  }
  return MvtFeature(type, tags, _geometry(geom));
}

List<Int32List> _geometry(List<int> g) {
  final rings = <Int32List>[];
  var cur = <int>[];
  var x = 0, y = 0, i = 0;
  void flush() {
    if (cur.length >= 2) rings.add(Int32List.fromList(cur));
    cur = <int>[];
  }

  while (i < g.length) {
    final cmd = g[i] & 7;
    final count = g[i] >> 3;
    i++;
    if (cmd == 7) {
      flush();
      continue;
    }
    for (var c = 0; c < count && i + 1 < g.length; c++) {
      if (cmd == 1) flush();
      x += (g[i] >> 1) ^ -(g[i] & 1);
      y += (g[i + 1] >> 1) ^ -(g[i + 1] & 1);
      i += 2;
      cur
        ..add(x)
        ..add(y);
    }
  }
  flush();
  return rings;
}

class _Reader {
  _Reader(this.b, [this.pos = 0, int? end]) : end = end ?? b.length;
  final Uint8List b;
  int pos;
  final int end;

  bool get more => pos < end;

  int varint() {
    var result = 0, shift = 0;
    while (true) {
      final byte = b[pos++];
      result |= (byte & 0x7f) << shift;
      if (byte < 0x80) return result;
      shift += 7;
    }
  }

  _Reader sub() {
    final len = varint();
    final r = _Reader(b, pos, pos + len);
    pos += len;
    return r;
  }

  String string() {
    final len = varint();
    final s = utf8.decode(Uint8List.sublistView(b, pos, pos + len), allowMalformed: true);
    pos += len;
    return s;
  }

  double float32() {
    final v = ByteData.sublistView(b, pos, pos + 4).getFloat32(0, Endian.little);
    pos += 4;
    return v;
  }

  double float64() {
    final v = ByteData.sublistView(b, pos, pos + 8).getFloat64(0, Endian.little);
    pos += 8;
    return v;
  }

  List<int> packed() {
    final r = sub();
    final out = <int>[];
    while (r.more) {
      out.add(r.varint());
    }
    return out;
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        pos += 8;
      case 2:
        pos += varint();
      case 5:
        pos += 4;
      default:
        throw FormatException('Unsupported wire type $wire');
    }
  }
}
