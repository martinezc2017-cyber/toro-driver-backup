import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

/// Service to generate Uber-style Weekly Statements for drivers
class StatementExportService {
  static final StatementExportService _instance = StatementExportService._internal();
  static StatementExportService get instance => _instance;
  StatementExportService._internal();

  /// Generate and download/share Weekly Statement PDF
  Future<void> generateWeeklyStatement({
    required Map<String, dynamic> driver,
    required DateTime weekStart,
    required DateTime weekEnd,
    required Map<String, dynamic> summary,
    required List<Map<String, dynamic>> transactions,
  }) async {
    final pdf = pw.Document();
    final periodFormat = DateFormat('MMM d, yyyy h a');

    final driverName = driver['name']?.toString().toUpperCase() ?? 'DRIVER';
    final driverPhone = driver['phone'] ?? '';
    final driverEmail = driver['email'] ?? '';

    // Extract summary data
    final startingBalance = (summary['starting_balance'] as num?)?.toDouble() ?? 0;
    final totalEarnings = (summary['total_earnings'] as num?)?.toDouble() ?? 0;
    final tips = (summary['tips'] as num?)?.toDouble() ?? 0;
    final payouts = (summary['payouts'] as num?)?.toDouble() ?? 0;
    final endingBalance = (summary['ending_balance'] as num?)?.toDouble() ?? 0;
    final previousWeekEvents = (summary['previous_week_events'] as num?)?.toDouble() ?? 0;

    // Page 1: Weekly Summary
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _buildLogo(),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Weekly Statement',
                      style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                    ),
                    pw.Text(
                      '${periodFormat.format(weekStart)} - ${periodFormat.format(weekEnd)}',
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 30),

            // Driver info
            pw.Row(
              children: [
                pw.Container(
                  width: 50,
                  height: 50,
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey300,
                    borderRadius: pw.BorderRadius.circular(25),
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      driverName.isNotEmpty ? driverName[0] : 'D',
                      style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ),
                pw.SizedBox(width: 15),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      driverName,
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      '$driverPhone     $driverEmail',
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 40),

            // Weekly Summary section
            pw.Text(
              'Weekly Summary',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 5),
              height: 2,
              width: 120,
              color: PdfColor.fromHex('#D4AF37'),
            ),
            pw.SizedBox(height: 20),

            // Starting balance
            _buildSummaryRow(
              'Starting balance at ${_formatDateTime(weekStart)}',
              startingBalance,
            ),
            pw.SizedBox(height: 15),

            // Events from previous weeks (if any)
            if (previousWeekEvents > 0) ...[
              _buildSummaryRow(
                'Events from previous weeks',
                previousWeekEvents,
                subtitle: "For details, see the 'Previous weeks' sections",
              ),
              pw.SizedBox(height: 20),
            ],

