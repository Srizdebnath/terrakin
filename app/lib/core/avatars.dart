import 'package:flutter/painting.dart';

enum Hair { spiky, bob, cap, bun, curly, hood }

enum Perk {
  longReach('Long Reach', 'Bond reach +10 m.'),
  tidewalker('Tidewalker', 'Tide and Grove Kin: +10% bond chance.'),
  stormchaser('Stormchaser', 'Weather-boosted Kin: +10% bond chance.'),
  cartographer('Cartographer', 'See wild Kin from 450 m instead of 300 m.'),
  hearthkeeper('Hearthkeeper', 'Your buddy earns 25% more Stride.'),
  nightwalker('Nightwalker', 'At night: +10% bond chance on every Kin.');

  const Perk(this.label, this.description);
  final String label;
  final String description;
}

/// A mintable player character, drawn in code by AvatarPainter.
class AvatarStyle {
  const AvatarStyle({
    required this.id,
    required this.name,
    required this.title,
    required this.perk,
    required this.skin,
    required this.hair,
    required this.hairColor,
    required this.top,
    required this.bottom,
    required this.accent,
  });

  final String id, name, title;
  final Perk perk;
  final Color skin;
  final Hair hair;
  final Color hairColor, top, bottom, accent;
}

const avatarStyles = <AvatarStyle>[
  AvatarStyle(
    id: 'rio',
    name: 'Rio',
    title: 'Trailblazer',
    perk: Perk.longReach,
    skin: Color(0xFFD9A27A),
    hair: Hair.spiky,
    hairColor: Color(0xFF2B1D16),
    top: Color(0xFFFF8A3D),
    bottom: Color(0xFF3A3452),
    accent: Color(0xFFFFD93D),
  ),
  AvatarStyle(
    id: 'mira',
    name: 'Mira',
    title: 'Tidewalker',
    perk: Perk.tidewalker,
    skin: Color(0xFFC68B5E),
    hair: Hair.bob,
    hairColor: Color(0xFF1C1A2E),
    top: Color(0xFF4CB3E6),
    bottom: Color(0xFFF6EFE2),
    accent: Color(0xFF2E85B8),
  ),
  AvatarStyle(
    id: 'kai',
    name: 'Kai',
    title: 'Stormchaser',
    perk: Perk.stormchaser,
    skin: Color(0xFF8D5A3B),
    hair: Hair.cap,
    hairColor: Color(0xFF151018),
    top: Color(0xFF3A3452),
    bottom: Color(0xFF68748A),
    accent: Color(0xFFFFD93D),
  ),
  AvatarStyle(
    id: 'juno',
    name: 'Juno',
    title: 'Cartographer',
    perk: Perk.cartographer,
    skin: Color(0xFFF1C7A0),
    hair: Hair.bun,
    hairColor: Color(0xFF7A3B2E),
    top: Color(0xFF5FBF6A),
    bottom: Color(0xFF6B4F3A),
    accent: Color(0xFFF6EFE2),
  ),
  AvatarStyle(
    id: 'sol',
    name: 'Sol',
    title: 'Hearthkeeper',
    perk: Perk.hearthkeeper,
    skin: Color(0xFFA86F4C),
    hair: Hair.curly,
    hairColor: Color(0xFF20140F),
    top: Color(0xFFC9A26B),
    bottom: Color(0xFF3E9150),
    accent: Color(0xFFFF5D6C),
  ),
  AvatarStyle(
    id: 'nova',
    name: 'Nova',
    title: 'Nightwalker',
    perk: Perk.nightwalker,
    skin: Color(0xFFE0B08C),
    hair: Hair.hood,
    hairColor: Color(0xFFE8C6FF),
    top: Color(0xFFC77DFF),
    bottom: Color(0xFF231A2E),
    accent: Color(0xFFE8C6FF),
  ),
];

AvatarStyle avatarById(String id) =>
    avatarStyles.firstWhere((a) => a.id == id, orElse: () => avatarStyles.first);
