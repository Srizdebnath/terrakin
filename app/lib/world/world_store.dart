import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import 'world_data.dart';

/// Streams OpenFreeMap vector tiles around the player, anywhere on Earth.
/// Raw tiles are cached on disk; decoded geometry lives in memory in a local
/// metre frame that re-centres when the player travels far.
class WorldStore extends ChangeNotifier {
  static const _tileJson = 'https://tiles.openfreemap.org/planet';
  static const _loadRadius = 1300.0;
  static const _keepRadius = 4000.0;
  static const _rebaseMetres = 6000.0;
  static const _maxConcurrent = 3;

  GeoFrame? frame;
  final _tiles = <TileId, WorldTile>{};
  final _bytes = <TileId, Uint8List>{};
  final _loading = <TileId>{};
  final _failed = <TileId>{};
  final _queue = <TileId>[];
  String? _template;
  Directory? _cacheDir;
  var _active = 0;

  List<WorldTile> get tiles => _tiles.values.toList(growable: false);
  bool get hasAny => _tiles.isNotEmpty;
  bool get offline => _failed.isNotEmpty && _tiles.isEmpty;

  /// Local metres for a coordinate in the current frame.
  (double, double) toLocal(LatLng p) {
    final f = frame!;
    return (f.x(p.longitude), f.y(p.latitude));
  }

  void ensureAround(LatLng p) {
    final f = frame;
    if (f == null ||
        const Distance().as(LengthUnit.Meter, LatLng(f.lat0, f.lng0), p) > _rebaseMetres) {
      _rebase(p);
    }
    final dLat = _loadRadius / 110574;
    final dLng = _loadRadius / (111320 * max(0.05, cos(p.latitude * pi / 180)));
    final a = TileId.at(min(85, p.latitude + dLat), p.longitude - dLng);
    final b = TileId.at(max(-85, p.latitude - dLat), p.longitude + dLng);
    final n = 1 << 14;
    final xs = <int>[];
    for (var x = a.x;; x = (x + 1) % n) {
      xs.add(x);
      if (x == b.x || xs.length > 4) break;
    }
    for (final x in xs) {
      for (var y = a.y; y <= b.y; y++) {
        final id = TileId(x, y);
        if (_tiles.containsKey(id) || _loading.contains(id) || _failed.contains(id)) continue;
        _loading.add(id);
        _queue.add(id);
      }
    }
    _evict(p);
    _pump();
  }

  /// What the ground is at [p]: null while its tile is still loading, so
  /// spawns can wait for terrain and stay identical across players.
  Habitat? habitatAt(LatLng p) {
    final id = TileId.at(p.latitude, p.longitude);
    final t = _tiles[id];
    if (t != null) {
      final (x, y) = toLocal(p);
      return t.habitatAt(x, y);
    }
    if (_failed.contains(id)) return Habitat.land;
    return null;
  }

  void retryFailed() {
    _failed.clear();
    notifyListeners();
  }

  void _rebase(LatLng p) {
    frame = GeoFrame(p.latitude, p.longitude);
    final ids = _tiles.keys.toList();
    _tiles.clear();
    for (final id in ids) {
      if (_bytes.containsKey(id) && !_loading.contains(id)) {
        _loading.add(id);
        _queue.insert(0, id);
      }
    }
  }

  void _evict(LatLng p) {
    bool far(TileId id) {
      final c = LatLng(TileId.latOf(id.y + 0.5, id.z), TileId.lngOf(id.x + 0.5, id.z));
      return const Distance().as(LengthUnit.Meter, c, p) > _keepRadius;
    }

    _tiles.removeWhere((id, _) => far(id));
    _bytes.removeWhere((id, _) => far(id));
    _failed.removeWhere(far);
  }

  void _pump() {
    while (_active < _maxConcurrent && _queue.isNotEmpty) {
      final id = _queue.removeAt(0);
      _active++;
      _load(id).whenComplete(() {
        _active--;
        _pump();
      });
    }
  }

  Future<void> _load(TileId id) async {
    var requeue = false;
    try {
      final bytes = _bytes[id] ?? await _readOrFetch(id);
      _bytes[id] = bytes;
      final f = frame!;
      final lat0 = f.lat0, lng0 = f.lng0;
      final tile = await Isolate.run(() => buildTile(bytes, id, lat0, lng0));
      if (frame == f) {
        _tiles[id] = tile;
      } else {
        requeue = true; // the frame re-centred mid-decode
      }
    } catch (e) {
      debugPrint('tile ${id.key} failed: $e');
      _failed.add(id);
    } finally {
      if (requeue) {
        _queue.insert(0, id);
      } else {
        _loading.remove(id);
      }
      notifyListeners();
    }
  }

  Future<Uint8List> _readOrFetch(TileId id) async {
    final dir = _cacheDir ??= Directory('${(await getApplicationSupportDirectory()).path}/tiles')
      ..createSync(recursive: true);
    final file = File('${dir.path}/${id.key}.pbf');
    if (file.existsSync() && DateTime.now().difference(file.lastModifiedSync()).inDays < 30) {
      return file.readAsBytes();
    }
    final template = _template ??= await _fetchTemplate();
    final url = template
        .replaceAll('{z}', '${id.z}')
        .replaceAll('{x}', '${id.x}')
        .replaceAll('{y}', '${id.y}');
    final bytes = await _get(Uri.parse(url));
    await file.writeAsBytes(bytes, flush: false);
    return bytes;
  }

  static Future<String> _fetchTemplate() async {
    final j = jsonDecode(utf8.decode(await _get(Uri.parse(_tileJson))));
    return (j['tiles'] as List).first as String;
  }

  static Future<Uint8List> _get(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'Terrakin/1.0 (xyz.terrakin.terrakin)');
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode == 204 || res.statusCode == 404) return Uint8List(0); // open ocean
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}', uri: uri);
      final b = BytesBuilder(copy: false);
      await for (final chunk in res) {
        b.add(chunk);
      }
      return b.takeBytes();
    } finally {
      client.close();
    }
  }
}
