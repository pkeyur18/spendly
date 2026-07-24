import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/async_state_views.dart';
import '../backup/backup_restore_screen.dart' show PrimaryButton;
import 'avatar.dart';
import 'avatar_picker_screen.dart';
import 'profile_provider.dart';

/// Edit profile (FR-52) — prototype phone 11. Name/phone/email form, with the
/// avatar + edit-pencil at top linking to the Avatar Picker.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  bool _seeded = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _seed(Profile profile) {
    if (_seeded) return;
    _seeded = true;
    _name.text = profile.name;
    _email.text = profile.email;
    _phone.text = profile.phone;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final current = ref.read(profileProvider).value ?? const Profile();
    await ref
        .read(profileProvider.notifier)
        .save(
          current.copyWith(
            name: _name.text.trim(),
            email: _email.text.trim(),
            phone: _phone.text.trim(),
          ),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    messenger.showSnackBar(const SnackBar(content: Text('Profile updated')));
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
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
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ProfileAvatar(
                      name: profile.name,
                      photoBytes: profile.photoBytes,
                      avatarColorIndex: profile.avatarColorIndex,
                    ),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: _EditBadge(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AvatarPickerScreen(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.person_outline),
                  labelText: 'Your name',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.phone_outlined),
                  labelText: 'Phone number',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.mail_outline),
                  labelText: 'Email address',
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: _saving ? 'Saving…' : 'Save changes',
                onTap: _saving ? null : _save,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EditBadge extends StatelessWidget {
  const _EditBadge({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Semantics(
      button: true,
      label: 'Change photo or avatar',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.card,
            border: Border.all(color: palette.textDim.withValues(alpha: 0.3)),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.edit, size: 14),
        ),
      ),
    );
  }
}
