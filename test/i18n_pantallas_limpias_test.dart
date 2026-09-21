import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// POR QUÉ EXISTE ESTA PRUEBA
///
/// La pantalla del mapa y la de dinero ya se habían "arreglado" antes y el
/// español seguía apareciendo en el teléfono: nada impedía que volviera a
/// entrar un texto escrito a mano. Esta prueba cierra esas pantallas: si
/// alguien vuelve a poner un literal en español en ellas, truena aquí y no en
/// la tienda.
///
/// Es una lista que CRECE: conforme se vaya limpiando el resto de la app, se
/// agregan archivos a [pantallasLimpias]. Lo que no está en la lista no se
/// revisa, para no trabar el trabajo del día con las 150 cadenas que faltan.
void main() {
  final raiz = Directory.current.path;

  const pantallasLimpias = <String>[
    'lib/src/screens/navigation_map_screen.dart',
    'lib/src/screens/earnings_screen.dart',
  ];

  const idiomas = <String>['es', 'en', 'es-MX'];

  // Palabras y letras que delatan español escrito a mano.
  final acentos = RegExp(r'[áéíóúñÁÉÍÓÚÑ¿¡]');
  final palabras = RegExp(
    r'\b(el|la|los|las|de|del|para|con|tu|tus|sin|por|que|una|un|más|está|'
    r'hay|ya|viaje|viajes|pasajero|conductor|efectivo|ganancias|saldo|'
    r'cuenta|pedido|recogida|paquete|tienda|cliente|esperando|disponible)\b',
    caseSensitive: false,
  );

  // Text('...'), label: '...', hintText: '...', tooltip: '...'
  final literal = RegExp(
    r"""(?<![\w.])(?:Text|label|labelText|hintText|tooltip)\s*[:(]\s*(?:const\s+)?'([^']{3,120})'""",
  );

  bool pareceEspanol(String t) {
    if (t.contains('.tr(')) return false;
    if (t.startsWith('assets/') || t.startsWith('http')) return false;
    return acentos.hasMatch(t) || palabras.hasMatch(t);
  }

  test('las pantallas ya limpiadas no traen texto en español escrito a mano',
      () {
    final hallazgos = <String>[];

    for (final ruta in pantallasLimpias) {
      final archivo = File('$raiz/$ruta');
      expect(archivo.existsSync(), isTrue, reason: 'no existe $ruta');
      final lineas = archivo.readAsStringSync().split('\n');
      for (var i = 0; i < lineas.length; i++) {
        final linea = lineas[i];
        if (linea.trimLeft().startsWith('//')) continue;
        final m = literal.firstMatch(linea);
        if (m != null && pareceEspanol(m.group(1)!)) {
          hallazgos.add('$ruta:${i + 1} -> "${m.group(1)}"');
        }
      }
    }

    expect(
      hallazgos,
      isEmpty,
      reason: 'Usa una llave con .tr() en vez del texto directo:\n'
          '${hallazgos.join('\n')}',
    );
  });

  test('los tres idiomas tienen exactamente las mismas llaves', () {
    final juegos = <String, Set<String>>{};
    for (final idioma in idiomas) {
      final archivo = File('$raiz/assets/lang/$idioma.json');
      expect(archivo.existsSync(), isTrue, reason: 'falta $idioma.json');
      final mapa = json.decode(archivo.readAsStringSync()) as Map<String, dynamic>;
      juegos[idioma] = mapa.keys.toSet();
    }
    final base = juegos['es']!;
    for (final idioma in idiomas) {
      expect(
        juegos[idioma]!.difference(base),
        isEmpty,
        reason: '$idioma tiene llaves que es no tiene',
      );
      expect(
        base.difference(juegos[idioma]!),
        isEmpty,
        reason: 'a $idioma le faltan llaves que sí están en es',
      );
    }
  });

  test('cada llave usada en esas pantallas existe en los tres idiomas', () {
    final usadas = <String>{};
    final usoLlave = RegExp(r"'([a-zA-Z0-9_.]+)'\s*\.tr\(");
    for (final ruta in pantallasLimpias) {
      final texto = File('$raiz/$ruta').readAsStringSync();
      for (final m in usoLlave.allMatches(texto)) {
        usadas.add(m.group(1)!);
      }
    }
    expect(usadas, isNotEmpty);

    for (final idioma in idiomas) {
      final mapa = json.decode(
        File('$raiz/assets/lang/$idioma.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final faltantes = usadas.where((k) => !mapa.containsKey(k)).toList()
        ..sort();
      expect(
        faltantes,
        isEmpty,
        reason: 'Sin estas llaves, easy_localization pinta el nombre crudo en '
            'la pantalla. Faltan en $idioma.json:\n${faltantes.join('\n')}',
      );
    }
  });
}
