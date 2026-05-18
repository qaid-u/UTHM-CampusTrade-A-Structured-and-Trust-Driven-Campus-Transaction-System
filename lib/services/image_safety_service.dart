import '../constants/app_defaults.dart';

class ImageSafetyService {
  /// Rejects invalid image URLs before UI uses them
  static String safe(String? url) {
    if (url == null) return AppDefaults.defaultProfileImage;

    final cleaned = url.trim();

    if (cleaned.isEmpty) return AppDefaults.defaultProfileImage;

    final isValidImage =
        cleaned.startsWith('http') &&
        (cleaned.contains('.png') ||
            cleaned.contains('.jpg') ||
            cleaned.contains('.jpeg') ||
            cleaned.contains('.webp') ||
            cleaned.contains('img.icons8.com'));

    if (!isValidImage) {
      return AppDefaults.defaultProfileImage;
    }

    return cleaned;
  }
}
