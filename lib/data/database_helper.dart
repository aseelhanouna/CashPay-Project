import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../core/session_manager.dart';
import '../security/crypto_helper.dart'; // استيراد الهيلبر الموحد
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
    await db.execute('''CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, id_number TEXT UNIQUE, name TEXT, password TEXT, salt TEXT, balance REAL DEFAULT 100.0, sync_status TEXT DEFAULT 'pending')''');
    await db.execute('''CREATE TABLE transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, tx_id TEXT UNIQUE NOT NULL, sender_id INTEGER NOT NULL, receiver_id INTEGER NOT NULL, amount REAL NOT NULL, type TEXT NOT NULL, status TEXT NOT NULL, signature TEXT NOT NULL, created_at INTEGER NOT NULL, sync_status TEXT DEFAULT 'pending')''');
  }

  // استخدام CryptoHelper الموحد بدلاً من الدالة القديمة
  bool verifyTxSignature(String txId, int senderId, double amount, int timestamp, String signature) {
    final String amountStr = amount.toStringAsFixed(2);
    final String rawData = "$txId|$senderId|$amountStr|$timestamp";
    return CryptoHelper.sign(rawData, senderId) == signature;
  }

  Future<void> receiveTokens({
    required String txId, required int senderId, required int receiverId,
    required double amount, required String signature, required int timestamp,
  }) async {
    final db = await database;

    await db.transaction((txn) async {
      // التأكد من عدم وجود العملية
      final existing = await txn.query('transactions', where: 'tx_id = ?', whereArgs: [txId]);
      if (existing.isNotEmpty) throw Exception("العملية مسجلة مسبقاً");

      // التحقق من صحة التوقيع
      if (!verifyTxSignature(txId, senderId, amount, timestamp, signature)) {
        throw Exception("فشل التحقق من أمان العملية");
      }

      // التحقق من الرصيد
      final sender = await txn.query('users', where: 'id = ?', whereArgs: [senderId]);
      final senderBalance = (sender.first['balance'] as num).toDouble();
      if (senderBalance < amount) throw Exception("رصيد المرسل غير كافٍ");

      // تحديث الأرصدة
      await txn.rawUpdate('UPDATE users SET balance = balance - ? WHERE id = ?', [amount, senderId]);
      await txn.rawUpdate('UPDATE users SET balance = balance + ? WHERE id = ?', [amount, receiverId]);

      // تسجيل العملية
      await txn.insert('transactions', {
        'tx_id': txId,
        'sender_id': senderId,
        'receiver_id': receiverId,
        'amount': amount,
        'type': 'receive',
        'status': 'completed',
        'signature': signature,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'sync_status': 'pending',
      });
    });
  }

  Future<double> getUserBalance(int userId) async {
    final db = await database;
    final res = await db.query('users', where: 'id = ?', whereArgs: [userId]);
    return res.isNotEmpty ? (res.first['balance'] as num).toDouble() : 0.0;
  }

  Future<bool> isTransactionExists(String txId) async {
    final db = await database;
    final res = await db.query('transactions', where: 'tx_id = ?', whereArgs: [txId]);
    return res.isNotEmpty;
  }
}
