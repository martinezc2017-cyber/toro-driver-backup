import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Service for handling Mexican CFDI (electronic invoices)
class MexicoCfdiService {
  final SupabaseClient _client = SupabaseConfig.client;

  /// Request a CFDI invoice
  Future<CfdiInvoiceResult> requestInvoice({
    required String driverId,
    required String rfcReceptor,
    required String nombreReceptor,
    String usoCfdi = 'G03',
    String regimenFiscal = '612',
    String? codigoPostal,
    List<String>? rideIds,
    int? year,
    int? month,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'generate-cfdi',
        body: {
          'driver_id': driverId,
          'rfc_receptor': rfcReceptor.toUpperCase(),
          'nombre_receptor': nombreReceptor,
          'uso_cfdi': usoCfdi,
          'regimen_fiscal': regimenFiscal,
          'codigo_postal': codigoPostal,
          'ride_ids': rideIds,
          'year': year,
          'month': month,
        },
      );

      if (response.status != 200) {
        final error = response.data['error'] ?? 'Error generando CFDI';
        throw Exception(error);
      }

      final data = response.data['data'];
      return CfdiInvoiceResult(
        success: true,
        invoiceId: data['invoice_id'],
        uuid: data['uuid'],
        folio: data['folio'],
        xmlUrl: data['xml_url'],
        pdfUrl: data['pdf_url'],
      );
    } catch (e) {
      return CfdiInvoiceResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Get all invoices for a driver
  Future<List<CfdiInvoice>> getInvoices({
    required String driverId,
    int? year,
    int? month,
  }) async {
    try {
      var query = _client
          .from('cfdi_invoices')
          .select()
          .eq('driver_id', driverId);

      final response = await query.order('created_at', ascending: false);

      List<CfdiInvoice> invoices = (response as List)
          .map((data) => CfdiInvoice.fromJson(data))
          .toList();

      // Filter by year/month if provided
      if (year != null) {
        invoices = invoices.where((inv) {
          if (inv.createdAt.year != year) return false;
          if (month != null && inv.createdAt.month != month) return false;
          return true;
        }).toList();
      }

      return invoices;
    } catch (e) {
      rethrow;
    }
  }

  /// Get invoice by ID
  Future<CfdiInvoice?> getInvoice(String invoiceId) async {
    try {
      final response = await _client
          .from('cfdi_invoices')
          .select()
          .eq('id', invoiceId)
          .maybeSingle();

      if (response == null) return null;
      return CfdiInvoice.fromJson(response);
    } catch (e) {
      rethrow;
    }
  }

  /// Cancel an invoice
  Future<bool> cancelInvoice({
    required String invoiceId,
    required String motivo,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'cancel-cfdi',
        body: {
          'invoice_id': invoiceId,
          'motivo': motivo,
        },
      );

      return response.status == 200;
    } catch (e) {
      return false;
    }
  }

  /// Get CFDI usage catalog
  List<CfdiUsoCatalog> getUsoCatalog() {
    return const [
      CfdiUsoCatalog(code: 'G01', description: 'Adquisición de mercancías'),
      CfdiUsoCatalog(code: 'G02', description: 'Devoluciones, descuentos o bonificaciones'),
      CfdiUsoCatalog(code: 'G03', description: 'Gastos en general'),
      CfdiUsoCatalog(code: 'I01', description: 'Construcciones'),
      CfdiUsoCatalog(code: 'I02', description: 'Mobiliario y equipo de oficina'),
      CfdiUsoCatalog(code: 'I03', description: 'Equipo de transporte'),
      CfdiUsoCatalog(code: 'I04', description: 'Equipo de cómputo'),
      CfdiUsoCatalog(code: 'I08', description: 'Otra maquinaria y equipo'),
      CfdiUsoCatalog(code: 'D01', description: 'Honorarios médicos y gastos hospitalarios'),
      CfdiUsoCatalog(code: 'D02', description: 'Gastos médicos por incapacidad'),
      CfdiUsoCatalog(code: 'D03', description: 'Gastos funerales'),
      CfdiUsoCatalog(code: 'D04', description: 'Donativos'),
      CfdiUsoCatalog(code: 'D05', description: 'Intereses reales hipotecarios'),
      CfdiUsoCatalog(code: 'D06', description: 'Aportaciones voluntarias al SAR'),
      CfdiUsoCatalog(code: 'D07', description: 'Primas de seguros de gastos médicos'),
      CfdiUsoCatalog(code: 'D08', description: 'Gastos de transportación escolar'),
      CfdiUsoCatalog(code: 'D09', description: 'Depósitos en cuentas de ahorro'),
      CfdiUsoCatalog(code: 'D10', description: 'Pagos por servicios educativos'),
      CfdiUsoCatalog(code: 'P01', description: 'Por definir'),
      CfdiUsoCatalog(code: 'S01', description: 'Sin efectos fiscales'),
      CfdiUsoCatalog(code: 'CP01', description: 'Pagos'),
      CfdiUsoCatalog(code: 'CN01', description: 'Nómina'),
    ];
  }

