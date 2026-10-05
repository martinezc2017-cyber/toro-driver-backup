// Lector de licencias mexicanas (5 oct 2026). Textos con la MISMA estructura y
// los mismos errores de OCR que los escaneos reales de producción, pero con
// datos inventados (nada de CURP ni domicilios reales en el repo).
import 'package:flutter_test/flutter_test.dart';
import 'package:toro_driver/src/services/document_ocr_service.dart';

const _bajaCalifornia = '''BAJA
CALIFORNIA
-0BIERNO DEL ESTADO
LICENCIA DECONDUCite
NOMBRE /NAME:
DRIVER'S LICENSE
CURP /POPULATION ID:
TIPO DE LICENCIA/
CLASS:
05/09/1990
DIRECCIÓN/ADDRESS:
NÚMERO DE LICENCIA/
LICENSE NUMBER:
BC202499999999
JUAN PRUEBA PEREZ
FECHA DE EXPEDICIÓN /
ISSUED:
22/10/2024
PEPJ900905HBCRRNO5
CHOFER C
FECHA DE VENCHMIENTOI
EXPIRES ON:
05/09/2029
FECHA DE NACIMIENTO / DOB:
E
CALLE FALSA 123
TIJUANA, BAJA CALIFORNIA''';

// El lector viejo devolvía "ENCIAV" como número (de "NÚMERO DE LICENCIAV").
const _numeroTrampa = '''BAJA
CALIFORNIA razón
LICENCIA DE CONDUCIR
CURP / POPULATION ID:
HEPC901102HBCRRRO8
FECHA DE NACIMIENTO/DOB:
02/11/1990
TIPO DE LICENCIA / CLASS:
NÚMERO DE LICENCIAV LICENSE NUMBER
BC202688888888
FECHA DE EXPEDICIÓN/ ISSUED
04/06/2026
FECHA DE VENCIMIENTO/EXPIRES ON:
02/11/2029
D
PLAYAS DE ROSARITO, BAJA CALIFORNIA''';

// Zacatecas: número solo dígitos tras la etiqueta y CURP partida por el OCR.
const _zacatecas = '''GOBIERNO DEL ESTADO DE ZACATECAS
ESTADOS UNIDOS MEXICANOS
4 CURP IPOPULA TION ID:
LICENCIA PARA CONDUCIR
PAPF8401 20HZSLNBO6
FECHA DE NACIMIENTO / DOB:
20/01/1984
FECHA DE EXPEDICIÓN/ ISSUE:
19/08/2026
FECHA DE VENCIMENTO /EXPIRES ON:
19/08/2028
TIPO DE
CLASS
NÚMERO DE LICENCIA
B
12 LICENSE NUMBER:
120299999
CHOFER''';

void main() {
  final ocr = DocumentOcrService();

  test('Baja California: vencimiento día/mes, CURP con O->0, tipo y estado', () {
    final d = ocr.parseLicenseText(_bajaCalifornia);
    expect(d.licenseNumber, 'BC202499999999');
    expect(d.expiryDate, DateTime(2029, 9, 5)); // NO 9 de mayo
    expect(d.curp, 'PEPJ900905HBCRRN05');
    expect(d.licenseClass, 'E');
    expect(d.state, 'BC');
  });

  test('el número ya no sale "ENCIAV"', () {
    final d = ocr.parseLicenseText(_numeroTrampa);
    expect(d.licenseNumber, 'BC202688888888');
    expect(d.expiryDate, DateTime(2029, 11, 2));
    expect(d.curp, 'HEPC901102HBCRRR08');
    expect(d.licenseClass, 'D');
  });

  test('Zacatecas: número tras la etiqueta, CURP partida, estado ZS', () {
    final d = ocr.parseLicenseText(_zacatecas);
    expect(d.licenseNumber, '120299999');
    expect(d.expiryDate, DateTime(2028, 8, 19));
    expect(d.curp, 'PAPF840120HZSLNB06');
    expect(d.licenseClass, 'B');
    expect(d.state, 'ZS');
  });
}
