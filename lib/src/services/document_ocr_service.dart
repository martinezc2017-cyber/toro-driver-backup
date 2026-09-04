import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Service to extract text from documents using ML Kit (offline, free)
/// Supports: Insurance cards, Driver's licenses, Vehicle registrations
/// Extracts: VIN, Policy Number, Expiry Date, Insurance Company, Driver Name, License Number
class DocumentOcrService {
  static final DocumentOcrService _instance = DocumentOcrService._internal();
  factory DocumentOcrService() => _instance;
  DocumentOcrService._internal();

  /// ML Kit text recognizer - works offline on iOS/Android
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  /// Extracted data from insurance card
  InsuranceCardData? lastExtractedData;

  /// Extracted data from driver's license
  DriverLicenseData? lastExtractedLicense;

  /// Check if OCR is available on current platform
  bool get isAvailable => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  /// Extract text from an image file using ML Kit
  Future<InsuranceCardData?> extractFromImage(XFile image) async {
    if (!isAvailable) {
      return null;
    }

    try {
      final inputImage = InputImage.fromFilePath(image.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      if (recognizedText.text.isEmpty) {
        return null;
      }

      final data = await _parseInsuranceCard(recognizedText.text);
      lastExtractedData = data;
      return data;
    } catch (e) {
      return null;
    }
  }

  /// Extract text from driver's license
  Future<DriverLicenseData?> extractFromLicense(XFile image) async {
    if (!isAvailable) {
      // DocumentOCR: ML Kit not available on this platform');
      return null;
    }

    try {
      final inputImage = InputImage.fromFilePath(image.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      if (recognizedText.text.isEmpty) {
        // DocumentOCR: No text found in license image');
        return null;
      }

      // DocumentOCR License: Extracted ${recognizedText.text.length} characters');
      final data = _parseDriverLicense(recognizedText.text);
      lastExtractedLicense = data;
      return data;
    } catch (e) {
      // DocumentOCR License Error: $e');
      return null;
    }
  }

  /// Extract data from INE (Mexican voter ID / credencial para votar)
  /// Reads the CURP directly off the document (NOT typed by the user)
  Future<IneData?> extractFromIne(XFile image) async {
    if (!isAvailable) {
      // DocumentOCR: ML Kit not available on this platform');
      return null;
    }

    try {
      final inputImage = InputImage.fromFilePath(image.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      if (recognizedText.text.isEmpty) {
        // DocumentOCR: No text found in INE image');
        return null;
      }

      // DocumentOCR INE: Extracted ${recognizedText.text.length} characters');
      return _parseIne(recognizedText.text);
    } catch (e) {
      // DocumentOCR INE Error: $e');
      return null;
    }
  }

  /// Extract from File directly
  Future<InsuranceCardData?> extractFromFile(File file) async {
    return extractFromImage(XFile(file.path));
  }

  /// Extract license from File directly
  Future<DriverLicenseData?> extractLicenseFromFile(File file) async {
    return extractFromLicense(XFile(file.path));
  }

  /// Extract INE from File directly
  Future<IneData?> extractIneFromFile(File file) async {
    return extractFromIne(XFile(file.path));
  }

  /// Parse extracted text to find insurance fields
  /// Uses NHTSA vPIC API for VIN decoding when available (free, no key needed)
  Future<InsuranceCardData> _parseInsuranceCard(String text) async {
    final upperText = text.toUpperCase();
    final lines = text.split('\n');

    final vin = _extractVin(upperText);
    final textMake = _extractVehicleMake(upperText);
    final textModel = _extractVehicleModel(upperText);
    final textYear = _extractVehicleYear(upperText);

    // Try NHTSA vPIC API for VIN decoding (fills make, model, year, body type)
    NhtsaVinResult? nhtsaResult;
    if (vin != null) {
      nhtsaResult = await _decodeVinWithNhtsa(vin);
    }

    return InsuranceCardData(
      vin: vin,
      policyNumber: _extractPolicyNumber(upperText, lines),
      expiryDate: _extractExpiryDate(upperText),
      insuranceCompany: _extractCompany(upperText, lines),
      driverName: _extractDriverName(lines),
      vehicleMake: textMake ?? nhtsaResult?.make ?? _decodeMakeFromVin(vin),
      vehicleModel: textModel ?? nhtsaResult?.model,
      vehicleYear: textYear ?? nhtsaResult?.year ?? _decodeYearFromVin(vin),
      vehiclePlate: _extractVehiclePlate(upperText, lines),
      vehicleColor: _extractVehicleColor(upperText, lines),
      rawText: text,
    );
  }

  // ==========================================================================
  // NHTSA vPIC API — free VIN decoding (no API key required)
  // https://vpic.nhtsa.dot.gov/api/
  // ==========================================================================

  /// Decode VIN using NHTSA vPIC API (US Dept of Transportation, free, no key)
  /// Returns make, model, year, and body class from any valid VIN
  Future<NhtsaVinResult?> _decodeVinWithNhtsa(String vin) async {
    try {
      final url = Uri.parse(
        'https://vpic.nhtsa.dot.gov/api/vehicles/decodevinvalues/$vin?format=json',
      );
      final response = await http.get(url).timeout(
        const Duration(seconds: 8),
      );

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final results = json['Results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;

      final r = results[0] as Map<String, dynamic>;

      // NHTSA returns empty strings for missing fields
      String? clean(String key) {
        final val = r[key]?.toString().trim();
        return (val != null && val.isNotEmpty && val != 'Not Applicable') ? val : null;
      }

      final make = clean('Make');
      final model = clean('Model');
      final yearStr = clean('ModelYear');
      final bodyClass = clean('BodyClass');

      if (make == null && model == null && yearStr == null) return null;

      return NhtsaVinResult(
        make: make != null ? _capitalizeMake(make) : null,
        model: model,
        year: yearStr != null ? int.tryParse(yearStr) : null,
        bodyClass: bodyClass,
      );
    } catch (_) {
      // Network error, timeout, etc. — fall back to offline decoding
      return null;
    }
  }

  /// Capitalize make properly (e.g., "TOYOTA" → "Toyota", "BMW" → "BMW")
  String _capitalizeMake(String make) {
    final upper = make.toUpperCase();
    // Acronyms that should stay all-caps
    const acronyms = {'BMW', 'GMC', 'RAM', 'KIA', 'MINI'};
    if (acronyms.contains(upper)) return upper;

    // Multi-word names
    if (upper.contains('MERCEDES')) return 'Mercedes-Benz';
    if (upper.contains('LAND ROVER')) return 'Land Rover';
    if (upper.contains('ALFA ROMEO')) return 'Alfa Romeo';
    if (upper.contains('ASTON MARTIN')) return 'Aston Martin';
    if (upper.contains('ROLLS')) return 'Rolls Royce';

    // Standard Title Case
    return make
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1).toLowerCase() : '')
        .join(' ');
  }

  /// Parse driver's license text
  DriverLicenseData _parseDriverLicense(String text) {
    final upperText = text.toUpperCase();
    final lines = text.split('\n');

    return DriverLicenseData(
      licenseNumber: _extractLicenseNumber(upperText, lines),
      fullName: _extractLicenseName(lines),
      dateOfBirth: _extractDateOfBirth(upperText),
      expiryDate: _extractLicenseExpiry(upperText),
      address: _extractAddress(lines),
      state: _extractState(upperText),
      licenseClass: _extractLicenseClass(upperText),
      rawText: text,
    );
  }

  /// Parse INE (credencial para votar) text
  IneData _parseIne(String text) {
    final upperText = text.toUpperCase();
    final lines = text.split('\n');

    return IneData(
      curp: _extractCurp(upperText),
      fullName: _extractLicenseName(lines),
      rawText: text,
    );
  }

  // ==========================================================================
  // INE PARSING
  // ==========================================================================

  /// Extract CURP from INE text.
  /// CURP is a strict 18-char format: 4 letters + 6 digits (birth date) +
  /// H/M (sex) + 5 letters (state + consonants) + 2 alphanumeric (homoclave).
  /// The strict format makes regex extraction reliable.
  String? _extractCurp(String text) {
    final curpRegex = RegExp(r'\b([A-Z]{4}\d{6}[HM][A-Z]{5}[A-Z0-9]{2})\b');
    final match = curpRegex.firstMatch(text);
    return match?.group(1);
  }

  // ==========================================================================
  // INSURANCE CARD PARSING
  // ==========================================================================

  /// Extract VIN (17 alphanumeric characters)
  String? _extractVin(String text) {
    // VIN is exactly 17 characters, no I, O, Q
    final vinRegex = RegExp(r'\b[A-HJ-NPR-Z0-9]{17}\b');
    final match = vinRegex.firstMatch(text);
    return match?.group(0);
  }

  /// Extract policy number
  String? _extractPolicyNumber(String text, List<String> lines) {
    // Words that should NEVER be returned as a policy number
    const invalidPolicies = {
      'NUMBER', 'NUMERO', 'POLICY', 'POLIZA', 'CERTIFICATE', 'COMPANY',
      'INSURED', 'INSURER', 'INSURANCE', 'VEHICLE', 'DRIVER', 'COVERAGE',
      'EFFECTIVE', 'EXPIRATION', 'ADDRESS', 'AGENT', 'ESTADO', 'SEGURO',
    };

    bool isValid(String? val) {
      if (val == null || val.length < 4 || val.length > 25) return false;
      if (invalidPolicies.contains(val.toUpperCase())) return false;
      // Reject if it looks like a date (MM/DD/YYYY)
      if (RegExp(r'^\d{1,2}/\d{1,2}/\d{2,4}$').hasMatch(val)) return false;
      // Reject if it's exactly 17 chars alphanumeric (likely VIN)
      if (val.length == 17 && RegExp(r'^[A-HJ-NPR-Z0-9]{17}$').hasMatch(val)) return false;
      return true;
    }

    // Labeled patterns (most reliable)
    final patterns = [
      // "POLICY NUMBER: ABC123" or "POLICY NO: ABC123"
      RegExp(r'POLICY\s*(?:NO\.?|NUMBER|NUM|#)\s*[:\s]\s*([A-Z0-9\-\s]{4,25})', caseSensitive: false),
      // "POLICY: ABC123"
      RegExp(r'POLICY\s*:\s*([A-Z0-9\-\s]{4,25})', caseSensitive: false),
      // "POL NO" or "POL#" or "POLNO" (common abbreviation on insurance cards)
      RegExp(r'POL\s*(?:NO\.?|#|ICY\s*(?:NO\.?|#|NUMBER))?\s*[:\s]\s*([A-Z0-9\-\s]{4,25})', caseSensitive: false),
      // Spanish: POLIZA NO: / NUMERO DE POLIZA:
      RegExp(r'P[OÓ]LIZA\s*(?:NO\.?|N[ÚU]M(?:ERO)?|#)\s*[:\s.]\s*([A-Z0-9\-\s]{4,25})', caseSensitive: false),
      RegExp(r'P[OÓ]LIZA\s*:\s*([A-Z0-9\-\s]{4,25})', caseSensitive: false),
      RegExp(r'NO\.?\s*DE\s*P[OÓ]LIZA[:\s]+([A-Z0-9\-\s]{4,25})', caseSensitive: false),
      // CERT / CERTIFICATE
      RegExp(r'(?:CERTIFICATE|CERT)\s*(?:NO\.?|#)?\s*[:\s]\s*([A-Z0-9\-\s]{4,25})', caseSensitive: false),
      // "INSURED'S COPY" often followed by policy on next line — handled below
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.groupCount >= 1) {
        final value = match.group(1)?.trim();
        if (isValid(value)) return value;
      }
    }

    // Line-by-line: find a line with any policy keyword, extract the number
    final policyKeywords = ['POLICY', 'POLIZA', 'PÓLIZA', 'POL NO', 'POL#', 'POLNO'];
    for (int i = 0; i < lines.length; i++) {
      final upper = lines[i].toUpperCase();
      if (policyKeywords.any((kw) => upper.contains(kw))) {
        // Try to extract alphanumeric from same line
        final numMatch = RegExp(r'(\d[\dA-Z\-]{3,19})').firstMatch(lines[i].toUpperCase());
        if (numMatch != null && isValid(numMatch.group(1)!.trim())) {
          return numMatch.group(1)!.trim();
        }
        // Try next line
        if (i + 1 < lines.length) {
          final next = lines[i + 1].trim();
          if (isValid(next) && RegExp(r'^[A-Z0-9\-\s]+$', caseSensitive: false).hasMatch(next)) {
            return next;
          }
        }
      }
    }

    // Fallback: look for alphanumeric sequences that look like policy numbers
    // Pattern: 2-4 letters followed by dash/space then 6+ digits (e.g. BWC-0012345)
    final letterDigit = RegExp(r'\b([A-Z]{2,5}[\-\s]?\d{6,15})\b', caseSensitive: false);
    for (final m in letterDigit.allMatches(text)) {
      final val = m.group(1)?.trim();
      if (isValid(val)) return val;
    }

    // Fallback: long standalone digit sequences (8-15 digits) that aren't phone numbers
    // Many policies are just numbers: "0012345678"
    final longNumber = RegExp(r'(?<!\d)(\d{8,15})(?!\d)');
    for (final m in longNumber.allMatches(text)) {
      final val = m.group(1)!;
      // Skip if it looks like a phone number (10 digits starting with 1 or common area codes)
      if (val.length == 10 && RegExp(r'^[2-9]\d{9}$').hasMatch(val)) continue;
      if (val.length == 11 && val.startsWith('1')) continue;
      // Skip if it's part of a date range
      if (isValid(val)) return val;
    }

    return null;
  }

  /// Extract expiry date
  DateTime? _extractExpiryDate(String text) {
    // Labeled expiry patterns — look for date after expiry keywords
    final expiryLabeled = [
      // English: EXP, EXPIRY, EXPIRES, EXPIRATION, EFF TO, EFFECTIVE TO
      RegExp(r'(?:EXP(?:IR(?:Y|ES|ATION))?|EFF(?:ECTIVE)?\s*TO|END\s*DATE)[:\s]*(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})', caseSensitive: false),
      // Spanish: VIGENCIA, VENCE, VENCIMIENTO, HASTA, VALIDEZ
      RegExp(r'(?:VIGENCIA|VENCE|VENCIMIENTO|HASTA|VALIDEZ)[:\s]*(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})', caseSensitive: false),
    ];

    for (final pattern in expiryLabeled) {
      final match = pattern.firstMatch(text);
      final date = _parseDateMatch(match);
      if (date != null) return date;
    }

    // "FROM mm/dd/yyyy TO mm/dd/yyyy" — take the TO date (the expiry)
    final fromTo = RegExp(
      r'(?:FROM|DESDE|EFF(?:ECTIVE)?)[:\s]*\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}\s*(?:TO|HASTA|[-–—])\s*(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})',
      caseSensitive: false,
    );
    final toMatch = fromTo.firstMatch(text);
    if (toMatch != null) {
      final date = _parseDateFromGroups(toMatch.group(1)!, toMatch.group(2)!, toMatch.group(3)!);
      if (date != null) return date;
    }

    // "mm/dd/yyyy - mm/dd/yyyy" or "mm/dd/yyyy TO mm/dd/yyyy" on same line
    final dateRange = RegExp(
      r'(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})\s*(?:TO|HASTA|[-–—]|THRU)\s*(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})',
      caseSensitive: false,
    );
    final rangeMatch = dateRange.firstMatch(text);
    if (rangeMatch != null) {
      // Take the second date (the expiry/end date)
      final date = _parseDateFromGroups(rangeMatch.group(4)!, rangeMatch.group(5)!, rangeMatch.group(6)!);
      if (date != null) return date;
    }

    // Generic: find ALL dates in the text, return the latest future date (likely expiry)
    final allDates = RegExp(r'(\d{1,2})[\/\-](\d{1,2})[\/\-](20\d{2})');
    DateTime? latestFuture;
    for (final match in allDates.allMatches(text)) {
      final date = _parseDateFromGroups(match.group(1)!, match.group(2)!, match.group(3)!);
      if (date != null && (latestFuture == null || date.isAfter(latestFuture))) {
        latestFuture = date;
      }
    }
    if (latestFuture != null) return latestFuture;

    // Try 2-digit year dates: mm/dd/yy
    final shortYear = RegExp(r'(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2})\b');
    for (final match in shortYear.allMatches(text)) {
      final yearPart = match.group(3)!;
      final fullYear = '20$yearPart';
      final date = _parseDateFromGroups(match.group(1)!, match.group(2)!, fullYear);
      if (date != null && (latestFuture == null || date.isAfter(latestFuture))) {
        latestFuture = date;
      }
    }

    return latestFuture;
  }

  /// Parse a date from regex match groups (month, day, year strings)
  DateTime? _parseDateFromGroups(String g1, String g2, String g3) {
    try {
      int month = int.parse(g1);
      int day = int.parse(g2);
      int year = int.parse(g3);
      if (year < 100) year += 2000;
      if (month > 12 && day <= 12) {
        final temp = month;
        month = day;
        day = temp;
      }
      if (month < 1 || month > 12 || day < 1 || day > 31) return null;
      final date = DateTime(year, month, day);
      // Only return future dates (this is an expiry)
      return date.isAfter(DateTime.now()) ? date : null;
    } catch (_) {
      return null;
    }
  }

  /// Parse a date from a regex Match object with 3 groups
  DateTime? _parseDateMatch(RegExpMatch? match) {
    if (match == null || match.groupCount < 3) return null;
    return _parseDateFromGroups(match.group(1)!, match.group(2)!, match.group(3)!);
  }

  /// Extract insurance company name
  String? _extractCompany(String text, List<String> lines) {
    // Sorted longest-first so multi-word names match before their substrings
    // (e.g. "BRISTOL WEST" before "WEST", "HDI SEGUROS" before "HDI")
    final knownCompanies = [
      // Multi-word first (longest)
      'SEGUROS MONTERREY', 'GENERAL DE SEGUROS', 'BANORTE SEGUROS',
      'PRIMERO SEGUROS', 'AMERICAN FAMILY', 'LIBERTY MUTUAL',
      'CHUBB SEGUROS', 'BRISTOL WEST', 'AUTO-OWNERS', 'ANA SEGUROS',
      'HDI SEGUROS', 'FRED LOYA', 'STATE FARM',
      // Single/short names
      'PROGRESSIVE', 'NATIONWIDE', 'CINCINNATI', 'DAIRYLAND',
      'ESURANCE', 'CHAMPAGNE', 'TRAVELERS', 'WAWANESA', 'ALLSTATE',
      'INFINITY', 'LEMONADE', 'QUALITAS', 'QUÁLITAS', 'HARTFORD',
      'KEMPER', 'SHELTER', 'MERCURY', 'BANORTE', 'INBURSA',
      'FARMERS', 'HANOVER', 'MAPFRE', 'SAFECO', 'METLIFE',
      'GEICO', 'USAA', 'ERIE', 'ZURICH', 'AFIRME', 'ATLAS',
      'ARGOS', 'CHUBB', 'SURA', 'ROOT', 'AAA', 'GNP', 'AXA', 'HDI',
    ];

    for (final company in knownCompanies) {
      if (text.contains(company)) {
        return company
            .split(' ')
            .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
            .join(' ');
      }
    }

    // Try first line if it looks like a company name
    if (lines.isNotEmpty) {
      final firstLine = lines[0].trim();
      if (firstLine.length > 3 &&
          firstLine.length < 40 &&
          !RegExp(r'\d{4}').hasMatch(firstLine)) {
        return firstLine;
      }
    }

    return null;
  }

  /// Extract driver name from insurance card
  String? _extractDriverName(List<String> lines) {
    // Look for "INSURED:", "NAME:", "NAMED INSURED:"
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].toUpperCase();
      if (line.contains('INSURED') || line.contains('NAME:')) {
        // Check same line after colon
        final colonIndex = lines[i].indexOf(':');
        if (colonIndex != -1 && colonIndex < lines[i].length - 2) {
          final name = lines[i].substring(colonIndex + 1).trim();
          if (name.length > 3 && _looksLikeName(name)) {
            return _formatName(name);
          }
        }
        // Check next line
        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1].trim();
          if (_looksLikeName(nextLine)) {
            return _formatName(nextLine);
          }
        }
      }
    }
    return null;
  }

  bool _looksLikeName(String text) {
    // Name should have letters, possibly spaces, no excessive numbers
    return RegExp(r'^[A-Za-z\s\.\-]{3,40}$').hasMatch(text) &&
        !RegExp(r'\d{3}').hasMatch(text);
  }

  String _formatName(String name) {
    return name
        .split(' ')
        .map(
          (w) => w.isNotEmpty
              ? w[0].toUpperCase() + w.substring(1).toLowerCase()
              : '',
        )
        .join(' ')
        .trim();
  }

  /// Extract vehicle make (brand)
  String? _extractVehicleMake(String text) {
    // Map of all known makes and their canonical names
    // Multi-word / longer names checked first to avoid partial matches
    final makeMap = <String, String>{
      'MERCEDES-BENZ': 'Mercedes-Benz', 'MERCEDES BENZ': 'Mercedes-Benz',
      'LAND ROVER': 'Land Rover', 'ALFA ROMEO': 'Alfa Romeo',
      'ASTON MARTIN': 'Aston Martin', 'ROLLS ROYCE': 'Rolls Royce',
      'MINI COOPER': 'Mini Cooper',
      'VOLKSWAGEN': 'Volkswagen', 'MITSUBISHI': 'Mitsubishi',
      'CHEVROLET': 'Chevrolet', 'CHRYSLER': 'Chrysler',
      'CADILLAC': 'Cadillac', 'INFINITI': 'Infiniti',
      'MASERATI': 'Maserati', 'LINCOLN': 'Lincoln',
      'PONTIAC': 'Pontiac', 'MERCURY': 'Mercury',
      'PORSCHE': 'Porsche', 'PEUGEOT': 'Peugeot',
      'RENAULT': 'Renault', 'CITROEN': 'Citroen',
      'HYUNDAI': 'Hyundai', 'GENESIS': 'Genesis',
      'FERRARI': 'Ferrari', 'BENTLEY': 'Bentley',
      'BUGATTI': 'Bugatti', 'MCLAREN': 'McLaren',
      'TOYOTA': 'Toyota', 'HONDA': 'Honda', 'FORD': 'Ford',
      'NISSAN': 'Nissan', 'SUBARU': 'Subaru', 'MAZDA': 'Mazda',
      'LEXUS': 'Lexus', 'ACURA': 'Acura', 'VOLVO': 'Volvo',
      'TESLA': 'Tesla', 'DODGE': 'Dodge', 'BUICK': 'Buick',
      'CHEVY': 'Chevrolet', 'JEEP': 'Jeep', 'AUDI': 'Audi',
      'FIAT': 'Fiat', 'MINI': 'Mini', 'SEAT': 'Seat',
      'SCION': 'Scion', 'SMART': 'Smart', 'ISUZU': 'Isuzu',
      'SUZUKI': 'Suzuki', 'SATURN': 'Saturn', 'HUMMER': 'Hummer',
      'JAGUAR': 'Jaguar', 'LOTUS': 'Lotus',
      'BMW': 'BMW', 'GMC': 'GMC', 'RAM': 'Ram', 'KIA': 'Kia',
      'VW': 'Volkswagen', 'MB': 'Mercedes-Benz',
    };

    // Check longest names first
    final sortedKeys = makeMap.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    for (final make in sortedKeys) {
      if (RegExp('\\b$make\\b').hasMatch(text)) {
        return makeMap[make];
      }
    }
    return null;
  }

  /// Extract vehicle model — comprehensive list + contextual search near make
  String? _extractVehicleModel(String text) {
    // Multi-word models first (longest), then single-word
    final models = [
      // Multi-word models (check first)
      'GRAND CHEROKEE', 'GRAND CARAVAN', 'GRAND WAGONEER', 'GRAND HIGHLANDER',
      'SANTA CRUZ', 'SANTA FE', 'COROLLA CROSS', 'ECLIPSE CROSS',
      'BRONCO SPORT', 'MODEL S', 'MODEL 3', 'MODEL X', 'MODEL Y',
      'LAND CRUISER', 'TOWN CAR', 'MONTE CARLO', 'EL CAMINO',
      'ID.4', 'ID4', 'GR86', 'BZ4X', 'CT4', 'CT5', 'XT4', 'XT5', 'XT6',
      'CX-5', 'CX-9', 'CX-3', 'CX-30', 'CX-50', 'CX-70', 'CX-90',
      'CR-V', 'CR-Z', 'HR-V', 'BR-V', 'MX-5', 'MX5',
      'F-150', 'F-250', 'F-350', 'F-450', 'F-550',
      'F150', 'F250', 'F350', 'F450',
      'C-CLASS', 'E-CLASS', 'S-CLASS', 'A-CLASS',
      'RAV4', 'RAV 4', 'NP300',
      // Toyota
      'CAMRY', 'COROLLA', 'HIGHLANDER', 'TACOMA', 'TUNDRA', '4RUNNER',
      'PRIUS', 'AVALON', 'SIENNA', 'SEQUOIA', 'VENZA', 'SUPRA', 'YARIS',
      'CROWN', 'CELICA', 'MATRIX', 'TERCEL',
      // Honda
      'CIVIC', 'ACCORD', 'PILOT', 'ODYSSEY', 'PASSPORT', 'RIDGELINE',
      'FIT', 'INSIGHT', 'PROLOGUE', 'ELEMENT', 'PRELUDE',
      // Ford
      'EXPLORER', 'ESCAPE', 'MUSTANG', 'FUSION', 'EDGE', 'EXPEDITION',
      'RANGER', 'BRONCO', 'MAVERICK', 'ECOSPORT', 'TRANSIT', 'FLEX',
      'FOCUS', 'FIESTA', 'TAURUS', 'EXCURSION', 'WINDSTAR', 'FREESTAR',
      // Chevrolet
      'SILVERADO', 'MALIBU', 'EQUINOX', 'TAHOE', 'SUBURBAN', 'TRAVERSE',
      'TRAX', 'BLAZER', 'COLORADO', 'CAMARO', 'CORVETTE', 'TRAILBLAZER',
      'BOLT', 'SPARK', 'IMPALA', 'CRUZE', 'SONIC', 'COBALT', 'AVEO',
      'CAPTIVA', 'CAVALIER', 'LUMINA', 'VENTURE',
      // Nissan
      'ALTIMA', 'SENTRA', 'ROGUE', 'PATHFINDER', 'MAXIMA', 'FRONTIER',
      'TITAN', 'KICKS', 'VERSA', 'MURANO', 'ARMADA', 'LEAF', 'JUKE',
      'MARCH', 'TSURU', 'QUEST', 'XTERRA',
      // Hyundai
      'ELANTRA', 'SONATA', 'TUCSON', 'PALISADE', 'KONA', 'VENUE',
      'ACCENT', 'IONIQ', 'VELOSTER', 'CRETA', 'AZERA', 'GENESIS',
      // Kia
      'OPTIMA', 'SORENTO', 'SPORTAGE', 'TELLURIDE', 'FORTE', 'SOUL',
      'SELTOS', 'CARNIVAL', 'RIO', 'NIRO', 'STINGER', 'SEDONA',
      'SPECTRA', 'AMANTI', 'BORREGO', 'CADENZA',
      'EV6', 'EV9', 'K5', 'K8',
      // Dodge
      'CHARGER', 'CHALLENGER', 'DURANGO', 'JOURNEY', 'DART', 'AVENGER',
      'HORNET', 'NEON', 'STRATUS', 'INTREPID', 'MAGNUM', 'NITRO',
      'CALIBER', 'VIPER',
      // Ram
      '1500', '2500', '3500',
      // Jeep
      'WRANGLER', 'CHEROKEE', 'COMPASS', 'RENEGADE', 'GLADIATOR',
      'WAGONEER', 'LIBERTY', 'PATRIOT', 'COMMANDER',
      // GMC
      'SIERRA', 'YUKON', 'ACADIA', 'TERRAIN', 'CANYON', 'ENVOY',
      'DENALI', 'SAVANA', 'JIMMY',
      // Subaru
      'OUTBACK', 'FORESTER', 'CROSSTREK', 'IMPREZA', 'LEGACY', 'ASCENT',
      'WRX', 'BRZ', 'SOLTERRA', 'TRIBECA', 'BAJA',
      // Tesla
      'CYBERTRUCK',
      // Volkswagen
      'JETTA', 'TIGUAN', 'ATLAS', 'PASSAT', 'GOLF', 'GTI', 'TAOS',
      'BEETLE', 'POLO', 'VENTO', 'BORA', 'DERBY',
      // BMW
      'X1', 'X2', 'X3', 'X4', 'X5', 'X6', 'X7',
      'M3', 'M4', 'M5', 'M8',
      // Mercedes
      'GLE', 'GLC', 'GLA', 'GLB', 'GLS', 'CLA', 'AMG', 'SLK', 'SL',
      // Mazda
      'MAZDA3', 'MAZDA6', 'MAZDA2',
      // Buick
      'ENCLAVE', 'ENCORE', 'ENVISION', 'LACROSSE', 'REGAL', 'VERANO',
      'LUCERNE', 'RENDEZVOUS', 'TERRAZA', 'CENTURY', 'LESABRE',
      // Cadillac
      'ESCALADE', 'LYRIQ', 'DEVILLE', 'SEVILLE', 'ELDORADO', 'CTS', 'ATS', 'SRX',
      // Chrysler
      'PACIFICA', '300', 'VOYAGER', 'SEBRING', 'CONCORDE', 'ASPEN',
      // Acura
      'MDX', 'RDX', 'TLX', 'ILX', 'INTEGRA', 'NSX', 'TSX', 'RSX', 'ZDX',
      // Infiniti
      'Q50', 'Q60', 'QX50', 'QX55', 'QX60', 'QX80', 'G35', 'G37', 'FX35',
      // Volvo
      'XC90', 'XC60', 'XC40', 'S60', 'S90', 'V60', 'V90', 'C30', 'C70',
      // Lexus
      'RX', 'ES', 'NX', 'IS', 'GX', 'LX', 'UX', 'LS', 'LC', 'RC',
      // Mitsubishi
      'OUTLANDER', 'MIRAGE', 'ASX', 'L200', 'LANCER', 'GALANT', 'MONTERO',
      'ENDEAVOR', 'RAIDER',
      // Porsche
      'CAYENNE', 'MACAN', 'PANAMERA', 'TAYCAN', '911', 'BOXSTER', 'CAYMAN',
      // Lincoln
      'NAVIGATOR', 'AVIATOR', 'CORSAIR', 'NAUTILUS', 'CONTINENTAL',
      'MKZ', 'MKC', 'MKX', 'MKT', 'MKS',
      // Jaguar
      'XF', 'XE', 'XJ',
      // Land Rover
      'DEFENDER', 'DISCOVERY', 'EVOQUE',
      // Fiat
      'PUNTO', 'PALIO', 'UNO', 'MOBI',
      // Suzuki
      'SWIFT', 'VITARA', 'JIMNY', 'ALTO', 'CIAZ',
      // Pontiac
      'FIREBIRD', 'SUNFIRE', 'VIBE', 'SOLSTICE', 'AZTEK',
      // Saturn
      'ASTRA', 'AURA', 'OUTLOOK', 'VUE',
    ];

    for (final model in models) {
      if (RegExp('\\b${RegExp.escape(model)}\\b').hasMatch(text)) {
        return model;
      }
    }

    // Contextual: look for words after known make names on insurance cards
    // Many cards show "2014 TOYOTA CAMRY" or "TOYOTA CAMRY" as vehicle description
    final makeNames = [
      'TOYOTA', 'HONDA', 'FORD', 'CHEVROLET', 'CHEVY', 'NISSAN', 'HYUNDAI',
      'KIA', 'DODGE', 'JEEP', 'GMC', 'SUBARU', 'MAZDA', 'VOLKSWAGEN', 'VW',
      'BMW', 'MERCEDES', 'AUDI', 'LEXUS', 'ACURA', 'INFINITI', 'VOLVO',
      'TESLA', 'BUICK', 'CADILLAC', 'CHRYSLER', 'LINCOLN', 'PONTIAC',
      'SATURN', 'MITSUBISHI', 'PORSCHE', 'JAGUAR', 'FIAT', 'SUZUKI',
      'RAM', 'GENESIS', 'SCION', 'HUMMER', 'ISUZU', 'MINI',
    ];

    for (final make in makeNames) {
      // Match: MAKE followed by an alphabetic word (the model)
      // Patterns: "TOYOTA CAMRY", "2014 TOYOTA CAMRY", "MAKE: TOYOTA MODEL: CAMRY"
      final afterMake = RegExp('\\b$make\\s+([A-Z][A-Z0-9\\-]{2,15})\\b');
      final match = afterMake.firstMatch(text);
      if (match != null) {
        final candidate = match.group(1)!;
        // Reject if the word is another make name or a common non-model word
        const rejectWords = {
          'INSURANCE', 'COMPANY', 'GROUP', 'MUTUAL', 'MOTOR', 'MOTORS',
          'AUTO', 'CAR', 'VEHICLE', 'CORP', 'INC', 'LLC', 'LTD',
          'FINANCIAL', 'SERVICES', 'GENERAL', 'NATIONAL', 'AMERICAN',
          'POLICY', 'PREMIUM', 'COVERAGE', 'AGENT', 'BROKER',
        };
        if (!rejectWords.contains(candidate) && !makeNames.contains(candidate)) {
          // It's a valid model word after the make
          return candidate[0].toUpperCase() + candidate.substring(1).toLowerCase();
        }
      }
    }

    return null;
  }

  /// Extract vehicle year
  int? _extractVehicleYear(String text) {
    // Look for 4-digit year between 1990-2030 near vehicle/year keywords first
    final labeledYear = RegExp(
      r'(?:YEAR|AÑO|YR|MODEL\s*YEAR|VEH(?:ICLE)?\s*YEAR)[:\s]*(\d{4})',
      caseSensitive: false,
    ).firstMatch(text);
    if (labeledYear != null) {
      final year = int.parse(labeledYear.group(1)!);
      if (year >= 1990 && year <= DateTime.now().year + 1) return year;
    }

    // Generic 4-digit year between 2000-2030
    final yearRegex = RegExp(r'\b(20[0-2]\d)\b');
    final matches = yearRegex.allMatches(text).toList();

    for (final match in matches) {
      final year = int.parse(match.group(1)!);
      if (year >= 2000 && year <= DateTime.now().year + 1) {
        return year;
      }
    }

    // Also try 1990s
    final older = RegExp(r'\b(19[9]\d)\b');
    final olderMatches = older.allMatches(text).toList();
    for (final match in olderMatches) {
      final year = int.parse(match.group(1)!);
      if (year >= 1990) return year;
    }

    return null;
  }

  // ==========================================================================
  // VIN DECODING — extract make and year from the VIN itself
  // ==========================================================================

  /// Decode vehicle make from VIN (positions 1-3 = World Manufacturer ID)
  String? _decodeMakeFromVin(String? vin) {
    if (vin == null || vin.length != 17) return null;
    final wmi = vin.substring(0, 3).toUpperCase();
    final wmi2 = vin.substring(0, 2).toUpperCase();

    const vinMakes = <String, String>{
      // Toyota
      '1T': 'Toyota', '2T': 'Toyota', '4T': 'Toyota', '5T': 'Toyota',
      'JT': 'Toyota',
      // Honda
      '1H': 'Honda', '2H': 'Honda', '5F': 'Honda', 'JH': 'Honda',
      // Ford
      '1F': 'Ford', '3F': 'Ford',
      // Chevrolet/GM
      '1G': 'Chevrolet', '2G': 'Chevrolet', '3G': 'Chevrolet',
      // Nissan
      '1N': 'Nissan', 'JN': 'Nissan',
      // Hyundai (5N also used by Nissan — resolved by 3-char WMI above)
      'KM': 'Hyundai',
      // Kia
      'KN': 'Kia',
      // Dodge/Chrysler/Jeep
      '1C': 'Chrysler', '2C': 'Chrysler', '3C': 'Chrysler',
      '1D': 'Dodge', '1J': 'Jeep',
      // BMW
      'WB': 'BMW',
      // Mercedes
      'WD': 'Mercedes-Benz', '4J': 'Mercedes-Benz',
      // Volkswagen
      'WV': 'Volkswagen', '3V': 'Volkswagen',
      // Audi
      'WA': 'Audi',
      // Subaru
      '4S': 'Subaru', 'JF': 'Subaru',
      // Mazda
      '1Y': 'Mazda', 'JM': 'Mazda',
      // Volvo
      'YV': 'Volvo',
      // Tesla
      '5Y': 'Tesla',
      // Lexus uses Toyota VINs (JT already listed above)
      // Acura uses Honda VINs (JH already listed above)
    };

    // Check 3-char WMI first for specificity, then 2-char
    if (wmi == '1GC' || wmi == '1GT' || wmi == '2GT') return 'GMC';
    if (wmi == '1GY' || wmi == '1G6') return 'Cadillac';
    if (wmi == '1G4') return 'Buick';
    if (wmi == '1G1' || wmi == '1GN' || wmi == '2G1' || wmi == '3G1') return 'Chevrolet';
    if (wmi == '1FA' || wmi == '1FB' || wmi == '1FC' || wmi == '1FD' || wmi == '1FT') return 'Ford';
    if (wmi == '1LN') return 'Lincoln';
    if (wmi == '5NM') return 'Hyundai';
    if (wmi == '5NP') return 'Hyundai';
    if (wmi == '5N1') return 'Nissan';
    if (wmi == '5N3') return 'Infiniti';
    if (wmi == '5XY') return 'Kia';
    if (wmi == 'KNA') return 'Kia';

    return vinMakes[wmi2];
  }

  /// Decode model year from VIN (position 10)
  int? _decodeYearFromVin(String? vin) {
    if (vin == null || vin.length != 17) return null;
    final code = vin[9].toUpperCase();
    const yearCodes = <String, int>{
      'A': 2010, 'B': 2011, 'C': 2012, 'D': 2013, 'E': 2014,
      'F': 2015, 'G': 2016, 'H': 2017, 'J': 2018, 'K': 2019,
      'L': 2020, 'M': 2021, 'N': 2022, 'P': 2023, 'R': 2024,
      'S': 2025, 'T': 2026, 'V': 2027, 'W': 2028, 'X': 2029,
      'Y': 2030,
      // Also support 2000s cycle
      '1': 2001, '2': 2002, '3': 2003, '4': 2004, '5': 2005,
      '6': 2006, '7': 2007, '8': 2008, '9': 2009,
    };
    return yearCodes[code];
  }

  /// Extract vehicle license plate number (US + Mexican formats)
  String? _extractVehiclePlate(String text, List<String> lines) {
    // First try labeled patterns (most reliable)
    final labeledPatterns = [
      // English labels
      RegExp(r'(?:LICENSE\s*PLATE|PLATE\s*(?:NO|NUMBER|#)?|TAG\s*(?:NO|#)?|REG(?:ISTRATION)?\s*(?:NO|#)?)[:\s]*([A-Z0-9]{1,3}[\s\-]?[A-Z0-9]{2,5}[\s\-]?[A-Z0-9]{0,4})', caseSensitive: false),
      // Spanish labels
      RegExp(r'(?:PLACAS?|MATRICULA|NO\.?\s*DE\s*PLACAS?)[:\s]*([A-Z0-9]{2,3}[\s\-]?[A-Z0-9]{2,4}[\s\-]?[A-Z0-9]{0,3})', caseSensitive: false),
    ];

    for (final pattern in labeledPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.groupCount >= 1) {
        final plate = match.group(1)?.trim().toUpperCase();
        if (plate != null && plate.length >= 4) return plate;
      }
    }

    // Then try line-by-line: look for a line after a plate keyword
    for (int i = 0; i < lines.length; i++) {
      final upper = lines[i].toUpperCase();
      if (upper.contains('PLATE') || upper.contains('PLACA') || upper.contains('TAG') || upper.contains('MATRICULA')) {
        // Check same line after colon/space
        final colonIdx = lines[i].indexOf(':');
        if (colonIdx != -1 && colonIdx < lines[i].length - 3) {
          final val = lines[i].substring(colonIdx + 1).trim().toUpperCase();
          if (val.length >= 4 && val.length <= 10 && RegExp(r'^[A-Z0-9\s\-]+$').hasMatch(val)) {
            return val;
          }
        }
        // Check next line
        if (i + 1 < lines.length) {
          final next = lines[i + 1].trim().toUpperCase();
          if (next.length >= 4 && next.length <= 10 && RegExp(r'^[A-Z0-9\s\-]+$').hasMatch(next)) {
            return next;
          }
        }
      }
    }

    return null;
  }

  /// Extract vehicle color (English + Spanish)
  String? _extractVehicleColor(String text, List<String> lines) {
    // All known color names (English + Spanish)
    final colorMap = <String, String>{
      // English
      'WHITE': 'White', 'BLACK': 'Black', 'SILVER': 'Silver',
      'GRAY': 'Gray', 'GREY': 'Gray', 'RED': 'Red', 'BLUE': 'Blue',
      'GREEN': 'Green', 'GOLD': 'Gold', 'BROWN': 'Brown', 'BEIGE': 'Beige',
      'TAN': 'Tan', 'ORANGE': 'Orange', 'YELLOW': 'Yellow',
      'PURPLE': 'Purple', 'MAROON': 'Maroon', 'BURGUNDY': 'Burgundy',
      'NAVY': 'Navy', 'CREAM': 'Cream', 'CHARCOAL': 'Charcoal',
      'BRONZE': 'Bronze', 'CHAMPAGNE': 'Champagne', 'PEARL': 'Pearl',
      // Common abbreviations on US insurance
      'WHT': 'White', 'BLK': 'Black', 'SIL': 'Silver', 'GRY': 'Gray',
      'BLU': 'Blue', 'GRN': 'Green', 'GLD': 'Gold', 'BRN': 'Brown',
      'YEL': 'Yellow', 'ONG': 'Orange', 'PLE': 'Purple', 'MRN': 'Maroon',
      // Spanish
      'BLANCO': 'Blanco', 'NEGRO': 'Negro', 'PLATA': 'Plata',
      'GRIS': 'Gris', 'ROJO': 'Rojo', 'AZUL': 'Azul', 'VERDE': 'Verde',
      'DORADO': 'Dorado', 'CAFE': 'Cafe', 'CAFÉ': 'Cafe',
      'MARRON': 'Marron', 'MARRÓN': 'Marron', 'NARANJA': 'Naranja',
      'AMARILLO': 'Amarillo', 'MORADO': 'Morado', 'GUINDA': 'Guinda',
      'VINO': 'Vino', 'ARENA': 'Arena', 'CREMA': 'Crema',
      'PERLA': 'Perla', 'BRONCE': 'Bronce', 'CHAMPÁN': 'Champan',
    };

    // First try labeled patterns (most reliable)
    final labeledPatterns = [
      RegExp(r'(?:VEH(?:ICLE)?\s*)?COL(?:O[RU])?[:\s]+([A-ZÁÉÍÓÚÑ]{3,12})', caseSensitive: false),
      RegExp(r'COLOR\s*(?:DEL\s*VEH[IÍ]CULO)?[:\s]+([A-ZÁÉÍÓÚÑ]{3,12})', caseSensitive: false),
    ];

    for (final pattern in labeledPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.groupCount >= 1) {
        final found = match.group(1)!.trim().toUpperCase();
        if (colorMap.containsKey(found)) return colorMap[found];
      }
    }

    // Line-by-line search after COLOR keyword
    for (int i = 0; i < lines.length; i++) {
      final upper = lines[i].toUpperCase();
      if (upper.contains('COLOR')) {
        final colonIdx = lines[i].indexOf(':');
        if (colonIdx != -1 && colonIdx < lines[i].length - 2) {
          final val = lines[i].substring(colonIdx + 1).trim().toUpperCase();
          for (final entry in colorMap.entries) {
            if (val.contains(entry.key)) return entry.value;
          }
        }
        // Check next line
        if (i + 1 < lines.length) {
          final next = lines[i + 1].trim().toUpperCase();
          for (final entry in colorMap.entries) {
            if (next == entry.key || next.contains(entry.key)) return entry.value;
          }
        }
      }
    }

    // Fallback: scan entire text for color words near vehicle-related keywords
    // Only match if near VEH, VEHICLE, VEHICULO, AUTO, CAR, etc.
    final vehicleContext = RegExp(r'(?:VEH|VEHICLE|VEHICULO|VEHÍCULO|AUTO|CAR|CARRO|CAMIONETA)', caseSensitive: false);
    if (vehicleContext.hasMatch(text)) {
      // Look for standalone color words in lines containing vehicle context
      for (final line in lines) {
        final upperLine = line.toUpperCase();
        if (vehicleContext.hasMatch(upperLine)) {
          for (final entry in colorMap.entries) {
            if (RegExp('\\b${entry.key}\\b').hasMatch(upperLine)) {
              return entry.value;
            }
          }
        }
      }
    }

    return null;
  }

  // ==========================================================================
  // DRIVER'S LICENSE PARSING
  // ==========================================================================

  /// Extract driver's license number
  String? _extractLicenseNumber(String text, List<String> lines) {
    final patterns = [
      // DL, DLN, LICENSE, LIC patterns
      RegExp(r'(?:DL|DLN|LICENSE|LIC)\s*(?:NO|NUMBER|#)?[:\s]*([A-Z0-9\-]{6,15})', caseSensitive: false),
      // After "DRIVER LICENSE" keyword
      RegExp(r'DRIVER\s*LICENSE[:\s]*([A-Z0-9\-]{6,15})', caseSensitive: false),
      // Generic alphanumeric that looks like a license
      RegExp(r'\b([A-Z]\d{7,8})\b'),
      RegExp(r'\b(\d{7,9})\b'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.groupCount >= 1) {
        return match.group(1)?.trim();
      }
    }
    return null;
  }

  /// Extract name from driver's license
  String? _extractLicenseName(List<String> lines) {
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].toUpperCase();
      // Look for FN, LN, NAME patterns
      if (line.contains('LN ') || line.contains('FN ') || line.contains('NAME')) {
        final colonIndex = lines[i].indexOf(':');
        if (colonIndex != -1 && colonIndex < lines[i].length - 2) {
          final name = lines[i].substring(colonIndex + 1).trim();
          if (name.length > 2 && _looksLikeName(name)) {
            return _formatName(name);
          }
        }
        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1].trim();
          if (_looksLikeName(nextLine)) {
            return _formatName(nextLine);
          }
        }
      }
    }

    // Try to find names by looking for lines with all caps letters
    for (final line in lines) {
      final trimmed = line.trim();
      if (_looksLikeName(trimmed) && trimmed.length > 5) {
        return _formatName(trimmed);
      }
    }
    return null;
  }

  /// Extract date of birth
  DateTime? _extractDateOfBirth(String text) {
    final patterns = [
      RegExp(r'(?:DOB|DATE\s*OF\s*BIRTH|BORN)[:\s]*(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})', caseSensitive: false),
      // Birth dates are usually older
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        try {
          int month = int.parse(match.group(1)!);
          int day = int.parse(match.group(2)!);
          int year = int.parse(match.group(3)!);

          if (year < 100) {
            year = year > 30 ? 1900 + year : 2000 + year;
          }

          if (month > 12 && day <= 12) {
            final temp = month;
            month = day;
            day = temp;
          }

          final date = DateTime(year, month, day);
          // DOB should be in the past and person should be 16+
          final age = DateTime.now().difference(date).inDays / 365;
          if (age >= 16 && age <= 100) {
            return date;
          }
        } catch (e) {
          continue;
        }
      }
    }
    return null;
  }

  /// Extract license expiry date
  DateTime? _extractLicenseExpiry(String text) {
    final patterns = [
      RegExp(r'(?:EXP|EXPIRES?)[:\s]*(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        try {
          int month = int.parse(match.group(1)!);
          int day = int.parse(match.group(2)!);
          int year = int.parse(match.group(3)!);

          if (year < 100) year += 2000;

          if (month > 12 && day <= 12) {
            final temp = month;
            month = day;
            day = temp;
          }

          return DateTime(year, month, day);
        } catch (e) {
          continue;
        }
      }
    }
    return null;
  }

  /// Extract address
  String? _extractAddress(List<String> lines) {
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      // Look for street number at start
      if (RegExp(r'^\d{1,5}\s+\w').hasMatch(line.trim())) {
        // Combine this line and next for full address
        String address = line.trim();
        if (i + 1 < lines.length) {
          address += ', ${lines[i + 1].trim()}';
        }
        return address;
      }
    }
    return null;
  }

  /// Extract state abbreviation
  String? _extractState(String text) {
    final states = [
      'AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DE', 'FL', 'GA',
      'HI', 'ID', 'IL', 'IN', 'IA', 'KS', 'KY', 'LA', 'ME', 'MD',
      'MA', 'MI', 'MN', 'MS', 'MO', 'MT', 'NE', 'NV', 'NH', 'NJ',
      'NM', 'NY', 'NC', 'ND', 'OH', 'OK', 'OR', 'PA', 'RI', 'SC',
      'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV', 'WI', 'WY',
    ];

    for (final state in states) {
      if (RegExp('\\b$state\\b').hasMatch(text)) {
        return state;
      }
    }
    return null;
  }

  /// Extract license class
  String? _extractLicenseClass(String text) {
    final match = RegExp(r'CLASS[:\s]*([A-D])', caseSensitive: false).firstMatch(text);
    return match?.group(1)?.toUpperCase();
  }

  /// Dispose resources
  void dispose() {
    _textRecognizer.close();
  }
}

