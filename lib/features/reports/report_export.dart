import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';
import '../profile/profile_provider.dart';
import 'report_model.dart';

// ---- Excel (FR-21, FR-32) — Summary + Transactions sheets ----
//
// The `excel` package has no native chart/image support (confirmed against
// its roadmap), so "graphical" here means real, checkable cell content: a
// category's share rendered as a row of colored cells (a segmented bar),
// not a picture. Layout mirrors the approved "dashboard header" mockup —
// a colored total banner, a totals row, then the category breakdown.

const _accentHex = 'FF6366F1';
const _accentSoftHex = 'FFEEEEFD';
const _trackHex = 'FFE5E5EA';
const _dimHex = 'FF6B6875';
const _goodHex = 'FF10B981';
const _barSegments = 10;
const _colCategory = 0;
const _colAmount = 1;
const _colBarStart = 2;
const _colShare = _colBarStart + _barSegments; // 12
const _sheetCols = _colShare + 1; // A..M

xl.ExcelColor _xlColor(String argbHex) => xl.ExcelColor.fromHexString(argbHex);

/// A category's stored ARGB [Color] value, forced fully opaque for Excel.
xl.ExcelColor _categoryColor(int colorValue) {
  final rgb = (colorValue & 0x00FFFFFF).toRadixString(16).padLeft(6, '0');
  return _xlColor('FF${rgb.toUpperCase()}');
}

xl.CellStyle _moneyStyle() => xl.CellStyle(
  numberFormat: xl.NumFormat.custom(formatCode: '"₹"#,##0'),
  horizontalAlign: xl.HorizontalAlign.Right,
);

/// One segmented "bar": [filled] of [_barSegments] cells tinted [color],
/// the rest left as a neutral track. FR-32's graphical category read.
void _writeBar(xl.Sheet sheet, int row, double fraction, xl.ExcelColor color) {
  final filled = (fraction * _barSegments).round().clamp(0, _barSegments);
  for (var i = 0; i < _barSegments; i++) {
    sheet
        .cell(
          xl.CellIndex.indexByColumnRow(
            columnIndex: _colBarStart + i,
            rowIndex: row,
          ),
        )
        .cellStyle = xl.CellStyle(
      backgroundColorHex: i < filled ? color : _xlColor(_trackHex),
    );
  }
}

void _setCell(
  xl.Sheet sheet,
  int col,
  int row,
  xl.CellValue value, {
  xl.CellStyle? style,
}) {
  final cell = sheet.cell(
    xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
  );
  cell.value = value;
  if (style != null) cell.cellStyle = style;
}

/// One row of a category breakdown table: name, amount, segmented bar, share %.
void _writeCategoryRow(
  xl.Sheet sheet,
  int row,
  (CategoryRow category, Money amount, double fraction) slice,
) {
  sheet.setRowHeight(row, 18);
  _setCell(
    sheet,
    _colCategory,
    row,
    xl.TextCellValue(slice.$1.name),
    style: xl.CellStyle(verticalAlign: xl.VerticalAlign.Center),
  );
  _setCell(
    sheet,
    _colAmount,
    row,
    xl.DoubleCellValue(slice.$2.minor / 100),
    style: _moneyStyle(),
  );
  _writeBar(sheet, row, slice.$3, _categoryColor(slice.$1.colorValue));
  _setCell(
    sheet,
    _colShare,
    row,
    xl.TextCellValue('${(slice.$3 * 100).round()}%'),
    style: xl.CellStyle(
      fontColorHex: _xlColor(_dimHex),
      horizontalAlign: xl.HorizontalAlign.Right,
    ),
  );
}

/// A section band (e.g. "By category") spanning the full sheet width.
void _writeSectionHeader(xl.Sheet sheet, int row, String title) {
  _mergeRow(
    sheet,
    0,
    row,
    _sheetCols,
    xl.TextCellValue(title),
    xl.CellStyle(bold: true, backgroundColorHex: _xlColor(_trackHex)),
  );
}

