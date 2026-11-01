import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<void> saveBytesImpl(Uint8List bytes, String fileName, String mime) async {
  await FilePicker.platform.saveFile(dialogTitle: 'Save the file', fileName: fileName, bytes: bytes);
}
