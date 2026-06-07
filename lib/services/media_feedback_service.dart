import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Interactive media element: optional audio feedback for key app actions.
/// Missing files or playback errors are ignored so user flows never block.
class MediaFeedbackService {
  MediaFeedbackService._();

  static final MediaFeedbackService instance = MediaFeedbackService._();

  static const String successSound = 'audio/success.mp3';
  static const String errorSound = 'audio/error.mp3';
  static const String notificationSound = 'audio/notification.mp3';
  static const String transactionCompleteSound =
      'audio/transaction_complete.mp3';

  final Set<String> _missingAssets = <String>{};

  Future<void> playSuccess() => _play(successSound);

  Future<void> playError() => _play(errorSound);

  Future<void> playNotification() => _play(notificationSound);

  Future<void> playTransactionComplete() => _play(transactionCompleteSound);

  Future<void> _play(String assetPath) async {
    if (_missingAssets.contains(assetPath)) return;

    try {
      await rootBundle.load('assets/$assetPath');
      final player = AudioPlayer();
      await player.setReleaseMode(ReleaseMode.release);
      await player.play(AssetSource(assetPath), volume: 0.65);
      player.onPlayerComplete.first.then((_) => player.dispose());
    } catch (e) {
      _missingAssets.add(assetPath);
      debugPrint('Audio feedback skipped: $e');
    }
  }
}
