// "Uso de la app" del chofer: qué pantalla cuenta y cuándo.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toro_driver/src/core/logging/uso_app_tracker.dart';

void main() {
  test('la raíz que no está al frente solo se recuerda, no cuenta', () {
    UsoAppTracker.marcar('/documents');
    UsoAppTracker.marcarRaiz('/inicio', visible: false);
    expect(UsoAppTracker.pantallaActual, '/documents');
    UsoAppTracker.marcarRaiz('/inicio');
    expect(UsoAppTracker.pantallaActual, '/inicio');
  });

  testWidgets('una pantalla sin nombre se registra por su tipo', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      navigatorObservers: [UsoAppTracker.observer],
      home: const SizedBox(),
    ));
    nav.currentState!.push(MaterialPageRoute(builder: (_) => const _PruebaScreen()));
    await tester.pumpAndSettle();
    expect(UsoAppTracker.pantallaActual, '_PruebaScreen');
  });
}

class _PruebaScreen extends StatelessWidget {
  const _PruebaScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('hola'));
}
