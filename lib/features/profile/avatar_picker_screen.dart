import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/async_state_views.dart';
import '../../core/widgets/glass.dart';
import '../backup/backup_restore_screen.dart' show PrimaryButton;
import 'avatar.dart';
import 'profile_provider.dart';

/// Avatar Picker (FR-53, FR-54) — prototype phone 12. Upload a real photo, or
/// pick one of 5 preset colored-initials gradients.
class AvatarPickerScreen extends ConsumerStatefulWidget {
  const AvatarPickerScreen({super.key});

  @override
  ConsumerState<AvatarPickerScreen> createState() =>
      _AvatarPickerScreenState();
}

class _AvatarPickerScreenState extends ConsumerState<AvatarPickerScreen> {
  Uint8List? _photoBytes;
  int? _colorIndex;
  bool _seeded = false;
  bool _saving = false;

  void _seed(Profile profile) {
    if (_seeded) return;
    _seeded = true;
    _photoBytes = profile.photoBytes;
    _colorIndex = profile.avatarColorIndex;
  }

  Future<void> _pickPhoto() async {
    final source = await showGlassSheet<ImageSource>(
      context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo library'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    final bytes = await File(picked.path).readAsBytes();

    setState(() {
      _photoBytes = bytes;
      _colorIndex = null;
    });
  }

  void _pickColor(int index) {
    setState(() {
      _colorIndex = index;
      _photoBytes = null;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final current = ref.read(profileProvider).value ?? const Profile();
    await ref
        .read(profileProvider.notifier)
        .save(
          current.copyWith(
            photoBytes: _photoBytes,
            clearPhotoBytes: _photoBytes == null,
            avatarColorIndex: _colorIndex,
            clearAvatarColorIndex: _colorIndex == null,
          ),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    messenger.showSnackBar(const SnackBar(content: Text('Avatar saved')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final palette = Theme.of(context).extension<AppPalette>()!;

    return Scaffold(
      appBar: AppBar(title: const Text('Choose photo')),
      body: profileAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: 'Couldn\'t load profile.',
          onRetry: () => ref.invalidate(profileProvider),
        ),
        data: (profile) {
          _seed(profile);
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              40,
            ),
            children: [
              Center(
                child: ProfileAvatar(
                  name: profile.name,
                  photoBytes: _photoBytes,
                  avatarColorIndex: _colorIndex,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Semantics(
                button: true,
                label: 'Upload a photo, camera or photo library',
                child: InkWell(
                  onTap: _pickPhoto,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 26,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                        color: palette.line,
                        width: 1.5,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Column(
                      children: [
                        const Text('📷', style: TextStyle(fontSize: 28)),
                        const SizedBox(height: AppSpacing.sm),
                        const Text(
                          'Upload a photo',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Camera or photo library',
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SectionTitle('Or pick an avatar style'),
              SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < avatarGradients.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: _ColorSwatch(
                          index: i,
                          selected: _photoBytes == null && (_colorIndex ?? 0) == i,
                          onTap: () => _pickColor(i),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: palette.card2,
                  border: Border.all(color: palette.line),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "No photo? We'll always show your initials on a color you "
                  'pick, so the app still feels personal — this is the '
                  'default for everyone until they add a real photo.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: palette.textDim,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: _saving ? 'Saving…' : 'Save',
                onTap: _saving ? null : _save,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Avatar color ${index + 1}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: gradientAt(index),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 2.5,
            ),
          ),
          alignment: Alignment.center,
          child: selected
              ? Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.35),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.check, color: Colors.white, size: 18),
                )
              : null,
        ),
      ),
    );
  }
}
