import 'package:flutter/material.dart';

import '../../features/expenses/recurring_schedule.dart';
import '../../features/expenses/widgets/expense_tile.dart'
    show relativeDayLabel;
import '../db/database.dart';
import '../theme/tokens.dart';

/// The "Repeat" bottom sheet — originally Quick Add's own, extracted so
/// Income's recurring toggle looks and behaves identically rather than
/// growing a near-duplicate (same move as `icon_color_picker.dart`).
/// Schedule and end-date live in the caller (`onRecurrenceChanged`/
/// `onEndDateChanged`); the sheet stays open after a choice — same as
/// before extraction — so picking "Monthly" and then setting an end date is
/// still one sheet visit, not two.
Future<void> showRepeatPickerSheet(
  BuildContext context, {
  required Recurrence? recurrence,
  required DateTime? endDate,
  required DateTime anchorDate,
  required ValueChanged<Recurrence?> onRecurrenceChanged,
  required ValueChanged<DateTime?> onEndDateChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (sheetContext) {
      var sheetRecurrence = recurrence;
      var sheetEndDate = endDate;
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          void choose(Recurrence? r) {
            setSheetState(() {
              sheetRecurrence = r;
              // An end date without a schedule is meaningless, and leaving a
              // stale one behind would silently truncate the series if repeat
              // were switched back on later.
              if (r == null) sheetEndDate = null;
            });
            onRecurrenceChanged(r);
            if (r == null) onEndDateChanged(null);
          }

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: Text(
                    'Repeat',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                RadioGroup<Recurrence?>(
                  groupValue: sheetRecurrence,
                  onChanged: choose,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<Recurrence?>(
                        value: null,
                        title: const Text('Does not repeat'),
                      ),
                      for (final r in Recurrence.values)
                        RadioListTile<Recurrence?>(
                          value: r,
                          title: Text(recurrenceLabel(r)),
                        ),
                    ],
                  ),
                ),
                if (sheetRecurrence != null)
                  ListTile(
                    leading: const Icon(Icons.event_busy_outlined),
                    title: const Text('Ends'),
                    subtitle: Text(
                      sheetEndDate == null
                          ? 'Never — until you switch it off'
                          : relativeDayLabel(sheetEndDate!),
                    ),
                    trailing: sheetEndDate == null
                        ? null
                        : IconButton(
                            tooltip: 'Clear end date',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              setSheetState(() => sheetEndDate = null);
                              onEndDateChanged(null);
                            },
                          ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: sheetContext,
                        initialDate:
                            sheetEndDate ??
                            DateTime.now().add(const Duration(days: 365)),
                        firstDate: anchorDate,
                        lastDate: DateTime(DateTime.now().year + 20),
                      );
                      if (picked == null) return;
                      setSheetState(() => sheetEndDate = picked);
                      onEndDateChanged(picked);
                    },
                  ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          );
        },
      );
    },
  );
}
