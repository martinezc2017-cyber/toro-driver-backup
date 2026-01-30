import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
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
      // DocumentOCR: ML Kit not available on this platform');
      return null;
    }

    try {
      final inputImage = InputImage.fromFilePath(image.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      if (recognizedText.text.isEmpty) {
        // DocumentOCR: No text found in image');
        return null;
      }

      // DocumentOCR: Extracted ${recognizedText.text.length} characters');
      final data = _parseInsuranceCard(recognizedText.text);
      lastExtractedData = data;
      return data;
    } catch (e) {
      // DocumentOCR Error: $e');
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

  /// Extract from File directly
  Future<InsuranceCardData?> extractFromFile(File file) async {
    return extractFromImage(XFile(file.path));
  }

  /// Extract license from File directly
  Future<DriverLicenseData?> extractLicenseFromFile(File file) async {
    return extractFromLicense(XFile(file.path));
  }

  /// Parse extracted text to find insurance fields
  InsuranceCardData _parseInsuranceCard(String text) {
    final upperText = text.toUpperCase();
    final lines = text.split('\n');

    return InsuranceCardData(
      vin: _extractVin(upperText),
      policyNumber: _extractPolicyNumber(upperText, lines),
      expiryDate: _extractExpiryDate(upperText),
      insuranceCompany: _extractCompany(upperText, lines),
      driverName: _extractDriverName(lines),
      vehicleMake: _extractVehicleMake(upperText),
      vehicleModel: _extractVehicleModel(upperText),
      vehicleYear: _extractVehicleYear(upperText),
      rawText: text,
    );
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
    // Common patterns: POL-XXXXXX, Policy: XXXXXX, Policy No: XXXXXX
    final patterns = [
      RegExp(r'POL[ICY\-#:\s]*[:\s]?([A-Z0-9\-]{6,20})', caseSensitive: false),
      RegExp(
        r'POLICY\s*(?:NO|NUMBER|#)?[:\s]?\s*([A-Z0-9\-]{6,20})',
        caseSensitive: false,
      ),
      RegExp(r'(?:NO|NUMBER)[:\s]+([A-Z0-9\-]{8,20})', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.groupCount >= 1) {
        return match.group(1)?.trim();
      }
    }

    return null;
  }

  /// Extract expiry date
  DateTime? _extractExpiryDate(String text) {
    // Common formats: MM/DD/YYYY, MM-DD-YYYY, YYYY-MM-DD
    final patterns = [
      // MM/DD/YYYY or MM-DD-YYYY after expiry keywords
      RegExp(
        r'(?:EXP(?:IR(?:Y|ES|ATION))?|EFFECTIVE\s*TO|TO)[:\s]*(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})',
        caseSensitive: false,
      ),
      // General date pattern
      RegExp(r'(\d{1,2})[\/\-](\d{1,2})[\/\-](20\d{2})'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        try {
          int month = int.parse(match.group(1)!);
          int day = int.parse(match.group(2)!);
          int year = int.parse(match.group(3)!);

          if (year < 100) year += 2000;

          // Swap if month > 12 (likely DD/MM format)
          if (month > 12 && day <= 12) {
            final temp = month;
            month = day;
            day = temp;
          }

          final date = DateTime(year, month, day);
          // Only return if date is in the future (expiry)
          if (date.isAfter(DateTime.now())) {
            return date;
          }
        } catch (e) {
          continue;
        }
      }
    }

    return null;
  }

  /// Extract insurance company name
  String? _extractCompany(String text, List<String> lines) {
    final knownCompanies = [
      'STATE FARM',
      'GEICO',
      'PROGRESSIVE',
      'ALLSTATE',
      'USAA',
      'LIBERTY MUTUAL',
      'FARMERS',
      'NATIONWIDE',
      'TRAVELERS',
      'AMERICAN FAMILY',
      'ERIE',
      'HARTFORD',
      'MERCURY',
      'AAA',
      'ESURANCE',
      'METLIFE',
      'SAFECO',
      'KEMPER',
      'INFINITY',
      'AUTO-OWNERS',
      'CINCINNATI',
      'CHUBB',
      'HANOVER',
      'MAPFRE',
      'ROOT',
      'LEMONADE',
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
    final makes = [
      'TOYOTA', 'HONDA', 'FORD', 'CHEVROLET', 'CHEVY', 'NISSAN', 'HYUNDAI',
      'KIA', 'MAZDA', 'VOLKSWAGEN', 'VW', 'BMW', 'MERCEDES', 'AUDI', 'LEXUS',
      'JEEP', 'DODGE', 'RAM', 'GMC', 'SUBARU', 'TESLA', 'BUICK', 'CADILLAC',
      'CHRYSLER', 'ACURA', 'INFINITI', 'VOLVO', 'MITSUBISHI', 'FIAT', 'PORSCHE',
    ];

    for (final make in makes) {
      if (text.contains(make)) {
        if (make == 'CHEVY') return 'Chevrolet';
        if (make == 'VW') return 'Volkswagen';
        return make[0].toUpperCase() + make.substring(1).toLowerCase();
      }
    }
    return null;
  }

  /// Extract vehicle model
  String? _extractVehicleModel(String text) {
    final models = [
      'CAMRY', 'COROLLA', 'RAV4', 'HIGHLANDER', 'TACOMA', 'TUNDRA', 'CIVIC',
      'ACCORD', 'CR-V', 'PILOT', 'ODYSSEY', 'F-150', 'F150', 'EXPLORER',
      'ESCAPE', 'MUSTANG', 'FUSION', 'SILVERADO', 'MALIBU', 'EQUINOX', 'TAHOE',
      'SUBURBAN', 'ALTIMA', 'SENTRA', 'ROGUE', 'PATHFINDER', 'MAXIMA',
      'ELANTRA', 'SONATA', 'TUCSON', 'SANTA FE', 'PALISADE', 'OPTIMA',
      'SORENTO', 'SPORTAGE', 'TELLURIDE', 'K5', 'MODEL S', 'MODEL 3',
      'MODEL X', 'MODEL Y', 'WRANGLER', 'GRAND CHEROKEE', 'CHEROKEE',
    ];

    for (final model in models) {
      if (text.contains(model)) {
        return model;
      }
    }
    return null;
  }

  /// Extract vehicle year
  int? _extractVehicleYear(String text) {
    // Look for 4-digit year between 2000-2030
    final yearRegex = RegExp(r'\b(20[0-2]\d)\b');
    final matches = yearRegex.allMatches(text).toList();

    // Filter to reasonable car years
    for (final match in matches) {
      final year = int.parse(match.group(1)!);
      if (year >= 2000 && year <= DateTime.now().year + 1) {
        return year;
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
    required this.rawText,
  });

  bool get hasAnyData =>
      vin != null ||
      policyNumber != null ||
      expiryDate != null ||
      insuranceCompany != null ||
      driverName != null;

  Map<String, dynamic> toJson() => {
    'vin': vin,
    'policy_number': policyNumber,
    'expiry_date': expiryDate?.toIso8601String(),
    'insurance_company': insuranceCompany,
    'driver_name': driverName,
    'vehicle_make': vehicleMake,
    'vehicle_model': vehicleModel,
    'vehicle_year': vehicleYear,
  };

  @override
  String toString() =>
      'InsuranceCardData(vin: $vin, policy: $policyNumber, company: $insuranceCompany, expiry: $expiryDate)';
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
