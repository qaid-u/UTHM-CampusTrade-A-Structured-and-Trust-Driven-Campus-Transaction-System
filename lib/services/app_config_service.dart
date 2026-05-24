import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AppConfigService {
  AppConfigService._();
  static final instance = AppConfigService._();

  static const _defaultCategories = <String>[
    'Textbooks',
    'Electronics',
    'Clothes',
    'Room Items',
    'Sports',
    'Others',
  ];

  static const _defaultConditions = <String>[
    'New',
    'Like new',
    'Good',
    'Fair',
    'Used',
  ];

  static const _defaultMeetupLocations = <String>[
    'Library',
    'Student Centre',
    'Faculty Area',
    'Residential College',
    'Cafe',
  ];

  List<String> categories = List.of(_defaultCategories);
  List<String> conditions = List.of(_defaultConditions);
  List<String> meetupLocations = List.of(_defaultMeetupLocations);

  Future<void> load() async {
    try {
      final doc = await _getConfigWithRetry();

      if (!doc.exists) return;

      final data = doc.data() ?? {};

      categories = _readList(data, 'categories', _defaultCategories);
      conditions = _readList(data, 'conditions', _defaultConditions);
      meetupLocations = _readList(
        data,
        'meetupLocations',
        _defaultMeetupLocations,
      );
    } on FirebaseException catch (e) {
      debugPrint('App config unavailable, using defaults: ${e.code}');
    } catch (e) {
      debugPrint('App config failed, using defaults: $e');
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _getConfigWithRetry() async {
    const retryableCodes = {
      'aborted',
      'cancelled',
      'deadline-exceeded',
      'resource-exhausted',
      'unavailable',
      'unknown',
    };

    var delay = const Duration(milliseconds: 400);

    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        return await FirebaseFirestore.instance
            .collection('config')
            .doc('app')
            .get();
      } on FirebaseException catch (e) {
        final canRetry = retryableCodes.contains(e.code) && attempt < 3;
        if (!canRetry) rethrow;

        await Future.delayed(delay);
        delay *= 2;
      }
    }

    throw StateError('Config retry loop exited unexpectedly');
  }

  List<String> _readList(
    Map<String, dynamic> data,
    String key,
    List<String> fallback,
  ) {
    final value = data[key];
    if (value is! Iterable) return List.of(fallback);

    final strings = value.whereType<String>().toList();
    return strings.isEmpty ? List.of(fallback) : strings;
  }
}
