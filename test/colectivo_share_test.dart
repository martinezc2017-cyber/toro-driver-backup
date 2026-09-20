import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:toro_driver/src/screens/tourism/colectivo_share_screen.dart';

/// El QR del cartel que el organizador publica en redes DEBE llevar una LIGA:
/// un número suelto, escaneado con la cámara, solo abre una búsqueda en el
/// buscador (pasó con el boleto del pasajero). Aquí se genera el mismo QR del
/// cartel y se guarda el PNG para leerlo con tools/leer_qr.py.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final evento = <String, dynamic>{
    'invitation_code': 'EVT-EA74381B',
    'event_name': 'Mexicali → San Felipe',
  };

  test('la liga del cartel apunta al viaje en toro-ride.com', () {
    expect(colectivoEventLink(evento), 'https://toro-ride.com/event/EVT-EA74381B');
    expect(colectivoEventLink(const {}), 'https://toro-ride.com');
  });

  test('el QR del cartel se genera con esa liga', () async {
    final painter = QrPainter(
      data: colectivoEventLink(evento),
      version: QrVersions.auto,
      gapless: true,
      // En el cartel el QR va sobre una tarjeta BLANCA; aquí se pinta igual,
      // si no el PNG sale transparente y ningún lector lo ve.
      emptyColor: Colors.white,
    );
    final data = await painter.toImageData(600, format: ui.ImageByteFormat.png);
    final out = File('build/cartel_qr.png');
    await out.create(recursive: true);
    await out.writeAsBytes(data!.buffer.asUint8List());
    expect(await out.length(), greaterThan(500));
  });
}
