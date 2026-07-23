import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import 'backup_format.dart';
import 'backup_import.dart';
import 'backup_providers.dart';
import 'backup_restore_screen.dart' show PrimaryButton;

/// Restore flow (FR-38, FR-39, FR-40) — prototype phone 10: pick a file,
/// preview it, choose Merge/Replace, restore.
class RestoreScreen extends ConsumerStatefulWidget {
  const RestoreScreen({super.key});

  @override
  ConsumerState<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends ConsumerState<RestoreScreen> {
  BackupPreview? _preview;
  RestoreMode _mode = RestoreMode.merge;
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;

    return Scaffold(
      appBar: AppBar(title: const Text('Restore data')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 40),
        children: [
          GestureDetector(
            onTap: _busy ? null : _pickFile,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(color: palette.line, width: 1.5, style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  const Text('📄', style: TextStyle(fontSize: 28)),
                  const SizedBox(height: 8),
                  Text(_preview == null ? 'Choose backup file' : _preview!.fileName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    _busy ? 'Reading…' : 'Tap to browse iCloud Drive, Google Drive, or Files',
                    style: TextStyle(fontSize: 12, color: palette.textDim),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
          ],
          if (_preview != null) ...[
            const SectionTitle('File preview'),
            AppCard(
              child: Column(
                children: [
                  _PreviewRow('File', _preview!.fileName),
                  _PreviewRow('Backup date', DateFormat.yMMMd().add_jm().format(_preview!.exportedAt)),
                  _PreviewRow('Expenses', '${_preview!.expenseCount} transactions'),
                  _PreviewRow('Date range', _dateRangeLabel(_preview!.expenseDateRange)),
                  _PreviewRow('File size', _formatSize(_preview!.fileSizeBytes)),
                ],
              ),
            ),
            const SectionTitle('How should we restore?'),
            _RestoreModeCard(
              title: 'Merge',
              description: "Add backup data to what's already on this device. Duplicate-safe.",
              selected: _mode == RestoreMode.merge,
              onTap: () => setState(() => _mode = RestoreMode.merge),
            ),
            const SizedBox(height: AppSpacing.sm),
            _RestoreModeCard(
              title: 'Replace',
              description: 'Erase current data on this device and restore only from the backup file.',
              selected: _mode == RestoreMode.replace,
              onTap: () => setState(() => _mode = RestoreMode.replace),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: _busy ? 'Restoring…' : 'Restore data',
              onTap: _busy ? null : _restore,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _preview = null;
    });
    final result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    await _loadFile(path);
  }

  Future<void> _loadFile(String path, {String? password}) async {
    setState(() => _busy = true);
    try {
      final preview = await loadAndValidate(path, password: password);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _error = null;
      });
    } on BackupPasswordRequiredException {
      if (!mounted) return;
      final entered = await _askPassword(context, wrongPassword: password != null);
      if (entered == null || !mounted) return;
      await _loadFile(path, password: entered);
      return;
    } on BackupWrongPasswordException {
      if (!mounted) return;
      final entered = await _askPassword(context, wrongPassword: true);
      if (entered == null || !mounted) return;
      await _loadFile(path, password: entered);
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askPassword(BuildContext context, {required bool wrongPassword}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Password required'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (wrongPassword)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text('Incorrect password — try again.',
                    style: TextStyle(color: AppColors.red, fontSize: 12)),
              ),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
  }

  Future<void> _restore() async {
    final preview = _preview;
    if (preview == null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final repo = ref.read(backupRepositoryProvider);
      await executeRestore(preview.payload, _mode, repo);
      messenger.showSnackBar(const SnackBar(content: Text('Data restored')));
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _dateRangeLabel((DateTime, DateTime)? range) {
    if (range == null) return '—';
    final df = DateFormat.yMMM();
    return '${df.format(range.$1)} – ${df.format(range.$2)}';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: palette.textDim)),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _RestoreModeCard extends StatelessWidget {
  const _RestoreModeCard({
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.08) : palette.card,
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: Border.all(color: selected ? AppColors.primary : palette.line, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20,
              height: 20,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? AppColors.primary : palette.line, width: 2),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration:
                            const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(description,
                      style: TextStyle(fontSize: 11, color: palette.textDim, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