/// Data extracted from insurance card
class InsuranceCardData {
  final String? vin;
  final String? policyNumber;
  final DateTime? expiryDate;
  final String? insuranceCompany;
  final String? driverName;
  final String? vehicleMake;
  final String? vehicleModel;
  final int? vehicleYear;
  final String? vehiclePlate;
  final String? vehicleColor;
  final String rawText;

  InsuranceCardData({
    this.vin,
    this.policyNumber,
    this.expiryDate,
    this.insuranceCompany,
    this.driverName,
    this.vehicleMake,
    this.vehicleModel,
    this.vehicleYear,
    this.vehiclePlate,
    this.vehicleColor,
    required this.rawText,
  });

  bool get hasAnyData =>
      vin != null ||
      policyNumber != null ||
      expiryDate != null ||
      insuranceCompany != null ||
      driverName != null ||
      vehicleMake != null ||
      vehicleModel != null ||
      vehicleYear != null ||
      vehiclePlate != null ||
      vehicleColor != null;

  /// True when ML Kit read text but structured parsing found nothing
  bool get hasRawTextOnly =>
      !hasAnyData && rawText.trim().length > 10;

  Map<String, dynamic> toJson() => {
    'vin': vin,
    'policy_number': policyNumber,
    'expiry_date': expiryDate?.toIso8601String(),
    'insurance_company': insuranceCompany,
    'driver_name': driverName,
    'vehicle_make': vehicleMake,
    'vehicle_model': vehicleModel,
    'vehicle_year': vehicleYear,
    'vehicle_plate': vehiclePlate,
    'vehicle_color': vehicleColor,
  };

