import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toro_driver/src/services/version_check_service.dart';

/// POR QUÉ EXISTE ESTA PRUEBA
///
/// Apple rechazó TORO Driver (guía 2.3.10) porque el aviso de "actualiza la
/// app" abría Google Play desde un iPhone: las dos plataformas leían el mismo
/// renglón de `app_versions` y ese renglón trae el enlace de Android.
///
/// Esta prueba cierra la puerta: en iOS el botón solo puede abrir el App Store
/// y la versión se compara contra el renglón propio de iOS.
void main() {
  const playUrl =
      'https://play.google.com/store/apps/details?id=com.tororide.driver';

  group('renglón de app_versions por plataforma', () {
    test('iOS lee su propio renglón', () {
      expect(
        VersionCheckService.rowIdFor('ios', 'toro_driver'),
        'toro_driver_ios',
      );
    });

    test('Android sigue leyendo el renglón de siempre', () {
      expect(
        VersionCheckService.rowIdFor('android', 'toro_driver'),
        'toro_driver',
      );
    });
  });

  group('tienda a la que manda el botón de actualizar', () {
    test('iOS nunca abre Google Play aunque la base lo traiga', () {
      final url = VersionCheckService.resolveStoreUrl('ios', playUrl);
      expect(url, VersionCheckService.appStoreUrl);
      expect(url, isNot(contains('google')));
    });

    test('iOS sin enlace en la base cae al App Store', () {
      expect(
        VersionCheckService.resolveStoreUrl('ios', null),
        VersionCheckService.appStoreUrl,
      );
      expect(
        VersionCheckService.resolveStoreUrl('ios', ''),
        VersionCheckService.appStoreUrl,
      );
    });

    test('iOS respeta un enlace del App Store capturado en la base', () {
      const otro = 'https://apps.apple.com/mx/app/toro-driver/id6760872144';
      expect(VersionCheckService.resolveStoreUrl('ios', otro), otro);
    });

    test('Android conserva el enlace de la base', () {
      expect(VersionCheckService.resolveStoreUrl('android', playUrl), playUrl);
      expect(VersionCheckService.resolveStoreUrl('android', null), isNull);
    });
  });

  test('el enlace del App Store apunta a la ficha de TORO Driver', () {
    final uri = Uri.parse(VersionCheckService.appStoreUrl);
    expect(uri.host, 'apps.apple.com');
    expect(uri.path, endsWith('id6760872144'));
  });

  test('la app de iPhone no se compila para iPad', () {
    // Universal ("1,2") obliga a subir capturas de iPad y a que Apple la revise
    // en iPad. Mientras no haya diseño de tableta, va solo para iPhone.
    final proyecto = File(
      '${Directory.current.path}/ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    expect(proyecto, isNot(contains('TARGETED_DEVICE_FAMILY = "1,2"')));
    expect(proyecto, contains('TARGETED_DEVICE_FAMILY = 1;'));
  });

  test('Info.plist explica cada permiso que la app puede pedir', () {
    final plist = File(
      '${Directory.current.path}/ios/Runner/Info.plist',
    ).readAsStringSync();
    const llaves = <String>[
      'NSLocationWhenInUseUsageDescription',
      'NSLocationAlwaysAndWhenInUseUsageDescription',
      'NSCameraUsageDescription',
      'NSPhotoLibraryUsageDescription',
      // Sin esta la app se cierra al tocar "Guardar imagen" al compartir.
      'NSPhotoLibraryAddUsageDescription',
      'NSFaceIDUsageDescription',
    ];
    for (final llave in llaves) {
      expect(plist, contains('<key>$llave</key>'), reason: 'falta $llave');
    }
    // La app no rastrea: si alguien agrega esta llave, Apple exige el aviso de
    // rastreo (ATT) y las etiquetas de privacidad dejan de cuadrar.
    expect(plist, isNot(contains('NSUserTrackingUsageDescription')));
  });
}
