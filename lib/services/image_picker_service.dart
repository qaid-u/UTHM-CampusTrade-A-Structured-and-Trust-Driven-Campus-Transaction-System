import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

class ImagePickerService {
  ImagePickerService._();
  static final instance = ImagePickerService._();

  final ImagePicker _picker = ImagePicker();

  bool _busy = false;

  Future<Uint8List?> pickImage() async {
    if (_busy) return null;

    _busy = true;

    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (file == null) return null;

      return await file.readAsBytes();
    } finally {
      _busy = false;
    }
  }
}
