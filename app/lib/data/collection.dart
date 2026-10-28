import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/conditions.dart';
import '../core/kin_stats.dart';
import '../chain/game_chain.dart';
import '../core/species.dart';

class Kin {
  Kin({
    required this.uid,
    required this.genes,
    required this.resonance,
    required this.imprintPath,
    required this.bondedAt,
    required this.lat,
    required this.lng,
    required this.spawnId,
    this.landmark = false,
    this.stride = 0,
    this.tradeMods = const [1, 1, 1, 1],
    this.trades = 0,
    this.tradedFrom,
  });

  final String uid;
  final Genes genes;
  final int resonance; // 0..100, Tether quality; adds to Stride gain
  final String? imprintPath; // local Imprint photo
  final DateTime bondedAt;

  /// Origin coordinate: where it spawned. Drives the Homeground bonus.
  final double lat;
  final double lng;
  final String spawnId;
  final bool landmark;

  /// Metres walked together as buddy.
  double stride;

  /// Stat multipliers (hp, atk, def, spd) accumulated from trades.
  final List<double> tradeMods;
  final int trades;

  /// Who this Kin came from in its latest trade.
  final String? tradedFrom;

  Species get species => genes.species;
  Grade get grade => genes.grade;
  LatLng get origin => LatLng(lat, lng);
  int get level => strideLevel(stride);
  StatBlock get stats => genes.stats(level: level).withMods(tradeMods);

  /// The same Kin after one more trade.
  Kin traded({required List<double> mods, required String from, bool keepPhoto = false}) => Kin(
        uid: uid,
        genes: genes,
        resonance: resonance,
        imprintPath: keepPhoto ? imprintPath : null,
        bondedAt: bondedAt,
        lat: lat,
        lng: lng,
        spawnId: spawnId,
        landmark: landmark,
        stride: stride,
        tradeMods: mods,
        trades: trades + 1,
        tradedFrom: from,
      );
  int get power => stats.power;

  List<Modifier> modifiers(Conditions c, LatLng player) => liveModifiers(
        genes,
        c,
        metresFromOrigin: const Distance().as(LengthUnit.Meter, origin, player),
      );

  int livePower(Conditions c, LatLng player) => (power * combined(modifiers(c, player))).round();

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'speciesId': species.id,
        'grade': grade.name,
        'vigor': genes.vigor.toList(),
        'trait': genes.trait.name,
        'resonance': resonance,
        'imprintPath': imprintPath,
        'bondedAt': bondedAt.toIso8601String(),
        'lat': lat,
        'lng': lng,
        'spawnId': spawnId,
        'landmark': landmark,
        'stride': stride,
        'tradeMods': tradeMods,
        'trades': trades,
        'tradedFrom': tradedFrom,
      };

  factory Kin.fromJson(Map<String, dynamic> j) {
    final sp = speciesById(j['speciesId']);
    final grade = Grade.values.byName(j['grade']);
    // Kin bonded before stats existed get a stable roll from their uid.
    final legacy = Genes.roll(Random(j['uid'].hashCode), sp, grade);
    final vigor = j['vigor'] is List ? Vigor.fromList(j['vigor']) : legacy.vigor;
    final trait = j['trait'] is String ? Trait.values.byName(j['trait']) : legacy.trait;
    return Kin(
      uid: j['uid'],
      genes: Genes(sp, grade, vigor, trait),
      resonance: j['resonance'],
      imprintPath: j['imprintPath'],
      bondedAt: DateTime.parse(j['bondedAt']),
      lat: (j['lat'] as num).toDouble(),
      lng: (j['lng'] as num).toDouble(),
      spawnId: j['spawnId'],
      landmark: j['landmark'] == true,
      stride: (j['stride'] as num?)?.toDouble() ?? 0,
      tradeMods: j['tradeMods'] is List
          ? [for (final m in j['tradeMods'] as List) (m as num).toDouble()]
          : const [1, 1, 1, 1],
      trades: (j['trades'] as num?)?.toInt() ?? 0,
      tradedFrom: j['tradedFrom'],
    );
  }
}

