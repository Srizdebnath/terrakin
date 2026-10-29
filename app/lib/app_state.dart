import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'chain/adventures.dart';
import 'chain/auth.dart';
import 'chain/commerce.dart';
import 'chain/game_chain.dart';
import 'chain/lab.dart';
import 'chain/social.dart';
import 'chain/strides.dart';
import 'chain/territory.dart';
import 'core/avatars.dart';
import 'core/conditions.dart';
import 'core/economy.dart';
import 'core/kin_stats.dart';
import 'core/species.dart';
import 'data/collection.dart';
import 'data/location.dart';
import 'data/player.dart';
import 'data/spawn_engine.dart';
import 'data/weather.dart';
import 'world/world_store.dart';

/// App-wide singletons. Small enough for now; swap for a DI/state package
/// once the backend and wallet layers arrive.
final auth = AuthService();
final chain = GameChain(auth);
final collection = Collection(chain);
final location = LocationService();
final weather = WeatherService();
final world = WorldStore();
final profile = Profile(chain);
final territory = TerritoryService(chain);
final lab = LabService(chain, territory);
final social = SocialService(chain);
final commerce = CommerceService(chain, territory);
final adventures = AdventureService(chain, territory);
final strides = StrideRewards(chain);

/// Spawns that fled this session; they disappear from the map.
final fledSpawns = <String>{};

Conditions get conditions => weather.effective;
Kin? get buddy => collection.byUid(profile.buddyUid);

// ---- Game rules -----------------------------------------------------------

/// Interaction radius from SRS FR-BND-01, plus perks and abilities.
double bondReach() {
  var r = 40.0;
  if (profile.perk == Perk.longReach) r += 10;
  if (buddy?.species.ability == Ability.rainsense && conditions.sky.wet) r += 20;
  return r;
}

/// How far away wild Kin show up.
double wildRadius() => profile.perk == Perk.cartographer ? 450 : 300;

/// Rare and better Kin, which Ember Nose reveals from twice as far.
double rareRadius() => wildRadius() * (buddy?.species.ability == Ability.emberNose ? 2 : 1);

/// Landmark zones searched around the player (1 = 3x3, 2 = 5x5).
int landmarkRing() => buddy?.species.ability == Ability.oldMemory ? 2 : 1;

/// Landmark Kin show as a beacon in the world inside this distance.
const landmarkBeaconMetres = 900.0;

bool isBoosted(Spawn s) => conditions.boosted.contains(s.species.affinity);

/// Chance one throw of [orb] holds the Kin, for a throw of [accuracy] (0..1).
double catchChance(Spawn s, double accuracy, Orb orb) {
  if (orb.guaranteed) return 1;
  var bonus = 0.0;
  final boosted = isBoosted(s);
  if (boosted) bonus += 0.1;
  switch (profile.perk) {
    case Perk.tidewalker when s.species.affinity == Affinity.tide || s.species.affinity == Affinity.grove:
    case Perk.stormchaser when boosted:
    case Perk.nightwalker when conditions.isNight:
      bonus += 0.1;
    default:
      break;
  }
  final base = s.grade.bondChance * (0.45 + 0.55 * accuracy) * (1 + bonus) * orb.catchMultiplier;
  return base.clamp(0.0, 0.99);
}

/// Chance the Kin runs off after breaking free. Steadfast buddies halve it.
double fleeChance(Spawn s) =>
    Economy.fleeChance(s.grade) * (buddy?.species.ability == Ability.steadfast ? 0.5 : 1);

/// Stride multiplier for the buddy on this stretch of walking.
double strideMultiplier(Kin k) {
  var m = 1.0 + k.resonance / 100 * 0.3;
  if (profile.perk == Perk.hearthkeeper) m *= 1.25;
  if (k.genes.trait == Trait.wanderer) m *= 1.5;
  if (k.species.ability == Ability.photosynth &&
      conditions.isDay &&
      (conditions.sky == Sky.clear || conditions.sky == Sky.partlyCloudy)) {
    m *= 1.5;
  }
  return m;
}

/// Counts real walking (not driving, not GPS jitter) towards distance walked and
/// the buddy's Stride.
class StrideTracker {
  LatLng? _last;

  void onFix() {
    if (!location.live) return;
    final p = location.position;
    final last = _last;
    if (location.accuracy > 35) return;
    if (last == null) {
      _last = p;
      return;
    }
    final d = const Distance().as(LengthUnit.Meter, last, p);
    // Only count once we're clearly away from the last counted point, so
    // jitter while standing never adds up but slow steps eventually do.
    if (d < math.max(6, location.accuracy)) return;
    _last = p;
    if (d > 150 || location.tooFast) return;
    strides.walked(p);
    profile.addWalk(d);
    final b = buddy;
    if (b != null) collection.addStride(b.uid, d * strideMultiplier(b));
  }
}

final strideTracker = StrideTracker();
