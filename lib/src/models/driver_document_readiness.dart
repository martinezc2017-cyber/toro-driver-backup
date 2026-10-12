/// Document requirements returned by the same server rule used for approval.
/// Submission/review status and permission to go online remain separate facts.
class DriverDocumentReadiness {
  final List<String> missing;
  final List<String> expired;

  const DriverDocumentReadiness._({required this.missing, required this.expired});

  bool get hasRequiredDocuments => missing.isEmpty && expired.isEmpty;
  int get outstandingCount => {...missing, ...expired}.length;

  /// A stale backend configuration must not send a US driver to a SAT form.
  /// Keep the server blocker visible as an account configuration issue.
  bool hasCountryMismatch(String country) {
    if (country.trim().toUpperCase() != 'US') return false;
    const mexicoOnly = {'ine', 'rfc_constancia', 'rfc', 'curp'};
    return [...missing, ...expired].any(mexicoOnly.contains);
  }

  factory DriverDocumentReadiness.fromJson(dynamic value) {
    if (value is! Map || value['faltantes'] is! List) {
      throw const FormatException('Invalid driver document requirements');
    }

    List<String> readCodes(dynamic codes) {
      if (codes is! List ||
          codes.any((code) => code is! String || code.trim().isEmpty)) {
        throw const FormatException('Invalid driver document codes');
      }
      return List<String>.unmodifiable(
        codes.cast<String>().map((code) => code.trim()).toSet(),
      );
    }

    return DriverDocumentReadiness._(
      missing: readCodes(value['faltantes']),
      expired: readCodes(value['vencidos'] ?? const <String>[]),
    );
  }
}
