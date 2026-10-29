import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/scheduler.dart';
import 'package:latlong2/latlong.dart';

import '../app_state.dart';
import '../chain/adventures.dart';
import '../chain/social.dart';
import '../core/copy.dart';
import '../core/sound.dart';
import '../core/conditions.dart';
import '../core/economy.dart';
import '../core/species.dart';
import '../core/theme.dart';
import '../data/location.dart';
import '../data/spawn_engine.dart';
import '../widgets/kin_widgets.dart';
import '../world/avatar_painter.dart';
import '../world/camera.dart';
import '../world/palette.dart';
import '../world/sky_painter.dart';
import '../world/world_data.dart';
import '../world/world_painter.dart';
import 'adventure_sheet.dart';
import 'hex_sheet.dart';
import 'lab_screen.dart';
import 'raid_sheet.dart';
import 'season_screen.dart';
import 'atlas_screen.dart';
import 'encounter_sheet.dart';
import 'market_screen.dart';
import 'profile_screen.dart';
import 'trade_screen.dart';

/// Home screen: the real world around the player in 3D, live weather and
/// daylight, the walking avatar, buddy, wild Kin and Landmark beacons.
class WorldScreen extends StatefulWidget {
  const WorldScreen({super.key});

  @override
  State<WorldScreen> createState() => _WorldScreenState();
}

