import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/logging/app_logger.dart';

/// Supported languages for the TORO ecosystem
enum AppLanguage {
  es('es', 'Español', 'Español'),
  en('en', 'English', 'Inglés'),
  zh('zh', '中文', 'Chino'),
  ja('ja', '日本語', 'Japonés'),
  ko('ko', '한국어', 'Coreano'),
  ar('ar', 'العربية', 'Árabe'),
  hi('hi', 'हिंदी', 'Hindi'),
  pt('pt', 'Português', 'Portugués'),
  fr('fr', 'Français', 'Francés'),
  de('de', 'Deutsch', 'Alemán');

  final String code;
  final String nativeName;
  final String spanishName;

  const AppLanguage(this.code, this.nativeName, this.spanishName);

  static AppLanguage fromCode(String code) {
    return AppLanguage.values.firstWhere(
      (lang) => lang.code == code,
      orElse: () => AppLanguage.es,
    );
  }
}

/// Service for translating messages between riders and drivers
/// Uses free translation APIs (MyMemory, LibreTranslate)
class TranslationService {
  static final TranslationService _instance = TranslationService._internal();
  static TranslationService get instance => _instance;

  TranslationService._internal();

  // Cache for translations to avoid repeated API calls
  final Map<String, String> _cache = {};

  /// Translate text from one language to another
  /// Returns original text if translation fails
  Future<String> translate({
    required String text,
    required String fromLang,
    required String toLang,
  }) async {
    // Skip if same language
    if (fromLang == toLang) return text;

    // Skip if text is empty
    if (text.trim().isEmpty) return text;

    // Check cache first
    final cacheKey = '${fromLang}_${toLang}_$text';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    try {
      // Try MyMemory API first (free, no API key needed)
      final translated = await _translateWithMyMemory(text, fromLang, toLang);
      if (translated != null) {
        _cache[cacheKey] = translated;
        return translated;
      }

      // Fallback to LibreTranslate
      final fallback = await _translateWithLibreTranslate(text, fromLang, toLang);
      if (fallback != null) {
        _cache[cacheKey] = fallback;
        return fallback;
      }

      return text; // Return original if all APIs fail
    } catch (e) {
      AppLogger.log('TRANSLATION -> Error: $e');
      return text;
    }
  }

  /// Translate using MyMemory API (free tier)
  Future<String?> _translateWithMyMemory(String text, String from, String to) async {
    try {
      final url = Uri.parse(
        'https://api.mymemory.translated.net/get?q=${Uri.encodeComponent(text)}&langpair=$from|$to',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final translated = data['responseData']['translatedText'] as String?;

        // MyMemory returns error messages in the translation when it fails
        if (translated != null &&
            !translated.contains('INVALID') &&
            !translated.contains('MYMEMORY WARNING')) {
          AppLogger.log('TRANSLATION -> MyMemory: "$text" -> "$translated"');
          return translated;
        }
      }
      return null;
    } catch (e) {
      AppLogger.log('TRANSLATION -> MyMemory error: $e');
      return null;
    }
  }

  /// Translate using LibreTranslate API (fallback)
  Future<String?> _translateWithLibreTranslate(String text, String from, String to) async {
    try {
      // List of public LibreTranslate instances
      final instances = [
        'https://libretranslate.com',
        'https://translate.argosopentech.com',
      ];

      for (final instance in instances) {
        try {
          final response = await http.post(
            Uri.parse('$instance/translate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'q': text,
              'source': from,
              'target': to,
              'format': 'text',
            }),
          ).timeout(const Duration(seconds: 10));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final translated = data['translatedText'] as String?;
            if (translated != null) {
              AppLogger.log('TRANSLATION -> LibreTranslate: "$text" -> "$translated"');
              return translated;
            }
          }
        } catch (e) {
          continue; // Try next instance
        }
      }
      return null;
    } catch (e) {
      AppLogger.log('TRANSLATION -> LibreTranslate error: $e');
      return null;
    }
  }

  /// Detect language from text (basic detection based on character sets)
  String detectLanguage(String text) {
    if (text.isEmpty) return 'es';

    // Check for Chinese characters
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(text)) return 'zh';

    // Check for Japanese (Hiragana, Katakana)
    if (RegExp(r'[\u3040-\u309f\u30a0-\u30ff]').hasMatch(text)) return 'ja';

    // Check for Korean
    if (RegExp(r'[\uac00-\ud7af]').hasMatch(text)) return 'ko';

    // Check for Arabic
    if (RegExp(r'[\u0600-\u06ff]').hasMatch(text)) return 'ar';

    // Check for Hindi/Devanagari
    if (RegExp(r'[\u0900-\u097f]').hasMatch(text)) return 'hi';

    // Default to Spanish (most common in this app context)
    return 'es';
  }

  /// Translate a message for communication between rider and driver
  /// Automatically detects source language and translates to target
  Future<Map<String, String>> translateMessage({
    required String message,
    required String senderLang,
    required List<String> targetLangs,
  }) async {
    final translations = <String, String>{};

    for (final targetLang in targetLangs) {
      if (targetLang == senderLang) {
        translations[targetLang] = message;
      } else {
        translations[targetLang] = await translate(
          text: message,
          fromLang: senderLang,
          toLang: targetLang,
        );
      }
    }

    return translations;
  }

  /// Clear the translation cache
  void clearCache() {
    _cache.clear();
  }
}

/// Helper extension for easy translation in widgets
extension StringTranslation on String {
  Future<String> translateTo(String targetLang, {String? fromLang}) async {
    final from = fromLang ?? TranslationService.instance.detectLanguage(this);
    return TranslationService.instance.translate(
      text: this,
      fromLang: from,
      toLang: targetLang,
    );
  }
}