  /// Get fiscal regime catalog
  List<CfdiRegimenCatalog> getRegimenCatalog() {
    return const [
      CfdiRegimenCatalog(code: '601', description: 'General de Ley Personas Morales'),
      CfdiRegimenCatalog(code: '603', description: 'Personas Morales con Fines no Lucrativos'),
      CfdiRegimenCatalog(code: '605', description: 'Sueldos y Salarios'),
      CfdiRegimenCatalog(code: '606', description: 'Arrendamiento'),
      CfdiRegimenCatalog(code: '607', description: 'Régimen de Enajenación o Adquisición de Bienes'),
      CfdiRegimenCatalog(code: '608', description: 'Demás ingresos'),
      CfdiRegimenCatalog(code: '610', description: 'Residentes en el Extranjero sin Establecimiento Permanente en México'),
      CfdiRegimenCatalog(code: '611', description: 'Ingresos por Dividendos'),
      CfdiRegimenCatalog(code: '612', description: 'Personas Físicas con Actividades Empresariales y Profesionales'),
      CfdiRegimenCatalog(code: '614', description: 'Ingresos por intereses'),
      CfdiRegimenCatalog(code: '615', description: 'Régimen de los ingresos por obtención de premios'),
      CfdiRegimenCatalog(code: '616', description: 'Sin obligaciones fiscales'),
      CfdiRegimenCatalog(code: '620', description: 'Sociedades Cooperativas de Producción'),
      CfdiRegimenCatalog(code: '621', description: 'Incorporación Fiscal'),
      CfdiRegimenCatalog(code: '622', description: 'Actividades Agrícolas, Ganaderas, Silvícolas y Pesqueras'),
      CfdiRegimenCatalog(code: '623', description: 'Opcional para Grupos de Sociedades'),
      CfdiRegimenCatalog(code: '624', description: 'Coordinados'),
      CfdiRegimenCatalog(code: '625', description: 'Régimen de las Actividades Empresariales con ingresos a través de Plataformas Tecnológicas'),
      CfdiRegimenCatalog(code: '626', description: 'Régimen Simplificado de Confianza'),
    ];
  }
}

/// Result of CFDI invoice request
class CfdiInvoiceResult {
  final bool success;
  final String? invoiceId;
  final String? uuid;
  final String? folio;
  final String? xmlUrl;
  final String? pdfUrl;
  final String? error;

  CfdiInvoiceResult({
    required this.success,
    this.invoiceId,
    this.uuid,
    this.folio,
    this.xmlUrl,
    this.pdfUrl,
    this.error,
  });
}

/// CFDI Invoice model
class CfdiInvoice {
  final String id;
  final String driverId;
  final String? uuid;
  final String? folio;
  final String? serie;
  final String rfcReceptor;
  final String? nombreReceptor;
  final String usoCfdi;
  final String? regimenFiscal;
  final double subtotal;
  final double iva;
  final double total;
  final String currency;
  final String status;
  final String? xmlUrl;
  final String? pdfUrl;
  final String? cancelMotivo;
  final DateTime? cancelledAt;
  final DateTime createdAt;

  CfdiInvoice({
    required this.id,
    required this.driverId,
    this.uuid,
    this.folio,
    this.serie,
    required this.rfcReceptor,
    this.nombreReceptor,
    required this.usoCfdi,
    this.regimenFiscal,
    required this.subtotal,
    required this.iva,
    required this.total,
    required this.currency,
    required this.status,
    this.xmlUrl,
    this.pdfUrl,
    this.cancelMotivo,
    this.cancelledAt,
    required this.createdAt,
  });

  factory CfdiInvoice.fromJson(Map<String, dynamic> json) {
    return CfdiInvoice(
      id: json['id'],
      driverId: json['driver_id'],
      uuid: json['uuid'],
      folio: json['folio'],
      serie: json['serie'],
      rfcReceptor: json['rfc_receptor'] ?? '',
      nombreReceptor: json['nombre_receptor'],
      usoCfdi: json['uso_cfdi'] ?? 'G03',
      regimenFiscal: json['regimen_fiscal'],
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      iva: (json['iva'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] ?? 'MXN',
      status: json['status'] ?? 'pending',
      xmlUrl: json['xml_url'],
      pdfUrl: json['pdf_url'],
      cancelMotivo: json['cancel_motivo'],
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.parse(json['cancelled_at'])
          : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  bool get isPending => status == 'pending';
  bool get isIssued => status == 'issued';
  bool get isCancelled => status == 'cancelled';
}

/// CFDI Usage catalog item
class CfdiUsoCatalog {
  final String code;
  final String description;

  const CfdiUsoCatalog({
    required this.code,
    required this.description,
  });

  @override
  String toString() => '$code - $description';
}

/// CFDI Fiscal Regime catalog item
class CfdiRegimenCatalog {
  final String code;
  final String description;

  const CfdiRegimenCatalog({
    required this.code,
    required this.description,
  });

  @override
  String toString() => '$code - $description';
}
