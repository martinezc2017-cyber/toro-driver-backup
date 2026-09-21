import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readProjectFile(String path) => File(path).readAsStringSync();

void main() {
  test('English, Spanish, and Spanish MX catalogs stay complete', () {
    final catalogs = <String, Map<String, dynamic>>{
      for (final locale in ['en', 'es', 'es-MX'])
        locale:
            jsonDecode(File('assets/lang/$locale.json').readAsStringSync())
                as Map<String, dynamic>,
    };
    final canonicalKeys = catalogs['en']!.keys.toSet();

    for (final entry in catalogs.entries) {
      expect(
        entry.value.keys.toSet(),
        canonicalKeys,
        reason: '${entry.key} must contain the complete translation catalog',
      );
    }

    expect(catalogs['en']!['home_title'], 'Toro Driver - Home');
    expect(catalogs['es']!['home_title'], 'Toro Driver - Inicio');
    expect(catalogs['es-MX']!['home_title'], 'Toro Driver - Inicio');
  });

  test('release version and supported locales stay production-ready', () {
    final pubspec = readProjectFile('pubspec.yaml');
    final main = readProjectFile('lib/main.dart');

    // Antes esta prueba fijaba la versión exacta ('version: 1.2.84+4126'), así
    // que tronaba en CADA subida de versión y llevaba tiempo en rojo. Lo que
    // de verdad importa para la App Store es la FORMA: nombre x.y.z y un
    // número de build entero, que es lo que Apple compara contra el último
    // subido (el build 104 de Codemagic falló justo por repetir el 4135).
    final version =
        RegExp(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$', multiLine: true)
            .firstMatch(pubspec);
    expect(version, isNotNull,
        reason: 'pubspec.yaml debe traer "version: x.y.z+build"');
    expect(int.parse(version!.group(2)!), greaterThan(4135),
        reason: 'el build 4135 ya se subió a App Store Connect; '
            'el siguiente tiene que ser mayor');

    // useOnlyLangCode: true en main.dart hace que easy_localization distinga
    // solo por idioma, no por país. Por eso aquí van 'en' y 'es' y NO 'es-MX'.
    expect(main, contains("Locale('en')"));
    expect(main, contains("Locale('es')"));
    expect(main, contains("fallbackLocale: const Locale('en')"));
  });

  test('Apple sign-in uses the official button and deletion is complete', () {
    final login = readProjectFile('lib/src/screens/login_screen.dart');
    final settings = readProjectFile('lib/src/screens/settings_screen.dart');
    final auth = readProjectFile('lib/src/services/auth_service.dart');

    expect(login, contains('SignInWithAppleButton('));
    expect(login, isNot(contains('Icons.apple')));
    expect(settings, contains("'delete_account'.tr()"));
    expect(auth, contains('credential.authorizationCode'));
    expect(
      auth,
      contains("body['apple_client_id'] = 'com.tororide.driver'"),
    );
    expect(auth, contains("data['ok'] != true"));
  });

  test('iOS privacy declarations match active Driver features', () {
    final plist = readProjectFile('ios/Runner/Info.plist');
    final manifest = readProjectFile('ios/Runner/PrivacyInfo.xcprivacy');
    final project = readProjectFile('ios/Runner.xcodeproj/project.pbxproj');

    expect(plist, contains('NSLocationWhenInUseUsageDescription'));
    expect(plist, contains('NSCameraUsageDescription'));
    expect(plist, isNot(contains('NSMicrophoneUsageDescription')));
    expect(manifest, contains('<key>NSPrivacyTracking</key>'));
    expect(manifest, contains('<false/>'));
    expect(manifest, isNot(contains('NSPrivacyCollectedDataTypeAudioData')));
    expect(project, contains('PrivacyInfo.xcprivacy in Resources'));
  });

  test('Stripe Connect and cash out remain country-aware', () {
    final connect = readProjectFile(
      'lib/src/services/stripe_connect_service.dart',
    );
    final payment = readProjectFile('lib/src/services/payment_service.dart');
    final cashOut = readProjectFile('lib/src/screens/cash_out_screen.dart');

    expect(connect, contains("stripe_country"));
    expect(connect, contains('resolvedProvider'));
    expect(payment, contains("stripe_country"));
    expect(cashOut, contains('double get _fee => 0'));
    expect(cashOut, contains('StripeConnectService.instance.getAccountStatus'));
    expect(cashOut, isNot(contains("from('driver_bank_accounts')")));
    expect(cashOut, isNot(contains("from('driver_debit_cards')")));
  });

  test('installation evidence keeps a stable device identity', () {
    final tracking = readProjectFile(
      'lib/src/services/app_installation_service.dart',
    );

    expect(tracking, contains('installation_id'));
    expect(tracking, contains("'p_app_role': 'driver'"));
    expect(tracking, contains("'record_app_installation'"));
    expect(tracking, contains('SharedPreferences'));
  });

  test('regional screens format money instead of forcing Mexico', () {
    final home = readProjectFile('lib/src/screens/home_screen.dart');
    final earnings = readProjectFile('lib/src/screens/earnings_screen.dart');
    final marketplace = readProjectFile(
      'lib/src/screens/marketplace_delivery_accept_screen.dart',
    );

    expect(home, contains('formatMoney('));
    expect(home, contains('country:'));
    expect(earnings, contains('formatMoney('));
    expect(marketplace, contains('formatMoney('));
    expect(marketplace, contains('.tr()'));
  });
}
