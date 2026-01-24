import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../utils/app_colors.dart';
import '../utils/haptic_service.dart';

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  String _selectedLanguage = 'es';

  final List<Map<String, dynamic>> _languages = [
    {'code': 'es', 'name': 'Español', 'flag': '🇲🇽', 'region': 'México'},
    {'code': 'en', 'name': 'English', 'flag': '🇺🇸', 'region': 'United States'},
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selectedLanguage = context.locale.languageCode;
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
            Icon(Icons.language, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'language'.tr(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Current selection indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  _languages.firstWhere((l) => l['code'] == _selectedLanguage)['name'],
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Language list
          ..._languages.map((lang) => _buildLanguageItem(lang)),

          const SizedBox(height: 24),

          // Info note
          Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'El cambio se aplica inmediatamente',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageItem(Map<String, dynamic> lang) {
    final isSelected = lang['code'] == _selectedLanguage;

    return GestureDetector(
      onTap: () {
        HapticService.selectionClick();
        setState(() => _selectedLanguage = lang['code']);
        context.setLocale(Locale(lang['code']));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Text(lang['flag'], style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lang['name'],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? AppColors.primary : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    lang['region'],
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, size: 18, color: AppColors.primary)
            else
              Icon(Icons.circle_outlined, size: 18, color: AppColors.border),
          ],
        ),
      ),
    );
  }
}
