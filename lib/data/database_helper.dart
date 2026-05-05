import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../core/session_manager.dart';
import '../security/crypto_helper.dart';
import 'package:flutter/foundation.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  final _secureStorage = const FlutterSecureStorage();

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('cashpay.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    String? key = await _secureStorage.read(key: 'db_key');
    if (key == null) {
      key = base64Url.encode(List<int>.generate(32, (_) => Random.secure().nextInt(256)));
      await _secureStorage.write(key: 'db_key', value: key);
    }
    return await openDatabase(path, version: 1, password: key, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_number TEXT UNIQUE,
        name TEXT,
        password TEXT,
        birthDate TEXT
        salt TEXT,
        balance REAL DEFAULT 100.0,
        sync_status TEXT DEFAULT 'pending'
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tx_id TEXT UNIQUE NOT NULL,
        sender_id INTEGER NOT NULL,
        receiver_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        status TEXT NOT NULL,
        signature TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        sync_status TEXT DEFAULT 'pending'
      )
    ''');
  }

  // --- دوال المستخدم (Login & Register) ---

  Future<int> createUser(Map<String, dynamic> user) async {
    final db = await database;
    return await db.insert('users', user, conflictAlgorithm: ConflictAlgorithm.fail);
  }

  Future<Map<String, dynamic>?> login(String idNumber, String password) async {
    final db = await database;
    final result = await db.query('users', where: 'id_number = ?', whereArgs: [idNumber]);

    if (result.isEmpty) return null;

    final user = result.first;
    final salt = user['salt']?.toString() ?? "";
    final hashedPassword = sha256.convert(utf8.encode(password + salt)).toString();

    if (hashedPassword != user['password']) return null;
    return user;
  }

  Future<String> getUserName(int userId) async {
    final db = await database;
    final res = await db.query('users', where: 'id = ?', whereArgs: [userId], columns: ['name']);
    return res.isNotEmpty ? res.first['name'] as String : "مستخدم";
  }

  // --- دوال الرصيد ---

  Future<double> getUserBalance(int userId) async {
    final db = await database;
    final res = await db.query('users', where: 'id = ?', whereArgs: [userId]);
    return res.isNotEmpty ? (res.first['balance'] as num).toDouble() : 0.0;
  }

  Future<void> updateUserBalance(int userId, double newBalance) async {
    final db = await database;
    await db.update('users', {'balance': newBalance, 'sync_status': 'pending'}, where: 'id = ?', whereArgs: [userId]);
  }

  // --- دوال العمليات (Transactions) ---

  Future<bool> isTransactionExists(String txId) async {
    final db = await database;
    final res = await db.query('transactions', where: 'tx_id = ?', whereArgs: [txId]);
    return res.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> getRecentTransactions(int userId) async {
    final db = await database;
    return await db.query('transactions', where: 'sender_id = ? OR receiver_id = ?', whereArgs: [userId, userId], orderBy: 'created_at DESC', limit: 10);
  }

  Future<List<Map<String, dynamic>>> getUserTransactions(int userId) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT t.*, s.name AS sender_name, r.name AS receiver_name
      FROM transactions t
      LEFT JOIN users s ON s.id = t.sender_id
      LEFT JOIN users r ON r.id = t.receiver_id
      WHERE t.sender_id = ? OR t.receiver_id = ?
      ORDER BY t.created_at DESC
    ''', [userId, userId]);
  }

  // --- دوال المزامنة (Sync) ---

  Future<List<Map<String, dynamic>>> getPendingTransactions() async {
    final db = await database;
    return await db.query('transactions', where: 'sync_status = ?', whereArgs: ['pending']);
  }

  Future<void> markAsSynced(String txId) async {
    final db = await database;
    await db.update('transactions', {'sync_status': 'synced'}, where: 'tx_id = ?', whereArgs: [txId]);
  }

  // --- منطق الاستلام الموحد ---

  Future<void> receiveTokens({
    required String txId, required int senderId, required int receiverId,
    required double amount, required String signature, required int timestamp,
  }) async {
    final db = await database;

    await db.transaction((txn) async {
      final existing = await txn.query('transactions', where: 'tx_id = ?', whereArgs: [txId]);
      if (existing.isNotEmpty) throw Exception("العملية مسجلة مسبقاً");

      // التحقق من التوقيع باستخدام الـ Helper
      final String amountStr = amount.toStringAsFixed(2);
      final String rawData = CryptoHelper.buildRawData(txId: txId, senderId: senderId, amountStr: amountStr, timestamp: timestamp);
      
      if (!CryptoHelper.verify(rawData, signature, senderId)) {
        throw Exception("فشل التحقق من أمان العملية");
      }

      await txn.rawUpdate('UPDATE users SET balance = balance - ? WHERE id = ?', [amount, senderId]);
      await txn.rawUpdate('UPDATE users SET balance = balance + ? WHERE id = ?', [amount, receiverId]);

      await txn.insert('transactions', {
        'tx_id': txId,
        'sender_id': senderId,
        'receiver_id': receiverId,
        'amount': amount,
        'type': 'transfer',
        'status': 'completed',
        'signature': signature,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'sync_status': 'pending',
      });
    });
  }

  // دالة مساعدة للاحتيال (يطلبها ملف الترانزاكشن)
  Future<int> countRecentTransactions(int userId) async {
    final db = await database;
    final fiveMinAgo = DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch;
    final res = await db.rawQuery('SELECT COUNT(*) as total FROM transactions WHERE (sender_id = ? OR receiver_id = ?) AND created_at > ?', [userId, userId, fiveMinAgo]);
    return Sqflite.firstIntValue(res) ?? 0;
  }

  Future<void> logFraud(String txId, String reason) async {
    final db = await database;
    // إذا لم يكن لديك جدول fraud_logs، يمكننا تجاهلها أو إنشاؤه
    print("FRAUD DETECTED: $txId - $reason");
  }
}
