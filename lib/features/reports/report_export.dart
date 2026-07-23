import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';
import 'report_model.dart';

// ---- CSV (FR-21, FR-32) — pure, unit-tested ----

/// The in-range transactions as RFC-4180 CSV. FR-32 export.
String buildCsv(List<ExpenseRow> expenses, Map<int, CategoryRow> byId) {
  final df = DateFormat('yyyy-MM-dd');
  final rows = <String>['Date,Category,Note,Amount,Payment method'];
  for (final e in expenses) {
    rows.add(
      [
        df.format(e.date),
        byId[e.categoryId]?.name ?? '',
        e.note ?? '',
        _decimal(e.amountMinor),
        e.paymentMethod ?? '',
      ].map(_csvField).join(','),
    );
  }
  return rows.join('\r\n');
}

/// Exact major-unit string from minor units — no float.
String _decimal(int minor) {
  final sign = minor < 0 ? '-' : '';
  final a = minor.abs();
  return '$sign${a ~/ 100}.${(a % 100).toString().padLeft(2, '0')}';
}

/// Quote a field iff it contains a comma, quote, CR or LF; embedded quotes doubled.
String _csvField(String v) {
  if (v.contains(RegExp(r'[",\r\n]'))) return '"${v.replaceAll('"', '""')}"';
  return v;
}

// ---- PDF (FR-21) ----

/// Render the report as a one-page PDF. Uses the bundled Inter/Sora fonts
/// (already app assets) so the ₹ glyph renders — pdf's built-in Helvetica lacks it.
Future<Uint8List> buildPdf(
  ReportData data,
  Map<int, CategoryRow> byId, {
  required String title,
}) async {
  final base = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Sora.ttf'));
  final doc = pw.Document();
  const indigo = PdfColor.fromInt(0xFF6366F1);
  final dim = PdfColors.grey600;
  String money(Money m) => m.format(locale: 'en_IN');

  pw.Widget statBox(String label, String value) => pw.Expanded(
    child: pw.Container(
      margin: const pw.EdgeInsets.only(right: 8),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 9, color: dim)),
          pw.SizedBox(height: 3),
          pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 13)),
        ],
      ),
    ),
  );

  final compare = data.changePct == null
      ? 'No prior-period spend to compare'
      : '${data.changeUp ? '↑' : '↓'} ${data.changePct!.abs().toStringAsFixed(0)}% '
            'vs previous period (${money(data.previousTotal)})';

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: base, bold: bold),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(font: bold, fontSize: 22)),
          pw.SizedBox(height: 2),
          pw.Text('Total spent', style: pw.TextStyle(fontSize: 10, color: dim)),
          pw.Text(
            money(data.total),
            style: pw.TextStyle(font: bold, fontSize: 30, color: indigo),
          ),
          pw.Text(compare, style: pw.TextStyle(fontSize: 10, color: dim)),
          pw.SizedBox(height: 16),
          pw.Row(
            children: [
              statBox('Daily average', money(data.dailyAverage)),
              statBox('Transactions', '${data.txnCount}'),
              statBox('Top category', data.topCategory?.$1.name ?? '—'),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text('By category', style: pw.TextStyle(font: bold, fontSize: 14)),
          pw.SizedBox(height: 6),
          if (data.breakdown.isEmpty)
            pw.Text(
              'No spending in this period',
              style: pw.TextStyle(color: dim),
            )
          else
            pw.Table(
              columnWidths: const {
                0: pw.FlexColumnWidth(4),
                1: pw.FlexColumnWidth(2),
                2: pw.FlexColumnWidth(1),
              },
              children: [
                for (final s in data.breakdown)
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 3),
                        child: pw.Text(s.$1.name),
                      ),
                      pw.Text(money(s.$2), textAlign: pw.TextAlign.right),
                      pw.Text(
                        '${(s.$3 * 100).round()}%',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(color: dim),
                      ),
                    ],
                  ),
              ],
            ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Top ${data.top5.length} expenses',
            style: pw.TextStyle(font: bold, fontSize: 14),
          ),
          pw.SizedBox(height: 6),
          for (var i = 0; i < data.top5.length; i++)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(
                children: [
                  pw.SizedBox(width: 18, child: pw.Text('${i + 1}.')),
                  pw.Expanded(
                    child: pw.Text(
                      data.top5[i].note?.isNotEmpty == true
                          ? data.top5[i].note!
                          : (byId[data.top5[i].categoryId]?.name ?? 'Expense'),
                    ),
                  ),
                  pw.Text(money(data.top5[i].amount)),
                ],
              ),
            ),
          pw.Spacer(),
          pw.Text(
            'Generated by Spendly',
            style: pw.TextStyle(fontSize: 9, color: dim),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

// ---- Share (FR-22) — one path serves PDF, CSV and email (email = a share target) ----

/// Write [bytes] to a temp file and hand it to the OS share sheet (which lists
/// Mail, Files, cloud drives, etc.).
Future<void> shareReportFile({
  required List<int> bytes,
  required String filename,
  String? text,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], text: text),
  );
}
