import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/sample_data.dart';
import '../models/item_model.dart';
import '../models/message_model.dart';
import '../models/notification_model.dart';
import '../models/transaction_model.dart';
import '../models/user_model.dart';

class DatabaseService extends ChangeNotifier {
  DatabaseService._();

  static final DatabaseService instance = DatabaseService._();

  final List<UserModel> _users = [];
  final List<ItemModel> _items = [];
  final List<TransactionModel> _transactions = [];
  final List<MessageModel> _messages = [];
  final List<NotificationModel> _notifications = [];
  bool _loaded = false;

  List<UserModel> get users => List.unmodifiable(_users);
  List<ItemModel> get items => List.unmodifiable(_items);
  List<TransactionModel> get transactions => List.unmodifiable(_transactions);
  List<MessageModel> get messages => List.unmodifiable(_messages);
  List<NotificationModel> get notifications =>
      List.unmodifiable(_notifications.reversed);

  File get _storeFile => File('campustrade_store.json');

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      if (await _storeFile.exists()) {
        final raw =
            jsonDecode(await _storeFile.readAsString()) as Map<String, dynamic>;
        _users
          ..clear()
          ..addAll(
            (raw['users'] as List).map(
              (entry) => UserModel.fromJson(entry as Map<String, dynamic>),
            ),
          );
        _items
          ..clear()
          ..addAll(
            (raw['items'] as List).map(
              (entry) => ItemModel.fromJson(entry as Map<String, dynamic>),
            ),
          );
        _transactions
          ..clear()
          ..addAll(
            (raw['transactions'] as List? ?? []).map(
              (entry) =>
                  TransactionModel.fromJson(entry as Map<String, dynamic>),
            ),
          );
        _messages
          ..clear()
          ..addAll(
            (raw['messages'] as List? ?? []).map(
              (entry) => MessageModel.fromJson(entry as Map<String, dynamic>),
            ),
          );
        _notifications
          ..clear()
          ..addAll(
            (raw['notifications'] as List? ?? []).map(
              (entry) =>
                  NotificationModel.fromJson(entry as Map<String, dynamic>),
            ),
          );
      } else {
        _users.addAll(sampleUsers);
        _items.addAll(sampleItems);
        await save();
      }
    } catch (_) {
      _users
        ..clear()
        ..addAll(sampleUsers);
      _items
        ..clear()
        ..addAll(sampleItems);
    }
    notifyListeners();
  }

  Future<void> save() async {
    final payload = {
      'users': _users.map((item) => item.toJson()).toList(),
      'items': _items.map((item) => item.toJson()).toList(),
      'transactions': _transactions.map((item) => item.toJson()).toList(),
      'messages': _messages.map((item) => item.toJson()).toList(),
      'notifications': _notifications.map((item) => item.toJson()).toList(),
    };
    try {
      await _storeFile.writeAsString(jsonEncode(payload));
    } catch (_) {
      // Replace with Firestore, SQLite, shared_preferences, or path_provider
      // backed JSON storage for production-grade Android persistence.
    }
  }

  UserModel? findUser(String id) {
    for (final user in _users) {
      if (user.id == id) return user;
    }
    return null;
  }

  UserModel? findUserByEmail(String email) {
    for (final user in _users) {
      if (user.email.toLowerCase() == email.toLowerCase()) return user;
    }
    return null;
  }

  ItemModel? findItem(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> addUser(UserModel user) async {
    _users.add(user);
    await save();
    notifyListeners();
  }

  Future<void> addItem(ItemModel item) async {
    _items.insert(0, item);
    addNotification('Listing posted', '${item.title} is now visible.');
    await save();
    notifyListeners();
  }

  Future<void> addTransaction(TransactionModel transaction) async {
    _transactions.insert(0, transaction);
    addNotification(
      'Offer submitted',
      'RM ${transaction.offerPrice.toStringAsFixed(2)} offer is pending.',
    );
    await save();
    notifyListeners();
  }

  Future<void> updateTransactionStatus(
    String id,
    TransactionStatus status,
  ) async {
    final index = _transactions.indexWhere((item) => item.id == id);
    if (index == -1) return;
    _transactions[index] = _transactions[index].copyWith(status: status);
    if (status == TransactionStatus.accepted) {
      addNotification('Offer accepted', 'Meetup can now be arranged safely.');
    }
    if (status == TransactionStatus.completed) {
      final tx = _transactions[index];
      _increaseTrust(tx.buyerId);
      _increaseTrust(tx.sellerId);
      addNotification('Transaction completed', 'Trust scores were updated.');
    }
    await save();
    notifyListeners();
  }

  Future<void> addMessage(MessageModel message) async {
    _messages.add(message);
    addNotification('New chat message', message.text);
    await save();
    notifyListeners();
  }

  void addNotification(String title, String body) {
    _notifications.add(
      NotificationModel(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        body: body,
        createdAt: DateTime.now(),
      ),
    );
  }

  void _increaseTrust(String userId) {
    final index = _users.indexWhere((user) => user.id == userId);
    if (index == -1) return;
    final user = _users[index];
    _users[index] = user.copyWith(
      trustScore: (user.trustScore + 8).clamp(0, 100),
      completedTransactions: user.completedTransactions + 1,
      rating: (user.rating + 0.03).clamp(0, 5),
    );
  }
}
