import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/copy.dart';
import '../core/sound.dart';
import 'season_screen.dart';
import '../core/economy.dart';
import '../core/theme.dart';
import '../widgets/kin_widgets.dart';
import 'atlas_screen.dart';
import 'market_screen.dart';
import 'mint_screen.dart';
import 'onboarding.dart';

/// Your character, buddy and walking stats.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: TK.night, title: Text('Wayfinder', style: TK.display(22))),
        body: ListenableBuilder(
          listenable: Listenable.merge([profile, collection, chain]),
          builder: (context, _) {
            final s = profile.style;
            final b = buddy;
            final bonded = collection.count;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: TK.paper,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: s.top, width: 4),
                  ),
                  child: Row(
                    children: [
                      AvatarView(s, size: 150),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name, style: TK.display(28, color: TK.ink)),
                            Text(s.title, style: TK.body(13, color: TK.ink.withValues(alpha: 0.6), bold: true)),
                            const SizedBox(height: 6),
                            Text('@${chain.name}', style: TK.body(14, color: TK.ink, bold: true)),
                            GestureDetector(
                              onTap: () => Clipboard.setData(ClipboardData(text: chain.address ?? '')),
                              child: Text(
                                '${shortAddress(chain.address)} · copy',
                                style: TK.body(11, color: TK.ink.withValues(alpha: 0.5)),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text.rich(TextSpan(children: [
                              TextSpan(text: '${s.perk.label}  ', style: TK.body(13, color: TK.ink, bold: true)),
                              TextSpan(text: s.perk.description, style: TK.body(13, color: TK.ink)),
                            ])),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  _stat('Walked', fmtDistance(profile.walkedMetres)),
                  const SizedBox(width: 10),
                  _stat('Kin bonded', '$bonded'),
                  const SizedBox(width: 10),
                  _stat('Balance', fmtMon(chain.balance)),
                ]),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MarketScreen())),
                  icon: const Icon(Icons.storefront_rounded),
                  label: Text('Market · ${profile.totalOrbs} orbs in bag'),
                ),
                const SizedBox(height: 20),
                Text('Buddy', style: TK.display(20)),
                const SizedBox(height: 4),
                Text('Your buddy walks beside you, levels up from real distance walked, and lends its ability.',
                    style: TK.body(12, color: TK.mist)),
                const SizedBox(height: 8),
                Material(
                  color: TK.dusk,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AtlasScreen())),
                    leading: b == null
                        ? const Icon(Icons.pets_rounded, color: TK.mist, size: 36)
                        : Image.asset(b.species.sprite, width: 48),
                    title: Text(b == null ? 'No buddy yet' : '${b.species.name} · Lv ${b.level}', style: TK.display(17)),
                    subtitle: Text(
                      b == null ? 'Pick one in the Atlas' : '${b.species.ability.label}: ${b.species.ability.description}',
                      style: TK.body(12, color: TK.mist),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: TK.mist),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Your characters', style: TK.display(20)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 150,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final a in profile.avatars)
                        GestureDetector(
                          onTap: () => profile.setActive(a.tokenId),
                          child: Container(
                            width: 110,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: TK.dusk,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: a.tokenId == profile.active?.tokenId ? TK.signal : TK.slate,
                                width: 2,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AvatarView(a.style, size: 90, walking: a.tokenId == profile.active?.tokenId),
                                Text(a.style.name, style: TK.display(15)),
                              ],
                            ),
                          ),
                        ),
                      GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MintScreen())),
                        child: Container(
                          width: 110,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: TK.slate, width: 2),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Builder(builder: (context) {
                            // Still opens the Mint screen to browse; it just reads as out of reach.
                            final price = chain.prices?.nextCharacter;
                            final affordable = price != null && chain.balance >= price;
                            return Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_circle_rounded, color: affordable ? TK.signal : TK.slate, size: 34),
                                const SizedBox(height: 6),
                                Text(
                                  price == null
                                      ? 'Mint one'
                                      : affordable
                                          ? 'Mint one · ${fmtMon(price)}'
                                          : 'Need ${fmtMon(price)}',
                                  textAlign: TextAlign.center,
                                  style: TK.body(12, color: affordable ? TK.paper : TK.mist, bold: true),
                                ),
                              ],
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('Your turf', style: TK.display(20)),
                const SizedBox(height: 6),
                ListenableBuilder(
                  listenable: territory,
                  builder: (context, _) => Text(
                    territory.mine.isEmpty
                        ? 'No hexes yet. Stand in one and tap Turf on the map.'
                        : '${territory.mine.length} hex${territory.mine.length == 1 ? '' : 'es'} · you take a cut of every catch in them',
                    style: TK.body(13, color: TK.mist),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SeasonScreen())),
                      icon: const Icon(Icons.emoji_events_rounded),
                      label: const Text('Leaderboard'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const SeasonScreen(initialTab: 2))),
                      icon: const Icon(Icons.groups_rounded),
                      label: ListenableBuilder(
                        listenable: social,
                        builder: (_, _) => Text(social.myCrew == null ? 'Crew' : '[${social.myCrew!.tag}] Crew'),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                Text('Sound', style: TK.display(20)),
                ListenableBuilder(
                  listenable: sound,
                  builder: (context, _) => Column(children: [
                    for (final (label, icon, value, set) in [
                      ('Music', Icons.music_note_rounded, sound.music, (double v) => sound.setVolumes(music: v)),
                      ('Effects', Icons.graphic_eq_rounded, sound.sfx, (double v) => sound.setVolumes(sfx: v)),
                    ])
                      Row(children: [
                        Icon(icon, color: value == 0 ? TK.mist : TK.signal, size: 20),
                        SizedBox(width: 64, child: Text(' $label', style: TK.body(13, bold: true))),
                        Expanded(
                          child: Slider(
                            value: value,
                            onChanged: set,
                            onChangeEnd: (_) => sound.play(Sfx.tap),
                          ),
                        ),
                      ]),
                  ]),
                ),
                const SizedBox(height: 12),
                Text('Tone', style: TK.display(20)),
                const SizedBox(height: 8),
                ListenableBuilder(
                  listenable: copy,
                  builder: (context, _) => SegmentedButton<Tone>(
                    segments: const [
                      ButtonSegment(value: Tone.normal, label: Text('Normal')),
                      ButtonSegment(value: Tone.unhinged, label: Text('Unhinged 💀')),
                    ],
                    selected: {copy.tone},
                    onSelectionChanged: (t) => copy.setTone(t.first),
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () async {
                    await auth.logOut();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const RootGate()),
                        (_) => false,
                      );
                    }
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
              ],
            );
          },
        ),
      );

  Widget _stat(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: TK.dusk, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Text(value, style: TK.display(20, color: TK.signal)),
            Text(label, style: TK.body(11, color: TK.mist)),
          ]),
        ),
      );
}
