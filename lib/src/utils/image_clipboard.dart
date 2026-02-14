// Mobile/IO implementation — uses pasteboard
import 'dart:typed_data';
import 'package:pasteboard/pasteboard.dart';

Future<bool> writeImageToClipboard(Uint8List bytes) async {
  await Pasteboard.writeImage(bytes);
  return true;
}