  @override
  String toString() =>
      'InsuranceCardData(vin: $vin, policy: $policyNumber, company: $insuranceCompany, plate: $vehiclePlate, color: $vehicleColor)';
}

/// Result from NHTSA vPIC VIN decoder API
class NhtsaVinResult {
  final String? make;
  final String? model;
  final int? year;
  final String? bodyClass;

  NhtsaVinResult({this.make, this.model, this.year, this.bodyClass});
}

/// Data extracted from driver's license
class DriverLicenseData {
  final String? licenseNumber;
  final String? fullName;
  final DateTime? dateOfBirth;
  final DateTime? expiryDate;
  final String? address;
  final String? state;
  final String? licenseClass;
  final String rawText;

  DriverLicenseData({
    this.licenseNumber,
    this.fullName,
    this.dateOfBirth,
    this.expiryDate,
    this.address,
    this.state,
    this.licenseClass,
    required this.rawText,
  });

  bool get hasAnyData =>
      licenseNumber != null ||
      fullName != null ||
      expiryDate != null;

  bool get isExpired =>
      expiryDate != null && expiryDate!.isBefore(DateTime.now());

  Map<String, dynamic> toJson() => {
    'license_number': licenseNumber,
    'full_name': fullName,
    'date_of_birth': dateOfBirth?.toIso8601String(),
    'expiry_date': expiryDate?.toIso8601String(),
    'address': address,
    'state': state,
    'license_class': licenseClass,
  };

  @override
  String toString() =>
      'DriverLicenseData(license: $licenseNumber, name: $fullName, expiry: $expiryDate)';
}

/// Data extracted from an INE (Mexican voter ID / credencial para votar)
class IneData {
  final String? curp;
  final String? fullName;
  final String rawText;

  IneData({
    this.curp,
    this.fullName,
    required this.rawText,
  });

  bool get hasAnyData => curp != null || fullName != null;

  Map<String, dynamic> toJson() => {
    'curp': curp,
    'full_name': fullName,
  };

  @override
  String toString() => 'IneData(curp: $curp, name: $fullName)';
}
