import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chain/game_chain.dart';
import '../core/avatars.dart';
import '../core/economy.dart';

class MintedAvatar {
  const MintedAvatar(this.tokenId, this.styleId);
  final String tokenId;
  final String styleId;

  AvatarStyle get style => avatarById(styleId);
}

/// What the player chose and did on this device. Ownership (characters, orbs,
/// MON) lives on chain in [GameChain]; this keeps the active character, buddy,
/// distance walked, and orbs thrown since the last bond.
class Profile extends ChangeNotifier {
  Profile(this.chain) {
    chain.addListener(notifyListeners);
  }
  final GameChain chain;
  static const _key = 'profile.v2';

  String? activeToken;
  String? buddyUid;
  double walkedMetres = 0;
  double _unsaved = 0;

  /// Orbs thrown at Kin that broke free or fled. They are still on chain until
  /// the next bond burns them along with that encounter's throws.
  final pendingThrows = <Orb, int>{for (final o in Orb.values) o: 0};

  List<MintedAvatar> get avatars => [
        for (final (id, style) in chain.characterTokens)
          MintedAvatar(id, avatarStyles[style.clamp(0, avatarStyles.length - 1)].id),
      ];
  bool get hasAvatar => avatars.isNotEmpty;
  MintedAvatar? get active {
    final all = avatars;
    return all.where((a) => a.tokenId == activeToken).firstOrNull ?? all.firstOrNull;
  }

  AvatarStyle get style => active?.style ?? avatarStyles.first;
  Perk get perk => style.perk;
  bool owns(String styleId) => avatars.any((a) => a.styleId == styleId);

  /// Orbs that can still be thrown: on chain minus already thrown.
  int orbsLeft(Orb o) => chain.orbs[o.index] - pendingThrows[o]!;
  int get totalOrbs => Orb.values.fold(0, (a, o) => a + orbsLeft(o));
  List<int> get throwsToBurn => [for (final o in Orb.values) pendingThrows[o]!];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    activeToken = j['active'];
    buddyUid = j['buddy'];
    walkedMetres = (j['walked'] as num?)?.toDouble() ?? 0;
    final p = (j['pending'] as Map?)?.cast<String, dynamic>() ?? const {};
    for (final o in Orb.values) {
      pendingThrows[o] = (p[o.name] as num?)?.toInt() ?? 0;
    }
    notifyListeners();
  }

  /// Takes one orb for a throw; false when none are left.
  bool useOrb(Orb orb) {
    if (orbsLeft(orb) <= 0) return false;
    pendingThrows[orb] = pendingThrows[orb]! + 1;
    _save();
    notifyListeners();
    return true;
  }

  /// After a bond burned [burned] on chain.
  void clearThrows(List<int> burned) {
    for (final o in Orb.values) {
      pendingThrows[o] = (pendingThrows[o]! - burned[o.index]).clamp(0, 1 << 30);
    }
    _save();
    notifyListeners();
  }

  Future<void> setActive(String token) async {
    activeToken = token;
    await _save();
    notifyListeners();
  }

  Future<void> setBuddy(String? uid) async {
    buddyUid = uid;
    await _save();
    notifyListeners();
  }

  void addWalk(double metres) {
    walkedMetres += metres;
    _unsaved += metres;
    if (_unsaved > 25) {
      _unsaved = 0;
      _save();
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'active': activeToken,
        'buddy': buddyUid,
        'walked': walkedMetres,
        'pending': {for (final e in pendingThrows.entries) e.key.name: e.value},
      }),
    );
  }
}
