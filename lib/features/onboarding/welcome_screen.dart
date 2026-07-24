import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../backup/backup_restore_screen.dart' show PrimaryButton;
import '../profile/profile_provider.dart';

/// First-launch Welcome/Onboarding screen (FR-44–FR-50) — prototype phone 0.
/// Name is mandatory, phone/email optional. Saving writes straight into the
/// same [profileProvider] Settings/Profile already uses; the app root
/// (`app.dart`) watches that provider and swaps to [HomeScreen] on its own
/// once `profile.name` is non-empty, so this screen never navigates itself.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  bool _seeded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  /// Seeds phone/email (not name — definitionally blank whenever this screen
  /// is reachable) in case an existing install already saved them via the
  /// Profile screen before ever entering a name.
  void _seed(Profile profile) {
    if (_seeded) return;
    _seeded = true;
    _phone.text = profile.phone;
    _email.text = profile.email;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref
        .read(profileProvider.notifier)
        .save(
          Profile(
            name: _name.text.trim(),
            phone: _phone.text.trim(),
            email: _email.text.trim(),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    ref.watch(profileProvider).whenData(_seed);
    final ready = _name.text.trim().isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxl,
            AppSpacing.xxl,
            AppSpacing.xxl,
            40,
          ),
          children: [
            SizedBox(
              height: 130,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.1),
                      ),
                    ),
                  ),
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: AppColors.heroGradient,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.4),
                          blurRadius: 30,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '₹',
                      style: TextStyle(
                        fontFamily: 'Sora',
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Welcome to Spendly',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Sora',
                fontSize: 21,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              "Let's set up your profile — takes 10 seconds",
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textDim, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.xxl),
            _label('Name', required: true, palette: palette),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.person_outline),
                hintText: 'e.g. Aditi Sharma',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _label('Phone number', required: false, palette: palette),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.phone_outlined),
                hintText: '+91 98765 43210',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _label('Email address', required: false, palette: palette),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.mail_outline),
                hintText: 'you@example.com',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Phone and email just help us restore your backups faster — '
              'you can always add them later in Settings.',
              style: TextStyle(
                color: palette.textDim,
                fontSize: 11.5,
                height: 1.6,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: _saving ? 'Saving…' : 'Get started',
              onTap: (ready && !_saving) ? _save : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(
    String text, {
    required bool required,
    required AppPalette palette,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.textDim,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          if (required)
            const Text(
              '*',
              style: TextStyle(
                color: AppColors.pink,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: palette.card2,
                border: Border.all(color: palette.line),
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Text(
                'OPTIONAL',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: palette.textDim,
                  letterSpacing: 0.3,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