/// What only this phone knows about a Kin: the Imprint photo, Stride walked
/// together, the spawn it came from, and the Tether quality.
class KinMeta {
  KinMeta({this.imprintPath, this.stride = 0, this.spawnId, this.resonance = 70});
  String? imprintPath;
  double stride;
  String? spawnId;
  int resonance;

  Map<String, dynamic> toJson() =>
      {'imprint': imprintPath, 'stride': stride, 'spawn': spawnId, 'res': resonance};
  factory KinMeta.fromJson(Map<String, dynamic> j) => KinMeta(
        imprintPath: j['imprint'],
        stride: (j['stride'] as num?)?.toDouble() ?? 0,
        spawnId: j['spawn'],
        resonance: (j['res'] as num?)?.toInt() ?? 70,
      );
}

/// The player's Kin: owned on Monad (Terrakin.kinOf), dressed with local
/// metadata. Re-built on every chain sync.
class Collection extends ChangeNotifier {
  Collection(this.chain) {
    chain.addListener(_rebuild);
  }
  final GameChain chain;
  static const _metaKey = 'kinmeta.v1';
  static const _bondedKey = 'bonded.v1';

  final List<Kin> _kin = [];
  final _meta = <String, KinMeta>{};

  /// Spawn ids this player has bonded, so they disappear from the world.
  final _bondedSpawns = <String>{};
  double _unsavedStride = 0;

  List<Kin> get all => List.unmodifiable(_kin.reversed);
  int get count => _kin.length;
  bool isBonded(String spawnId) => _bondedSpawns.contains(spawnId);
  bool hasSpecies(String id) => _kin.any((k) => k.species.id == id);
  Kin? byUid(String? uid) => uid == null ? null : _kin.where((k) => k.uid == uid).firstOrNull;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_metaKey);
    if (raw != null) {
      (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) => _meta[k] = KinMeta.fromJson(v));
    }
    _bondedSpawns.addAll(prefs.getStringList(_bondedKey) ?? const []);
    _rebuild();
  }

  void _rebuild() {
    _kin
      ..clear()
      ..addAll([
        for (final c in chain.kin..sort((a, b) => a.bondedAt.compareTo(b.bondedAt)))
          () {
            final m = _meta[c.id] ?? KinMeta();
            final sp = species[c.species.clamp(0, species.length - 1)];
            return Kin(
              uid: c.id,
              genes: Genes(sp, Grade.values[c.grade.clamp(0, 4)],
                  Vigor(c.vigor[0], c.vigor[1], c.vigor[2], c.vigor[3]), Trait.values[c.trait.clamp(0, Trait.values.length - 1)]),
              resonance: m.resonance,
              imprintPath: m.imprintPath,
              bondedAt: DateTime.fromMillisecondsSinceEpoch(c.bondedAt * 1000),
              lat: c.lat / 1e6,
              lng: c.lng / 1e6,
              spawnId: m.spawnId ?? '',
              landmark: c.landmark,
              stride: m.stride,
              tradeMods: [for (final x in c.mods) x / 10000],
              trades: c.trades,
            );
          }(),
      ]);
    notifyListeners();
  }

  /// Records local details for a Kin just bonded on chain.
  Future<void> remember(String kinId, KinMeta meta) async {
    _meta[kinId] = meta;
    if (meta.spawnId != null) _bondedSpawns.add(meta.spawnId!);
    await _save();
    _rebuild();
  }

  /// Adds walked metres to a buddy; persists every 25 m or so.
  void addStride(String uid, double metres) {
    final k = byUid(uid);
    if (k == null || metres <= 0) return;
    final m = _meta[uid] ??= KinMeta();
    final before = k.level;
    m.stride += metres;
    k.stride = m.stride;
    _unsavedStride += metres;
    if (_unsavedStride > 25 || k.level != before) {
      _unsavedStride = 0;
      _save();
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_metaKey, jsonEncode({for (final e in _meta.entries) e.key: e.value.toJson()}));
    await prefs.setStringList(_bondedKey, _bondedSpawns.toList());
  }
}