class _WorldScreenState extends State<WorldScreen>
    with SingleTickerProviderStateMixin {
  final _cam = WorldCamera();
  final _time = ValueNotifier<double>(0);
  final _frame = ValueNotifier<int>(0);
  late final Ticker _ticker = createTicker(_tick);
  Duration _lastTick = Duration.zero;

  GeoFrame? _geo;
  double _ax = 0, _ay = 0, _heading = 0, _phase = 0;
  double _bx = 0, _by = 0;
  bool _moving = false;
  (double, double, double, double, bool) _lastCam = (0, 0, 0, 0, false);

  List<Spawn> _spawns = [];
  List<Spawn> _landmarks = [];
  late Conditions _cond = conditions;
  late Palette _palette = Palette.of(_cond);
  LatLng? _refreshedAt;
  Timer? _timer;

  double _zoomAtStart = 0.3;

  @override
  void initState() {
    super.initState();
    location.addListener(_onFix);
    weather.addListener(_onWeather);
    world.addListener(_onWorld);
    collection.addListener(_refresh);
    profile.addListener(_refresh);
    territory.addListener(_onTerritory);
    social.addListener(_onTerritory);
    adventures.addListener(_onAdventures);
    strides.addListener(_onStrides);
    adventures.restoreLoop().catchError((Object _) {});
    territory.start(() => location.position);
    social
        .enrollOnce()
        .then((_) => social.refreshMyCrew())
        .catchError((Object _) {});
    location.start();
    world.ensureAround(location.position);
    weather.start(location.position);
    _refreshAdventures(location.position, force: true);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
    _ticker.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _greet());
    sound.setConditions(conditions);
  }

  /// "gm" once per UTC day.
  Future<void> _greet() async {
    final prefs = await SharedPreferences.getInstance();
    final day = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    if (prefs.getString('gm.day') == day || !mounted) return;
    await prefs.setString('gm.day', day);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(copy.gm(chain.name.isEmpty ? 'Wayfinder' : chain.name)),
      ),
    );
  }

  @override
  void dispose() {
    location.removeListener(_onFix);
    weather.removeListener(_onWeather);
    world.removeListener(_onWorld);
    collection.removeListener(_refresh);
    profile.removeListener(_refresh);
    territory.removeListener(_onTerritory);
    social.removeListener(_onTerritory);
    adventures.removeListener(_onAdventures);
    strides.removeListener(_onStrides);
    _timer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _onFix() {
    final p = location.position;
    strideTracker.onFix();
    world.ensureAround(p);
    weather.update(p);
    territory.moved(p);
    adventures.walked(p);
    _refreshAdventures(p);
    final last = _refreshedAt;
    if (last == null || const Distance().as(LengthUnit.Meter, last, p) > 12) {
      _refresh();
    }
    if (mounted) setState(() {});
  }

  void _onWeather() {
    sound.setConditions(conditions);
    if (!mounted) return;
    setState(() {
      _cond = conditions;
      _palette = Palette.of(_cond);
    });
    _refresh();
    _frame.value++;
  }

  DateTime? _adventuresAt;

  /// Drops and the Convergence schedule around the player, at most once a minute.
  void _refreshAdventures(LatLng p, {bool force = false}) {
    final at = _adventuresAt;
    if (!force && at != null && DateTime.now().difference(at) < const Duration(minutes: 1)) return;
    _adventuresAt = DateTime.now();
    adventures.refreshDrops(p).catchError((Object _) {});
    adventures.refreshConvergences(p).catchError((Object _) {});
  }

  void _onStrides() {
    final r = strides.lastReward;
    if (r != null) {
      strides.lastReward = null;
      sound.play(Sfx.coin);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('+${fmtMon(r.$1)} for walking ${fmtDistance(r.$2.toDouble())}')),
      );
    }
    if (mounted) setState(() {});
  }

  void _onAdventures() {
    _frame.value++;
    if (mounted) setState(() {});
  }

  void _openAdventures() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TK.dusk,
      builder: (sheet) => AdventureSheet(
        onStartLoop: () {
          Navigator.pop(sheet);
          adventures.startLoop(location.position);
        },
      ),
    );
  }

  void _onTerritory() {
    _frame.value++;
    final owners = territory.states.values
        .map((s) => s.owner)
        .whereType<String>();
    social.lookupCrews(owners).catchError((Object _) {});
  }

  /// Territory hexes in local metres: faint outlines for unclaimed hexes,
  /// holder colours for held ones, amber for yours, brighter for the one
  /// you stand in.
  List<(Float32List, Color, Color, double)> _hexRings() {
    if (world.frame == null || !territory.enabled) return const [];
    final out = <(Float32List, Color, Color, double)>[];
    for (final MapEntry(key: id, value: s) in territory.states.entries) {
      final c = territory.corners(id);
      final pts = Float32List(c.length * 2);
      for (var i = 0; i < c.length; i++) {
        final (x, y) = world.toLocal(c[i]);
        pts[i * 2] = x;
        pts[i * 2 + 1] = y;
      }
      final here = id == territory.here;
      if (s.owner == null) {
        out.add((
          pts,
          here ? TK.paper.withValues(alpha: 0.06) : const Color(0x00000000),
          const Color(0xFF3A3452).withValues(alpha: here ? 0.9 : 0.4),
          here ? 2.5 : 1,
        ));
      } else {
        final mine = territory.isMine(s);
        final crew = social.crewOfOwner[s.owner] ?? 0;
        final colour = mine
            ? TK.signal
            : (crew != 0
                  ? SocialService.crewColour(crew)
                  : holderColor(s.owner!));
        out.add((
          pts,
          colour.withValues(alpha: 0.14),
          colour.withValues(alpha: mine || here ? 0.95 : 0.6),
          here ? 3 : (mine ? 2 : 1.5),
        ));
      }
    }
    // The loop being walked, drawn on top; the start hex is the finish line.
    if (adventures.looping) {
      for (final id in adventures.trail.toSet()) {
        final c = territory.corners(id);
        final pts = Float32List(c.length * 2);
        for (var i = 0; i < c.length; i++) {
          final (x, y) = world.toLocal(c[i]);
          pts[i * 2] = x;
          pts[i * 2 + 1] = y;
        }
        final start = id == adventures.startHex;
        out.add((pts, TK.loop.withValues(alpha: start ? 0.32 : 0.2), TK.loop, start ? 4 : 2.5));
      }
    }
    return out;
  }

  void _onWorld() {
    if (mounted) setState(() {});
    _refresh();
    _frame.value++;
  }

  void _refresh() {
    if (!mounted) return;
    final p = location.position;
    final now = DateTime.now();
    _refreshedAt = p;
    const dist = Distance();
    final wildR = wildRadius();
    final spawns = location.tooFast
        ? <Spawn>[]
        : SpawnEngine.wild(
                p,
                max(wildR, rareRadius()),
                now: now,
                conditions: conditions,
                habitat: world.habitatAt,
              )
              .where(
                (s) =>
                    !collection.isBonded(s.id) &&
                    !fledSpawns.contains(s.id) &&
                    (s.grade.index >= Grade.rare.index ||
                        dist.as(LengthUnit.Meter, p, s.point) <= wildR),
              )
              .toList();
    final landmarks = SpawnEngine.landmarks(p, now: now, ring: landmarkRing())
      ..sort(
        (a, b) => location
            .distanceTo(a.point)
            .compareTo(location.distanceTo(b.point)),
      );
    setState(() {
      _spawns = spawns;
      _landmarks = landmarks;
    });
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _lastTick = elapsed;
    _time.value += dt;
    final frame = world.frame;
    if (frame == null) return;
    final (tx, ty) = world.toLocal(location.position);
    if (!identical(frame, _geo)) {
      _geo = frame;
      _ax = _bx = tx;
      _ay = ty;
      _by = ty - 4;
    }

    // Walk the avatar toward the latest GPS fix at a believable pace.
    final dx = tx - _ax, dy = ty - _ay;
    final d = sqrt(dx * dx + dy * dy);
    if (d > 300) {
      _ax = tx;
      _ay = ty;
      _moving = false;
    } else if (d > 0.35) {
      final speed = (d * 1.4).clamp(1.3, 10.0);
      final step = min(d, speed * dt);
      _ax += dx / d * step;
      _ay += dy / d * step;
      _heading = atan2(dx, dy);
      _moving = true;
      _phase += dt * (5 + speed * 1.5);
    } else {
      _moving = false;
    }

    // Buddy trots a few metres behind.
    final fx = _ax - sin(_heading) * 6, fy = _ay - cos(_heading) * 6;
    final k = min(1.0, dt * 3);
    _bx += (fx - _bx) * k;
    _by += (fy - _by) * k;

    _cam
      ..tx = _ax
      ..ty = _ay;
    final key = (_ax, _ay, _cam.yaw, _cam.zoom, _moving);
    if (key != _lastCam || _moving) {
      _lastCam = key;
      _frame.value++;
    }
  }

  // ---- Interaction ----------------------------------------------------------

  void _openSpawn(Spawn s) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EncounterSheet(spawn: s),
    );
  }

  void _openRadar() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TK.dusk,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _RadarSheet(
        spawns: _spawns,
        landmarks: _landmarks,
        onPick: (s) {
          Navigator.pop(context);
          _openSpawn(s);
        },
      ),
    );
  }

  void _openWeather() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: TK.dusk,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _WeatherSheet(),
    );
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cond = _cond;
    return Scaffold(
      backgroundColor: _palette.land,
      body: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: (_) => _zoomAtStart = _cam.zoom,
                  onScaleUpdate: (d) {
                    if (d.pointerCount > 1) {
                      _cam.zoom = (_zoomAtStart - (d.scale - 1) * 0.6).clamp(
                        0.0,
                        1.0,
                      );
                      _cam.yaw -= d.rotation * 0.02;
                    } else {
                      _cam.yaw -= d.focalPointDelta.dx * 0.007;
                      _cam.zoom = (_cam.zoom + d.focalPointDelta.dy * 0.0025)
                          .clamp(0.0, 1.0);
                    }
                  },
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: SkyPainter(
                              cam: _cam,
                              palette: _palette,
                              conditions: cond,
                              time: _time,
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: WorldPainter(
                              tiles: () => world.tiles,
                              cam: _cam,
                              palette: _palette,
                              player: () => (_ax, _ay),
                              reach: bondReach(),
                              ringColor: TK.signal,
                              hexes: _hexRings,
                              repaint: _frame,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: ValueListenableBuilder<int>(
                  valueListenable: _frame,
                  builder: (_, _, _) => _billboards(size),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: WeatherFxPainter(conditions: cond, time: _time),
                    ),
                  ),
                ),
              ),
              _topBar(cond),
              _bottomBar(),
              if (location.tooFast) _speedLock(),
              if (!world.hasAny) _loadingBadge(),
              Positioned(
                left: 8,
                bottom: 4,
                child: IgnorePointer(
                  child: Text(
                    '© OpenFreeMap © OpenMapTiles © OpenStreetMap · Weather: Open-Meteo',
                    style: TK.body(8.5, color: TK.ink.withValues(alpha: 0.55)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _billboards(Size size) {
    _cam.update(size);
    final items = <(double, Widget)>[];
    const dist = Distance();
    final me = location.position;

    void add(
      Key key,
      LatLng? at,
      double x,
      double y,
      double heightM,
      double minPx,
      double maxPx,
      double aspect,
      Widget child, {
      double lift = 0,
    }) {
      if (at != null) (x, y) = world.toLocal(at);
      _cam.view(x, y, lift);
      final depth = _cam.vz;
      if (depth < WorldCamera.near + 1) return;
      final sx = _cam.sx(_cam.vx, depth), sy = _cam.sy(_cam.vy, depth);
      final h = (heightM * _cam.scaleAt(depth)).clamp(minPx, maxPx);
      final w = h * aspect;
      if (sx < -w ||
          sx > size.width + w ||
          sy < -h * 0.2 ||
          sy > size.height + h) {
        return;
      }
      items.add((
        depth,
        Positioned(
          key: key,
          left: sx - w / 2,
          top: sy - h * 0.94,
          width: w,
          height: h,
          child: child,
        ),
      ));
    }

    if (world.frame == null) return const SizedBox.shrink();

    for (final s in _landmarks) {
      if (dist.as(LengthUnit.Meter, me, s.point) > landmarkBeaconMetres) {
        continue;
      }
      add(
        ValueKey('beam${s.id}'),
        s.point,
        0,
        0,
        160,
        120,
        520,
        0.14,
        const IgnorePointer(child: _Beam()),
      );
      add(
        ValueKey(s.id),
        s.point,
        0,
        0,
        26,
        52,
        170,
        1,
        GestureDetector(
          onTap: () => _openSpawn(s),
          child: _SpawnBadge(s, boosted: isBoosted(s)),
        ),
      );
    }
    for (final (i, s) in _spawns.indexed) {
      add(
        ValueKey(s.id),
        s.point,
        0,
        0,
        s.grade.index >= Grade.rare.index ? 17 : 14,
        40,
        150,
        1,
        GestureDetector(
          onTap: () => _openSpawn(s),
          child: Bobbing(
            phase: (i * 0.37) % 1,
            child: _SpawnBadge(s, boosted: isBoosted(s)),
          ),
        ),
      );
    }

    final conv = adventures.nextConvergence;
    if (conv != null && conv.announced) {
      add(
        const ValueKey('convBeam'),
        conv.at,
        0,
        0,
        220,
        140,
        600,
        0.14,
        const IgnorePointer(child: _Beam(colour: Color(0xFFE879F9))),
      );
      add(
        ValueKey('conv${conv.id}'),
        conv.at,
        0,
        0,
        30,
        64,
        180,
        1,
        GestureDetector(
          onTap: () => openConvergence(context, conv),
          child: _ConvergenceBeacon(conv),
        ),
      );
    }
    for (final d in adventures.nearbyDrops) {
      add(
        ValueKey('drop${d.id}'),
        d.area,
        0,
        0,
        12,
        40,
        110,
        1,
        GestureDetector(
          onTap: () => openDrop(context, d),
          child: const _DropCrate(),
        ),
      );
    }

    final b = buddy;
    if (b != null) {
      add(
        const ValueKey('buddy'),
        null,
        _bx,
        _by,
        10,
        34,
        90,
        1,
        KinSprite(b.species, size: 90, glow: false),
        lift: _moving ? (sin(_phase * 2)).abs() * 1.2 : 0,
      );
    }

    final rel = _heading - _cam.yaw;
    add(
      const ValueKey('me'),
      null,
      _ax,
      _ay,
      24,
      84,
      180,
      100 / 140,
      GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        ),
        child: CustomPaint(
          painter: AvatarPainter(
            style: profile.style,
            phase: _phase,
            moving: _moving,
            back: _moving && cos(rel) > 0.35,
            look: _moving ? sin(rel) : 0,
          ),
        ),
      ),
    );

    items.sort((a, b) => b.$1.compareTo(a.$1));
    return Stack(
      clipBehavior: Clip.none,
      children: [for (final i in items) i.$2],
    );
  }

  Widget _chip(
    Widget child, {
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) => GestureDetector(
    onTap: onTap,
    onLongPress: onLongPress,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: TK.dusk.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TK.slate),
      ),
      child: child,
    ),
  );

  Widget _topBar(Conditions cond) {
    final gps = switch (location.state) {
      LocationState.live => null,
      LocationState.starting => ('Finding you…', TK.signal),
      LocationState.denied => ('Location off · demo spot', TK.danger),
      LocationState.off => ('GPS disabled · demo spot', TK.danger),
    };
    final place = weather.place;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _chip(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  ),
                  Row(
                    children: [
                      SizedBox(
                        width: 22,
                        height: 30,
                        child: CustomPaint(
                          painter: AvatarPainter(style: profile.style),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(profile.style.name, style: TK.display(15)),
                          Text(
                            '${collection.count} Kin · ${fmtDistance(profile.walkedMetres)}',
                            style: TK.body(10, color: TK.mist),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: _chip(
                    onTap: _openWeather,
                    onLongPress: kDebugMode ? weather.cycleDebugSky : null,
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(cond.sky.icon, size: 18, color: TK.signal),
                        const SizedBox(width: 6),
                        Text(
                          weather.live ? '${cond.tempC.round()}°' : '–°',
                          style: TK.display(15),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            [
                              place ?? '…',
                              if (weather.debugSky != null) '(preview)',
                            ].join(' '),
                            overflow: TextOverflow.ellipsis,
                            style: TK.body(11, color: TK.mist, bold: true),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _chip(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MarketScreen()),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.account_balance_wallet_rounded,
                        size: 16,
                        color: TK.signal,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        fmtMon(chain.balance),
                        style: TK.body(12, bold: true),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.circle,
                        size: 12,
                        color: Color(0xFF5FBF6A),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${profile.totalOrbs}',
                        style: TK.body(12, bold: true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (strides.enabled && gps == null) ...[
                  _chip(
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(strides.cappedToday
                            ? 'You\'ve earned today\'s walking MON. More tomorrow.'
                            : 'Every 500 m walked with Terrakin open earns '
                                '${strides.perStep > BigInt.zero ? fmtMon(strides.perStep) : 'MON'}'
                                '${strides.stepsPerDay > 0 ? ' (up to ${strides.stepsPerDay * 500 ~/ 1000} km a day)' : ''}.'),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.directions_walk_rounded, size: 16, color: TK.signal),
                        const SizedBox(width: 4),
                        Text(
                          strides.cappedToday ? 'Done today' : '${strides.progressM.round()}/500 m',
                          style: TK.body(11, bold: true),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (gps != null)
                  _chip(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 9, color: gps.$2),
                        const SizedBox(width: 6),
                        Text(gps.$1, style: TK.body(11, bold: true)),
                      ],
                    ),
                  ),
                const Spacer(),
                _compass(),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SeasonScreen()),
                ),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: TK.dusk.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    border: Border.all(color: TK.signal.withValues(alpha: 0.6)),
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    color: TK.signal,
                    size: 22,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: _adventuresButton()),
          ],
        ),
      ),
    );
  }

  Widget _adventuresButton() {
    final live = adventures.looping ||
        adventures.nearbyDrops.isNotEmpty ||
        (adventures.nextConvergence?.announced ?? false);
    return GestureDetector(
      onTap: _openAdventures,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: TK.dusk.withValues(alpha: 0.9),
              shape: BoxShape.circle,
              border: Border.all(color: TK.loop.withValues(alpha: 0.7)),
            ),
            child: const Icon(Icons.explore_rounded, color: TK.loop, size: 24),
          ),
          if (live)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: TK.danger,
                  shape: BoxShape.circle,
                  border: Border.all(color: TK.dusk, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _closing = false;

  Future<void> _closeLoop() async {
    setState(() => _closing = true);
    final m = ScaffoldMessenger.of(context);
    try {
      final (taken, _) = await adventures.closeLoop();
      sound.play(Sfx.crown);
      m.showSnackBar(SnackBar(
        content: Text(taken == 0
            ? 'Loop closed, but everything inside was already held or defended.'
            : 'Loop closed: $taken ${taken == 1 ? 'hex is' : 'hexes are'} yours!'),
      ));
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  /// While walking a loop: progress, and the button to close it.
  Widget _loopBanner() {
    final n = adventures.distinctHexes;
    final back = adventures.canClose;
    final hint = adventures.loopError ??
        (back
            ? 'Back at the start. Close it!'
            : n < 6
                ? 'Walk ${6 - n} more ${6 - n == 1 ? 'hex' : 'hexes'}, then head back to the start'
                : 'Head back to your starting hex to close the loop');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _chip(
        Row(
          children: [
            const Icon(Icons.all_inclusive_rounded, color: TK.loop, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Loop · $n ${n == 1 ? 'hex' : 'hexes'}', style: TK.body(13, bold: true, color: TK.loop)),
                  Text(
                    hint,
                    style: TK.body(11, color: adventures.loopError != null ? TK.danger : TK.mist),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (back)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: TK.loop,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: _closing ? null : _closeLoop,
                child: _closing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: TK.ink))
                    : const Text('Close loop'),
              ),
            IconButton(
              tooltip: 'Abandon loop',
              onPressed: _closing ? null : adventures.cancelLoop,
              icon: const Icon(Icons.close_rounded, color: TK.mist),
            ),
          ],
        ),
      ),
    );
  }

  /// The hour before a Convergence and while it's open.
  Widget _convergenceChip(Convergence c) {
    final now = DateTime.now();
    final when = c.open
        ? 'OPEN · ${c.closesAt.difference(now).inMinutes + 1} min left'
        : 'in ${c.opensAt.difference(now).inMinutes + 1} min';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _chip(
        onTap: () => openConvergence(context, c),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.blur_circular_rounded, size: 18, color: Grade.mythic.color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Convergence $when · ${c.name} · ${fmtDistance(location.distanceTo(c.at))}',
                overflow: TextOverflow.ellipsis,
                style: TK.body(12, bold: true, color: c.open ? TK.signal : TK.paper),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compass() => ValueListenableBuilder<int>(
    valueListenable: _frame,
    builder: (_, _, _) => GestureDetector(
      onTap: () => _cam
        ..yaw = 0
        ..zoom = 0.3,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: TK.dusk.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          border: Border.all(color: TK.slate),
        ),
        child: Transform.rotate(
          angle: -_cam.yaw,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.navigation_rounded, size: 18, color: TK.danger),
              Text('N', style: TK.body(9, bold: true)),
            ],
          ),
        ),
      ),
    ),
  );

  /// Today's raid at the nearest Landmark.
  void _openRaid() {
    const dist = Distance();
    final me = location.position;
    final nearest = [..._landmarks]
      ..sort(
        (a, b) => dist
            .as(LengthUnit.Meter, me, a.point)
            .compareTo(dist.as(LengthUnit.Meter, me, b.point)),
      );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TK.dusk,
      builder: (_) => RaidSheet(landmark: nearest.first),
    );
  }

  Widget _bottomBar() {
    final lm = _landmarks.where((s) => !collection.isBonded(s.id)).firstOrNull;
    final me = location.position;
    final conv = adventures.nextConvergence;
    return Positioned(
      left: 16,
      right: 16,
      bottom: 22,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (adventures.looping) _loopBanner(),
            if (conv != null && conv.announced) _convergenceChip(conv),
            if (lm != null || _landmarks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (lm != null)
                      Flexible(
                        child: _chip(
                          onTap: () => _openSpawn(lm),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.flag_rounded,
                                size: 16,
                                color: TK.signal,
                              ),
                              const SizedBox(width: 6),
                              Image.asset(
                                lm.species.sprite,
                                width: 24,
                                height: 24,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Landmark ${lm.grade.label} ${lm.species.name} · '
                                  '${fmtDistance(location.distanceTo(lm.point))} ${compassPoint(me, lm.point)}',
                                  overflow: TextOverflow.ellipsis,
                                  style: TK.body(12, bold: true),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_landmarks.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _chip(
                        onTap: () => _openRaid(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.local_fire_department_rounded,
                              size: 16,
                              color: TK.danger,
                            ),
                            const SizedBox(width: 4),
                            Text('Raid', style: TK.body(12, bold: true)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            Row(
              children: [
                _roundButton(Icons.auto_stories_rounded, 'Atlas', () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AtlasScreen()),
                  );
                }),
                const SizedBox(width: 10),
                _roundButton(Icons.swap_horiz_rounded, 'Trade', () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TradeScreen()),
                  );
                }),
                const SizedBox(width: 10),
                _roundButton(Icons.hexagon_rounded, 'Turf', () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: TK.dusk,
                    builder: (_) => const HexSheet(),
                  );
                }),
                const Spacer(),
                _chip(
                  onTap: _openRadar,
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.radar_rounded,
                        size: 18,
                        color: TK.signal,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_spawns.length} nearby',
                        style: TK.body(13, bold: true),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                _roundButton(Icons.science_rounded, 'Lab', () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LabScreen()),
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundButton(IconData icon, String label, VoidCallback onTap) =>
      Semantics(
        label: label,
        button: true,
        child: Material(
          color: TK.paper,
          shape: const CircleBorder(side: BorderSide(color: TK.ink, width: 3)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Icon(icon, color: TK.ink, size: 28),
            ),
          ),
        ),
      );

  Widget _loadingBadge() => Center(
    child: _chip(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!world.offline)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: TK.signal,
              ),
            )
          else
            const Icon(Icons.cloud_off_rounded, size: 16, color: TK.danger),
          const SizedBox(width: 8),
          Text(
            world.offline
                ? 'No connection · map unavailable'
                : 'Loading the world around you…',
            style: TK.body(12, bold: true),
          ),
          if (world.offline) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                world.retryFailed();
                world.ensureAround(location.position);
              },
              child: Text(
                'Retry',
                style: TK.body(12, color: TK.signal, bold: true),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _speedLock() => Positioned.fill(
    child: Container(
      color: TK.night.withValues(alpha: 0.8),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Moving too fast', style: TK.display(26)),
          const SizedBox(height: 8),
          Text(
            'Kin hide from vehicles. They will be back when you slow down.',
            textAlign: TextAlign.center,
            style: TK.body(14, color: TK.mist),
          ),
        ],
      ),
    ),
  );
}

