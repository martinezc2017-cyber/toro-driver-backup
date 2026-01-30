import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:toro_driver/main.dart';

void main() {
  testWidgets('App loads successfully', (WidgetTester tester) async {
    await EasyLocalization.ensureInitialized();
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('es')],
        path: 'assets/lang',
        fallbackLocale: const Locale('en'),
        child: const ToroDriverApp(),
      ),
    );
    // Espera máximo 10 segundos a que la app cargue
    await tester.pumpAndSettle(const Duration(seconds: 10));
    // Verifica que aparece el texto traducido de login (toro_driver)
    expect(find.text('TORO DRIVER'), findsOneWidget);
    // O, si la traducción está en minúsculas, usar ignoreCase
    // expect(find.textContaining(RegExp('toro driver', caseSensitive: false)), findsOneWidget);
  });
}