/// The "Category | Amount | Share" column-header row above a breakdown table.
void _writeColumnHeaders(xl.Sheet sheet, int row) {
  sheet.setRowHeight(row, 18);
  final dim = xl.CellStyle(fontColorHex: _xlColor(_dimHex));
  _setCell(sheet, _colCategory, row, xl.TextCellValue('Category'), style: dim);
  _setCell(sheet, _colAmount, row, xl.TextCellValue('Amount'), style: dim);
  _mergeRow(
    sheet,
    _colBarStart,
    row,
    _sheetCols - _colBarStart,
    xl.TextCellValue('Share'),
    dim,
  );
}

/// Merge [col, row] .. [col + colSpan - 1, row], value/style on the anchor.
void _mergeRow(
  xl.Sheet sheet,
  int col,
  int row,
  int colSpan,
  xl.CellValue value,
  xl.CellStyle style,
) {
  _setCell(sheet, col, row, value, style: style);
  sheet.merge(
    xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    xl.CellIndex.indexByColumnRow(
      columnIndex: col + colSpan - 1,
      rowIndex: row,
    ),
  );
}

/// Full report as an .xlsx: a Summary sheet (dashboard-header total, then
/// category breakdown as segmented bars) and a Transactions sheet (today's
/// CSV columns, typed). FR-21/FR-32 export.
Uint8List buildXlsx(
  ReportData data,
  Map<int, CategoryRow> byId, {
  required String title,
  Profile? profile,
}) {
  final excel = xl.Excel.createExcel();
  final summary = excel['Summary'];
  final txns = excel['Transactions'];
  for (final name in excel.sheets.keys.toList()) {
    if (name != 'Summary' && name != 'Transactions') excel.delete(name);
  }
  excel.setDefaultSheet('Summary');
  String money(Money m) => '₹${m.minor ~/ 100}';

  summary.setColumnWidth(_colCategory, 22);
  summary.setColumnWidth(_colAmount, 14);
  for (var c = _colBarStart; c < _colShare; c++) {
    summary.setColumnWidth(c, 2.8);
  }
  summary.setColumnWidth(_colShare, 9);

  var row = 0;
  summary.setRowHeight(row, 28);
  _mergeRow(
    summary,
    0,
    row,
    _sheetCols,
    xl.TextCellValue('Spend Summary — $title'),
    xl.CellStyle(
      bold: true,
      fontSize: 16,
      fontColorHex: _xlColor(_accentHex),
      backgroundColorHex: _xlColor(_accentSoftHex),
      verticalAlign: xl.VerticalAlign.Center,
    ),
  );
  row++;
  summary.setRowHeight(row, 6);
  row++;

  final compare = data.changePct == null
      ? 'No prior-period spend to compare'
      : '${data.changeUp ? '↑' : '↓'} ${data.changePct!.abs().toStringAsFixed(0)}% vs previous period (${money(data.previousTotal)})';
  summary.setRowHeight(row, 24);
  _setCell(
    summary,
    _colCategory,
    row,
    xl.TextCellValue('Total spent'),
    style: xl.CellStyle(
      fontColorHex: _xlColor(_dimHex),
      verticalAlign: xl.VerticalAlign.Center,
    ),
  );
  _mergeRow(
    summary,
    _colAmount,
    row,
    4,
    xl.TextCellValue(money(data.total)),
    xl.CellStyle(
      bold: true,
      fontSize: 16,
      fontColorHex: _xlColor(_accentHex),
      verticalAlign: xl.VerticalAlign.Center,
    ),
  );
  _mergeRow(
    summary,
    5,
    row,
    _sheetCols - 5,
    xl.TextCellValue(compare),
    xl.CellStyle(
      fontColorHex: _xlColor(data.changeUp ? _goodHex : _dimHex),
      horizontalAlign: xl.HorizontalAlign.Right,
      verticalAlign: xl.VerticalAlign.Center,
    ),
  );
  row++;

  summary.setRowHeight(row, 20);
  _setCell(
    summary,
    _colCategory,
    row,
    xl.TextCellValue('Transactions'),
    style: xl.CellStyle(
      fontColorHex: _xlColor(_dimHex),
      verticalAlign: xl.VerticalAlign.Center,
    ),
  );
  _setCell(
    summary,
    _colAmount,
    row,
    xl.TextCellValue('${data.txnCount}'),
    style: xl.CellStyle(
      bold: true,
      verticalAlign: xl.VerticalAlign.Center,
    ),
  );
  _mergeRow(
    summary,
    3,
    row,
    2,
    xl.TextCellValue('Daily average'),
    xl.CellStyle(
      fontColorHex: _xlColor(_dimHex),
      verticalAlign: xl.VerticalAlign.Center,
    ),
  );
  _mergeRow(
    summary,
    5,
    row,
    2,
    xl.TextCellValue(money(data.dailyAverage)),
    xl.CellStyle(bold: true, verticalAlign: xl.VerticalAlign.Center),
  );
  row += 2;
  summary.setRowHeight(row - 1, 10);

  _writeSectionHeader(summary, row, 'By category');
  row++;
  _writeColumnHeaders(summary, row);
  row++;
  for (final slice in data.breakdown) {
    _writeCategoryRow(summary, row, slice);
    row++;
  }
  row++;

  if (data.ignoredBreakdown.isNotEmpty) {
    _writeSectionHeader(
      summary,
      row,
      'Excluded from budget — ${money(data.ignoredTotal)}',
    );
    row++;
    _writeColumnHeaders(summary, row);
    row++;
    for (final slice in data.ignoredBreakdown) {
      _writeCategoryRow(summary, row, slice);
      row++;
    }
    row++;
  }

  final footer = [
    'Generated by Spendly',
    if (profile != null && !profile.isEmpty)
      [
        profile.name,
        profile.email,
        profile.phone,
      ].where((s) => s.isNotEmpty).join(' · '),
  ].join(' · ');
  _mergeRow(
    summary,
    0,
    row,
    _sheetCols,
    xl.TextCellValue(footer),
    xl.CellStyle(fontColorHex: _xlColor(_dimHex), fontSize: 9),
  );

  // ---- Transactions sheet — today's CSV columns, typed ----
  txns.setColumnWidth(0, 12);
  txns.setColumnWidth(1, 16);
  txns.setColumnWidth(2, 28);
  txns.setColumnWidth(3, 12);
  txns.setColumnWidth(4, 16);
  txns.appendRow([
    xl.TextCellValue('Date'),
    xl.TextCellValue('Category'),
    xl.TextCellValue('Note'),
    xl.TextCellValue('Amount'),
    xl.TextCellValue('Payment method'),
  ]);
  for (final e in data.expenses) {
    txns.appendRow([
      xl.DateCellValue(
        year: e.date.year,
        month: e.date.month,
        day: e.date.day,
      ),
      xl.TextCellValue(byId[e.categoryId]?.name ?? ''),
      xl.TextCellValue(e.note ?? ''),
      xl.DoubleCellValue(e.amountMinor / 100),
      xl.TextCellValue(e.paymentMethod ?? ''),
    ]);
  }

  return Uint8List.fromList(excel.save()!);
}

// ---- PDF (FR-21) ----

/// Render the report as a one-page PDF. Uses the bundled Inter/Sora fonts
/// (already app assets) so the ₹ glyph renders — pdf's built-in Helvetica lacks it.
Future<Uint8List> buildPdf(
  ReportData data,
  Map<int, CategoryRow> byId, {
  required String title,
  Profile? profile,
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
          if (profile != null && !profile.isEmpty)
            pw.Text(
              [
                profile.name,
                profile.email,
                profile.phone,
              ].where((s) => s.isNotEmpty).join(' · '),
              style: pw.TextStyle(fontSize: 9, color: dim),
            ),
        ],
      ),
    ),
  );
  return doc.save();
}

// ---- Share (FR-22) — one path serves PDF, Excel and email (email = a share target) ----

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