/// Kin on the map, with a small badge for weather boosts and Landmarks.
class _SpawnBadge extends StatelessWidget {
  const _SpawnBadge(this.s, {required this.boosted});
  final Spawn s;
  final bool boosted;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) {
      final size = box.maxHeight;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          KinSprite(s.species, size: size),
          if (boosted || s.landmark)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: EdgeInsets.all(size * 0.04),
                decoration: BoxDecoration(
                  color: s.landmark ? TK.signal : TK.dusk,
                  shape: BoxShape.circle,
                  border: Border.all(color: TK.ink, width: 1.5),
                ),
                child: Icon(
                  s.landmark ? Icons.flag_rounded : Icons.cyclone_rounded,
                  size: max(12, size * 0.18),
                  color: s.landmark ? TK.ink : TK.signal,
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _Beam extends StatelessWidget {
  const _Beam({this.colour = TK.signal});
  final Color colour;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(40),
      gradient: LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          colour.withValues(alpha: 0.55),
          colour.withValues(alpha: 0),
        ],
      ),
    ),
  );
}

class _RadarSheet extends StatelessWidget {
  const _RadarSheet({
    required this.spawns,
    required this.landmarks,
    required this.onPick,
  });
  final List<Spawn> spawns;
  final List<Spawn> landmarks;
  final void Function(Spawn) onPick;

