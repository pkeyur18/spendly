import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// The 5 preset avatar gradients (FR-54), colors lifted verbatim from the
/// prototype's `.avatar-opt` swatches. Index 0 is the default (FR-55) — also
/// the main app avatar's own gradient.
const avatarGradients = <List<Color>>[
  [AppColors.primaryDeep, AppColors.primary, AppColors.pink], // default
  [AppColors.accent, AppColors.red],
  [AppColors.teal, Color(0xFF0D9488)], // teal deep
  [AppColors.primarySoft, AppColors.primary],
  [AppColors.pink, Color(0xFFF472B6)], // pink light
];

LinearGradient gradientAt(int? index) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: avatarGradients[(index ?? 0).clamp(0, avatarGradients.length - 1)],
);

/// Pure, never throws, never returns something unrenderable (FR-55) — even
/// for a blank, single-word, multi-word, or emoji-only name.
String initialsFor(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '';

  String firstGrapheme(String w) {
    final chars = w.characters;
    return chars.isEmpty ? '' : chars.first.toUpperCase();
  }

  if (words.length == 1) return firstGrapheme(words.first);
  return firstGrapheme(words.first) + firstGrapheme(words.last);
}

/// Shared avatar render: a photo if one's set, else colored initials —
/// the one path used by Profile's hero, Edit Profile, and Avatar Picker, so
/// there is never a blank/broken-image state anywhere (FR-55).
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.name,
    this.photoBytes,
    this.avatarColorIndex,
    this.size = 92,
    this.fontSize = 32,
  });

  final String name;
  final Uint8List? photoBytes;
  final int? avatarColorIndex;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoBytes != null;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasPhoto ? null : gradientAt(avatarColorIndex),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.4),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? Image.memory(
              photoBytes!,
              width: size,
              height: size,
              fit: BoxFit.cover,
            )
          : Text(
              initialsFor(name),
              style: TextStyle(
                fontFamily: 'Sora',
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}
