// Web implementation — uses browser Clipboard API with proper await
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart';

Future<bool> writeImageToClipboard(Uint8List bytes) async {
  try {
    final blob = Blob(
      [bytes.toJS].toJS,
      BlobPropertyBag(type: 'image/png'),
    );
    final item = ClipboardItem(
      {'image/png': blob}.jsify()! as JSObject,
    );
    await window.navigator.clipboard.write([item].toJS).toDart;
    return true;
  } catch (e) {
    // ignore — caller handles fallback
    return false;
  }
}