  @override
  Widget build(BuildContext context) {
    final me = location.position;
    final near = [...spawns]
      ..sort(
        (a, b) => location
            .distanceTo(a.point)
            .compareTo(location.distanceTo(b.point)),
      );
    Widget row(Spawn s, {bool done = false}) => ListTile(
      onTap: () => onPick(s),
      leading: Image.asset(s.species.sprite, width: 40, height: 40),
      title: Text(s.species.name, style: TK.display(16)),
      subtitle: Row(
        children: [
          GradeGems(s.grade, size: 12),
          const SizedBox(width: 6),
          if (isBoosted(s))
            const Icon(Icons.cyclone_rounded, size: 14, color: TK.signal),
          if (done) Text('  bonded', style: TK.body(11, color: TK.mist)),
        ],
      ),
      trailing: Text(
        '${fmtDistance(location.distanceTo(s.point))} ${compassPoint(me, s.point)}',
        style: TK.body(13, bold: true),
      ),
    );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (_, ctrl) => ListView(
        controller: ctrl,
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Landmark Kin', style: TK.display(20)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              'One per ~4.5 km zone, all day, at the same spot for every player. Walk there to bond.',
              style: TK.body(12, color: TK.mist),
            ),
          ),
          for (final s in landmarks) row(s, done: collection.isBonded(s.id)),
          const Divider(color: TK.slate, height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Nearby (${near.length})', style: TK.display(20)),
          ),
          if (near.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Nothing close right now. Wild Kin shuffle every 15 minutes.',
                style: TK.body(13, color: TK.mist),
              ),
            ),
          for (final s in near) row(s),
        ],
      ),
    );
  }
}

