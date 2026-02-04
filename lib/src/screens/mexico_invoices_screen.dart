import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../utils/app_colors.dart';
import '../config/supabase_config.dart';

class MexicoInvoicesScreen extends StatefulWidget {
  const MexicoInvoicesScreen({super.key});

  @override
  State<MexicoInvoicesScreen> createState() => _MexicoInvoicesScreenState();
}

class _MexicoInvoicesScreenState extends State<MexicoInvoicesScreen> {
  bool _isLoading = true;
  String? _driverId;
  List<CfdiInvoice> _invoices = [];
  int _selectedYear = DateTime.now().year;
  int? _selectedMonth;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Get driver info
      final driverResponse = await SupabaseConfig.client
          .from('drivers')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (driverResponse != null) {
        _driverId = driverResponse['id'];

        // Get invoices
        var query = SupabaseConfig.client
            .from('cfdi_invoices')
            .select()
            .eq('driver_id', _driverId!);

        final response = await query.order('created_at', ascending: false);

        _invoices = (response as List).map((data) => CfdiInvoice.fromJson(data)).toList();

        // Filter by year and month
        _invoices = _invoices.where((inv) {
          final invoiceDate = inv.createdAt;
          if (invoiceDate.year != _selectedYear) return false;
          if (_selectedMonth != null && invoiceDate.month != _selectedMonth) return false;
          return true;
        }).toList();
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Icon(Icons.receipt_long, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('mx_invoices_title'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          // Year selector
          PopupMenuButton<int>(
            initialValue: _selectedYear,
            onSelected: (year) {
              setState(() => _selectedYear = year);
              _loadData();
            },
            itemBuilder: (context) => [
              for (int year = DateTime.now().year; year >= 2024; year--)
                PopupMenuItem(value: year, child: Text('$year')),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$_selectedYear', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const Icon(Icons.arrow_drop_down, size: 16),
                ],
              ),
            ),
          ),
          // Month selector
          PopupMenuButton<int?>(
            initialValue: _selectedMonth,
            onSelected: (month) {
              setState(() => _selectedMonth = month);
              _loadData();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: null, child: Text('Todos')),
              for (int month = 1; month <= 12; month++)
                PopupMenuItem(
                  value: month,
                  child: Text(_getMonthName(month)),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _selectedMonth != null ? _getMonthName(_selectedMonth!).substring(0, 3) : 'Mes',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: _invoices.isEmpty
                  ? _buildEmptyState()
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Summary Card
                        _buildSummaryCard(),
                        const SizedBox(height: 16),

                        // Info Card
                        _buildInfoCard(),
                        const SizedBox(height: 16),

                        // Invoices List
                        Text(
                          'mx_invoices_list'.tr(),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),

                        ..._invoices.map((invoice) => _buildInvoiceCard(invoice)),

                        const SizedBox(height: 80),
                      ],
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showRequestInvoiceDialog,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.black),
        label: Text('mx_request_invoice'.tr(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'mx_no_invoices'.tr(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'mx_no_invoices_description'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showRequestInvoiceDialog,
              icon: const Icon(Icons.add),
              label: Text('mx_request_first_invoice'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final total = _invoices.fold<double>(0, (sum, inv) => sum + inv.total);
    final subtotal = _invoices.fold<double>(0, (sum, inv) => sum + inv.subtotal);
    final iva = _invoices.fold<double>(0, (sum, inv) => sum + inv.iva);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withValues(alpha: 0.2), AppColors.primary.withValues(alpha: 0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.summarize, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'mx_invoices_summary'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem('mx_invoices_count'.tr(), '${_invoices.length}'),
              ),
              Expanded(
                child: _buildSummaryItem('Subtotal', '\$${subtotal.toStringAsFixed(2)}'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem('IVA', '\$${iva.toStringAsFixed(2)}'),
              ),
              Expanded(
                child: _buildSummaryItem('Total', '\$${total.toStringAsFixed(2)}', highlight: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, {bool highlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: highlight ? 18 : 14,
            fontWeight: FontWeight.bold,
            color: highlight ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: AppColors.info, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'mx_cfdi_info'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  'mx_cfdi_description'.tr(),
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceCard(CfdiInvoice invoice) {
    Color statusColor;
    IconData statusIcon;

    switch (invoice.status) {
      case 'issued':
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle;
        break;
      case 'cancelled':
        statusColor = AppColors.error;
        statusIcon = Icons.cancel;
        break;
      case 'pending':
      default:
        statusColor = AppColors.warning;
        statusIcon = Icons.hourglass_empty;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(statusIcon, color: statusColor, size: 20),
        ),
        title: Text(
          invoice.folio ?? 'Sin folio',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          DateFormat('dd/MM/yyyy').format(invoice.createdAt),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '\$${invoice.total.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            Text(
              'MXN',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('UUID', invoice.uuid ?? 'N/A'),
                _buildDetailRow('RFC ${'mx_receiver'.tr()}', invoice.rfcReceptor),
                _buildDetailRow('mx_use'.tr(), invoice.usoCfdi),
                _buildDetailRow('Subtotal', '\$${invoice.subtotal.toStringAsFixed(2)}'),
                _buildDetailRow('IVA (16%)', '\$${invoice.iva.toStringAsFixed(2)}'),
                _buildDetailRow('Total', '\$${invoice.total.toStringAsFixed(2)}', bold: true),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (invoice.xmlUrl != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _downloadFile(invoice.xmlUrl!, 'XML'),
                          icon: const Icon(Icons.code, size: 16),
                          label: const Text('XML'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: BorderSide(color: AppColors.primary),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    if (invoice.xmlUrl != null && invoice.pdfUrl != null)
                      const SizedBox(width: 8),
                    if (invoice.pdfUrl != null)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _downloadFile(invoice.pdfUrl!, 'PDF'),
                          icon: const Icon(Icons.picture_as_pdf, size: 16),
                          label: const Text('PDF'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showRequestInvoiceDialog() {
    final rfcController = TextEditingController();
    final nameController = TextEditingController();
    String selectedUso = 'G03';
    String selectedRegimen = '612';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'mx_request_invoice'.tr(),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 20),

                // RFC
                Text('RFC', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: rfcController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 13,
                  decoration: InputDecoration(
                    hintText: 'AAAA000000XXX',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: AppColors.card,
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 16),

                // Name
                Text('mx_business_name'.tr(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'mx_name_hint'.tr(),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: AppColors.card,
                  ),
                ),
                const SizedBox(height: 16),

                // Uso CFDI
                Text('mx_cfdi_use'.tr(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedUso,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: AppColors.card,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'G01', child: Text('G01 - Adquisición de mercancías')),
                    DropdownMenuItem(value: 'G03', child: Text('G03 - Gastos en general')),
                    DropdownMenuItem(value: 'P01', child: Text('P01 - Por definir')),
                  ],
                  onChanged: (value) => setSheetState(() => selectedUso = value!),
                ),
                const SizedBox(height: 16),

                // Régimen fiscal
                Text('mx_fiscal_regime'.tr(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedRegimen,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: AppColors.card,
                  ),
                  items: const [
                    DropdownMenuItem(value: '601', child: Text('601 - General de Ley PM')),
                    DropdownMenuItem(value: '603', child: Text('603 - Personas Morales sin fines de lucro')),
                    DropdownMenuItem(value: '612', child: Text('612 - Personas Físicas con actividades empresariales')),
                    DropdownMenuItem(value: '621', child: Text('621 - Incorporación Fiscal')),
                    DropdownMenuItem(value: '625', child: Text('625 - Régimen de las actividades empresariales con ingresos a través de plataformas')),
                  ],
                  onChanged: (value) => setSheetState(() => selectedRegimen = value!),
                ),
                const SizedBox(height: 24),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _requestInvoice(
                      rfcController.text.trim().toUpperCase(),
                      nameController.text.trim(),
                      selectedUso,
                      selectedRegimen,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('mx_generate_invoice'.tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _requestInvoice(String rfc, String name, String uso, String regimen) async {
    if (rfc.length < 12 || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('mx_fill_all_fields'.tr()), backgroundColor: AppColors.error),
      );
      return;
    }

    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            const SizedBox(width: 12),
            Text('mx_generating_invoice'.tr()),
          ],
        ),
        duration: const Duration(seconds: 30),
      ),
    );

    try {
      final response = await SupabaseConfig.client.functions.invoke(
        'generate-cfdi',
        body: {
          'driver_id': _driverId,
          'rfc_receptor': rfc,
          'nombre_receptor': name,
          'uso_cfdi': uso,
          'regimen_fiscal': regimen,
        },
      );

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (response.status == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('mx_invoice_generated'.tr()), backgroundColor: AppColors.success),
        );
        _loadData();
      } else {
        throw Exception(response.data['error'] ?? 'Error desconocido');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  void _downloadFile(String url, String type) {
    // TODO: Implement file download
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('mx_downloading'.tr(namedArgs: {'type': type}))),
    );
  }

  String _getMonthName(int month) {
    const months = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
    ];
    return months[month - 1];
  }
}

class CfdiInvoice {
  final String id;
  final String? uuid;
  final String? folio;
  final String rfcReceptor;
  final String? nombreReceptor;
  final String usoCfdi;
  final double subtotal;
  final double iva;
  final double total;
  final String status;
  final String? xmlUrl;
  final String? pdfUrl;
  final DateTime createdAt;

  CfdiInvoice({
    required this.id,
    this.uuid,
    this.folio,
    required this.rfcReceptor,
    this.nombreReceptor,
    required this.usoCfdi,
    required this.subtotal,
    required this.iva,
    required this.total,
    required this.status,
    this.xmlUrl,
    this.pdfUrl,
    required this.createdAt,
  });

  factory CfdiInvoice.fromJson(Map<String, dynamic> json) {
    return CfdiInvoice(
      id: json['id'],
      uuid: json['uuid'],
      folio: json['folio'],
      rfcReceptor: json['rfc_receptor'] ?? '',
      nombreReceptor: json['nombre_receptor'],
      usoCfdi: json['uso_cfdi'] ?? 'G03',
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      iva: (json['iva'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      status: json['status'] ?? 'pending',
      xmlUrl: json['xml_url'],
      pdfUrl: json['pdf_url'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