            // Payouts section
            pw.Container(
              padding: const pw.EdgeInsets.all(15),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildSummaryRow('Payouts', payouts, bold: true),
                  pw.SizedBox(height: 5),
                  pw.Text(
                    'This amount was withdrawn from your balance',
                    style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 20),
                    child: _buildSummaryRow(
                      'Transferred to your bank account on ${_formatDateTime(weekStart)}',
                      payouts,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Ending balance
            pw.Container(
              padding: const pw.EdgeInsets.all(15),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: _buildSummaryRow(
                'Ending balance at ${_formatDateTime(weekEnd)}',
                endingBalance,
                bold: true,
              ),
            ),

            pw.Spacer(),

            // Footer
            _buildFooter(driverName, 1, 3),
          ],
        ),
      ),
    );

    // Page 2: Breakdown
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header
            _buildPageHeader(periodFormat, weekStart, weekEnd),
            pw.SizedBox(height: 40),

            // Breakdown section
            pw.Text(
              'Breakdown of Your earnings',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 5),
              height: 2,
              width: 180,
              color: PdfColor.fromHex('#D4AF37'),
            ),
            pw.SizedBox(height: 20),

            // Earnings breakdown
            _buildBreakdownRow('Trip earnings', summary['trip_earnings']),
            _buildBreakdownRow('Tips', tips),
            _buildBreakdownRow('Quest bonuses', summary['quest_bonuses']),
            _buildBreakdownRow('Streak bonuses', summary['streak_bonuses']),
            _buildBreakdownRow('Referral bonuses', summary['referral_bonuses']),
            _buildBreakdownRow('Promotions', summary['promotion_bonuses']),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 10),

            // Total
            pw.Container(
              padding: const pw.EdgeInsets.all(15),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: _buildSummaryRow('Your earnings', totalEarnings, bold: true),
            ),

            pw.Spacer(),

            // Footer
            _buildFooter(driverName, 2, 3),
          ],
        ),
      ),
    );

    // Page 3: Transactions
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header
            _buildPageHeader(periodFormat, weekStart, weekEnd),
            pw.SizedBox(height: 40),

            // Transactions section
            pw.Text(
              'Transactions',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 5),
              height: 2,
              width: 100,
              color: PdfColor.fromHex('#D4AF37'),
            ),
            pw.SizedBox(height: 20),

            // Table header
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 5),
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300)),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text('Processed', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                  ),
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text('Event', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text('Your earnings', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600), textAlign: pw.TextAlign.right),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text('Payouts', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600), textAlign: pw.TextAlign.right),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text('Balance', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600), textAlign: pw.TextAlign.right),
                  ),
                ],
              ),
            ),

            // Transaction rows
            ...transactions.take(15).map((tx) => _buildTransactionRow(tx)),

            pw.Spacer(),

            // Footer
            _buildFooter(driverName, 3, 3),
          ],
        ),
      ),
    );

    // Save/Share PDF
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'toro_statement_${DateFormat('MMM_d_yyyy').format(weekStart)}.pdf',
    );
  }

  // Build TORO logo
  pw.Widget _buildLogo() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'TORO',
          style: pw.TextStyle(
            fontSize: 32,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('#D4AF37'),
          ),
        ),
        pw.Text(
          'RIDESHARE',
          style: pw.TextStyle(
            fontSize: 10,
            letterSpacing: 3,
            color: PdfColors.grey600,
          ),
        ),
      ],
    );
  }

  // Build page header (for pages 2+)
  pw.Widget _buildPageHeader(DateFormat periodFormat, DateTime weekStart, DateTime weekEnd) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        _buildLogo(),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'Weekly Statement',
              style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
            ),
            pw.Text(
              '${periodFormat.format(weekStart)} - ${periodFormat.format(weekEnd)}',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            ),
          ],
        ),
      ],
    );
  }

  // Build summary row
  pw.Widget _buildSummaryRow(
    String label,
    double amount, {
    String? subtitle,
    bool bold = false,
    double fontSize = 12,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: fontSize,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
              if (subtitle != null)
                pw.Text(
                  subtitle,
                  style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                ),
            ],
          ),
        ),
        pw.Text(
          '\$${amount.toStringAsFixed(2)}',
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    );
  }

  // Build breakdown row
  pw.Widget _buildBreakdownRow(String label, dynamic value) {
    final amount = (value as num?)?.toDouble() ?? 0;
    if (amount == 0) return pw.SizedBox.shrink();

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 12)),
          pw.Text('\$${amount.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  // Build transaction row
  pw.Widget _buildTransactionRow(Map<String, dynamic> tx) {
    final processedAt = DateTime.tryParse(tx['processed_at'] ?? tx['earned_at'] ?? '');
    final eventDate = DateTime.tryParse(tx['event_date'] ?? tx['earned_at'] ?? '');
    final type = tx['type'] ?? 'Trip';
    final earnings = (tx['earnings'] as num?)?.toDouble() ?? (tx['total_earnings'] as num?)?.toDouble() ?? 0;
    final payout = (tx['payout'] as num?)?.toDouble() ?? 0;
    final balance = (tx['balance'] as num?)?.toDouble() ?? 0;

    final dateFormat = DateFormat('MMM d');
    final timeFormat = DateFormat('h:mm a');

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200)),
      ),
      child: pw.Row(
        children: [
          // Processed date
          pw.Expanded(
            flex: 2,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (processedAt != null) ...[
                  pw.Text(dateFormat.format(processedAt), style: const pw.TextStyle(fontSize: 10)),
                  pw.Text(timeFormat.format(processedAt), style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                ],
              ],
            ),
          ),
          // Event
          pw.Expanded(
            flex: 3,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(_capitalizeType(type), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                if (eventDate != null)
                  pw.Text(
                    '${dateFormat.format(eventDate)} ${timeFormat.format(eventDate)}',
                    style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                  ),
              ],
            ),
          ),
          // Earnings
          pw.Expanded(
            flex: 2,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                if (earnings > 0) pw.Text('\$${earnings.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 10)),
                if (earnings > 0) pw.Text('\$${earnings.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              ],
            ),
          ),
          // Payouts
          pw.Expanded(
            flex: 2,
            child: payout != 0
                ? pw.Text(
                    payout < 0 ? '-\$${payout.abs().toStringAsFixed(2)}' : '\$${payout.toStringAsFixed(2)}',
                    style: const pw.TextStyle(fontSize: 10),
                    textAlign: pw.TextAlign.right,
                  )
                : pw.SizedBox.shrink(),
          ),
          // Balance
          pw.Expanded(
            flex: 2,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  earnings > 0 ? '\$${earnings.toStringAsFixed(2)}' : (payout < 0 ? '-\$${payout.abs().toStringAsFixed(2)}' : ''),
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text('\$${balance.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Build footer
  pw.Widget _buildFooter(String driverName, int currentPage, int totalPages) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 20),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(driverName, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
          pw.Text('$currentPage of $totalPages', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        ],
      ),
    );
  }

  // Format datetime
  String _formatDateTime(DateTime dt) {
    final format = DateFormat('EEE, MMM d, h:mm a');
    return format.format(dt);
  }

  // Capitalize type
  String _capitalizeType(String type) {
    switch (type.toLowerCase()) {
      case 'ride':
        return 'Trip';
      case 'tip':
        return 'Tip';
      case 'bonus':
      case 'quest':
        return 'Quest Bonus';
      case 'streak':
        return 'Streak Bonus';
      case 'referral':
        return 'Referral Bonus';
      case 'payout':
      case 'transfer':
        return 'Transferred To Bank Account';
      default:
        return type[0].toUpperCase() + type.substring(1);
    }
  }
}