class _WeatherSheet extends StatelessWidget {
  const _WeatherSheet();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: weather,
    builder: (context, _) {
      final c = conditions;
      final p = location.position;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(c.sky.icon, color: TK.signal, size: 34),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${c.sky.label} · ${c.tempC.round()}°C',
                          style: TK.display(22),
                        ),
                        Text(
                          [
                                weather.place,
                                weather.country,
                              ].whereType<String>().join(', ') +
                              (weather.place == null ? 'Locating…' : ''),
                          style: TK.body(13, color: TK.mist),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Tag(c.timeLabel, icon: Icons.schedule_rounded, dark: true),
                  Tag(
                    'Wind ${c.windKmh.round()} km/h',
                    icon: Icons.air_rounded,
                    dark: true,
                  ),
                  Tag(
                    '${p.latitude.toStringAsFixed(3)}, ${p.longitude.toStringAsFixed(3)}',
                    icon: Icons.place_rounded,
                    dark: true,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Boosted right now', style: TK.display(16)),
              const SizedBox(height: 4),
              Text(
                'These Kin spawn more, bond easier and hit harder in this weather.',
                style: TK.body(12, color: TK.mist),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (final a in c.boosted)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(a.emblem, width: 26),
                        const SizedBox(width: 4),
                        Text(a.label, style: TK.body(13, bold: true)),
                      ],
                    ),
                ],
              ),
              if (c.dampened.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Sulking: ${c.dampened.map((a) => a.label).join(', ')} (×0.9)',
                  style: TK.body(12, color: TK.danger),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                weather.live
                    ? 'Live from Open-Meteo for your coordinates · updates every 10 min'
                    : 'Waiting for live weather…',
                style: TK.body(11, color: TK.mist),
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: weather.cycleDebugSky,
                  child: Text(
                    weather.debugSky == null
                        ? 'Preview another sky (debug)'
                        : 'Previewing ${weather.debugSky!.label} · tap for next',
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// Where a Convergence will open: the Mythic's silhouette until it does.
class _ConvergenceBeacon extends StatelessWidget {
  const _ConvergenceBeacon(this.c);
  final Convergence c;

  @override
  Widget build(BuildContext context) {
    final sp = species[c.species];
    return Bobbing(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: TK.night.withValues(alpha: 0.8),
          border: Border.all(color: Grade.mythic.color, width: 3),
          boxShadow: [BoxShadow(color: Grade.mythic.color.withValues(alpha: 0.6), blurRadius: 18, spreadRadius: 2)],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: c.open ? Image.asset(sp.sprite) : Silhouette(sp, size: 96),
        ),
      ),
    );
  }
}

/// A dead drop somewhere in this hex.
class _DropCrate extends StatelessWidget {
  const _DropCrate();

  @override
  Widget build(BuildContext context) => Bobbing(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: TK.night.withValues(alpha: 0.85),
            border: Border.all(color: TK.drop, width: 2.5),
          ),
          child: const FittedBox(
            child: Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.question_mark_rounded, color: TK.drop),
            ),
          ),
        ),
      );
}
