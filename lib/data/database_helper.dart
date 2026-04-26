import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../core/session_manager.dart';
import 'package:flutter/foundation.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  final _secureStorage = const FlutterSecureStorage();

  DatabaseHelper._init();

  // Gett 
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('cashpay.db'); // استدعاء الدالة الموحدة
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    String? key = await _secureStorage.read(key: 'db_key');

    if (key == null) {
      key = base64Url.encode(
        List<int>.generate(32, (_) => Random.secure().nextInt(256)),
      );
      await _secureStorage.write(key: 'db_key', value: key);
    }

    return await openDatabase(
      path,
      version: 1,
      password: key,
      onCreate: _createDB,
    );
  }

  // ======================
  // CREATE TABLES
  // ======================
  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_number TEXT UNIQUE,
        name TEXT,
        password TEXT,
        birthDate TEXT,
        pin TEXT,
        salt TEXT,
        balance REAL DEFAULT 100.0
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
        used INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        sync_status TEXT DEFAULT 'pending',
        timestamp TEXT,
        synced_at INTEGER
      )
    ''');
    await db.execute('''
    CREATE TABLE fraud_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tx_id TEXT,
      reason TEXT,
      created_at INTEGER
    )
    ''');
  }

  // ======================
  // AUTH & USER
  // ======================

  // تصحيح: استخدام database (الـ getter) بدلاً من db
  Future<int> createUser(Map<String, dynamic> user) async {
    final dbClient = await database;
    return await dbClient.insert(
      'users',
      user,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> login(String phone, String password) async {
    final db = await database;

    final result = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (result.isEmpty) return null;

    final user = result.first;
    final salt = user['salt']?.toString() ?? "";

    final hashedPassword = sha256
        .convert(utf8.encode(password + salt))
        .toString();

    if (hashedPassword != user['password']) {
      return null;
    }

    return {'id': user['id'], 'name': user['name'], 'id': user['id']};

  // ======================
  // SIGNATURE (Offline Logic)
  // ======================
  String generateSignature({
    required String txId,
    required int senderId,
    required int receiverId,
    required double amount,
    required int timestamp,
  }) {
    final secret = "USER_${senderId}_SECRET_KEY";
    final data = "$txId|$senderId|$receiverId|$amount|$timestamp|$secret";
    return sha256.convert(utf8.encode(data)).toString();
  }

  bool verifySignature({
    required String txId,
    required int senderId,
    required int receiverId,
    required double amount,
    required int timestamp,
    required String signature,
  }) {
    final expected = generateSignature(
      txId: txId,
      senderId: senderId,
      receiverId: receiverId,
      amount: amount,
      timestamp: timestamp,
    );
    return expected == signature;
  }

  // ======================
  // CORE TRANSACTIONS
  // ======================
  Future<void> receiveTokens({
    required String txId,
    required int senderId,
    required int receiverId,
    required double amount,
    required String signature,
    required int timestamp,
  }) async {
    final db = await database;
    bool locked = await SessionManager.isBlocked();

    if (locked) {
      throw Exception("رصيد غير كافي");
    }

    await db.transaction((txn) async {
      final exists = await txn.query(
        'transactions',
        where: 'tx_id = ?',
        whereArgs: [txId],
      );

      if (exists.isNotEmpty) {
        throw Exception("⚠️ هذا التحويل مستخدم مسبقاً");
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - timestamp > 5 * 60 * 1000) {
        throw Exception("⛔ انتهت صلاحية QR");
      }

      final valid = verifySignature(
        txId: txId,
        senderId: senderId,
        receiverId: receiverId,
        amount: amount,
        timestamp: timestamp,
        signature: signature,
      );

      if (!valid) {
        throw Exception("❌ QR غير صالح");
      }

      final sender = await txn.query(
        'users',
        where: 'id = ?',
        whereArgs: [senderId],
        columns: ['balance'],
      );

      final balance = (sender.first['balance'] as num).toDouble();

      if (balance < amount) {
        throw Exception("❌ رصيد غير كافي");
      }

      if (exists.isNotEmpty) throw Exception("مستخدم مسبقاً");
      if (now - timestamp > 60000) throw Exception("QR انتهى");
      if (balance < amount) throw Exception("رصيد غير كافي");
      await txn.rawUpdate(
        'UPDATE users SET balance = balance - ? WHERE id = ?',
        [amount, senderId],
      );

      await txn.rawUpdate(
        'UPDATE users SET balance = balance + ? WHERE id = ?',
        [amount, receiverId],
      );

      await txn.insert('transactions', {
        'tx_id': txId,
        'sender_id': senderId,
        'receiver_id': receiverId,
        'amount': amount,
        'type': 'transfer',
        'status': 'completed',
        'signature': signature,
        'created_at': now,
        'sync_status': 'pending',
        'synced_at': null,
      });
    });
  }

  Future<double> getUserBalance(int userId) async {
    final db = await database;
    final result = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      columns: ['balance'],
    );
    if (result.isNotEmpty) {
      // نأخذ القيمة ونحولها لـ double بأمان
      return (result.first['balance'] as num).toDouble();
    }
    return 100.0;
  }

  Future<List<Map<String, dynamic>>> getRecentTransactions(int userId) async {
    final db = await database;

    return await db.query(
      'transactions',
      where: 'sender_id = ? OR receiver_id = ?',
      whereArgs: [userId, userId],
      orderBy: 'created_at DESC',
      limit: 20,
    );
  }

  Future<List<Map<String, dynamic>>> getUserTransactions(int userId) async {
    final db = await database;

    return await db.rawQuery(
      '''
    SELECT t.*,
    sender.name AS sender_name,
    receiver.name AS receiver_name
    FROM transactions t
    LEFT JOIN users sender ON sender.id = t.sender_id
    LEFT JOIN users receiver ON receiver.id = t.receiver_id
    WHERE t.sender_id = ? OR t.receiver_id = ?
    ORDER BY t.created_at DESC
  ''',
      [userId, userId],
    );
  }

  Future<bool> isTransactionExists(String txId) async {
    final db = await database;

    final result = await db.query(
      'transactions',
      where: 'tx_id = ?',
      whereArgs: [txId],
    );

    // إذا كانت النتيجة ليست فارغة، فهذا يعني أن العملية مسجلة مسبقاً
    return result.isNotEmpty;
  }

  Future<String> getUserName(int userId) async {
    final db = await database;

    final res = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      columns: ['name'],
    );

    if (res.isNotEmpty) {
      return res.first['name'] as String;
    }

    return "مستخدم";
  }

  Future<List<Map<String, dynamic>>> getPendingTransactions() async {
    final db = await instance.database;

    return await db.query(
      'transactions',
      where: 'sync_status = ? OR sync_status = ?',
      whereArgs: ['pending', 'failed'],
    );
  }

  Future<int> countRecentTransactions(int userId) async {
    final db = await database;
    DateTime fiveMinutesAgo = DateTime.now().subtract(
      const Duration(minutes: 5),
    );
    String timeLimit = fiveMinutesAgo.toIso8601String();

    final List<Map<String, dynamic>> result = await db.rawQuery(
      '''
    SELECT COUNT(*) as total 
    FROM transactions 
    WHERE user_id = ? 
    AND timestamp > ?
  ''',
      [userId, timeLimit],
    );

    // 3. استخراج العدد من النتيجة
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> markAsSynced(String txId) async {
    final db = await database;

    await db.update(
      'transactions',
      {
        'sync_status': 'synced',
        'synced_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'tx_id = ?',
      whereArgs: [txId],
    );
  }

  Future<void> markAsFailed(String txId) async {
    final db = await database;

    await db.update(
      'transactions',
      {'sync_status': 'failed'},
      where: 'tx_id = ?',
      whereArgs: [txId],
    );
  }

  Future<void> logFraud(String txId, String reason) async {
    final db = await database;

    await db.insert('fraud_logs', {
      'tx_id': txId,
      'reason': reason,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // دالة شحن الرصيد في قاعدة البيانات
  Future<int> topUpBalance(int userId, double amount) async {
    final db = await instance.database;

    // نقوم بجلب الرصيد الحالي أولاً ثم إضافة المبلغ الجديد
    return await db.rawUpdate(
      '''
    UPDATE users 
    SET balance = balance + ? 
    WHERE id = ?
  ''',
      [amount, userId],
    );
  }

  // 💰 تحديث رصيد المستخدم (خصم أو إضافة)
  Future<void> updateUserBalance(int userId, double amount) async {
    final db = await instance.database;

    await db.rawUpdate(
      '''
      UPDATE users 
      SET balance = balance + ? 
      WHERE id = ?
    ''',
      [amount, userId],
    );

    debugPrint(" تم تحديث الرصيد للمستخدم $userId بمقدار $amount");
  }
}
  // دالة جلب الرصيد
    Future<double> getUserBalance(int userId) async {
      final db = await database;
      final res = await db.query('users', columns: ['balance'], where: 'id = ?', whereArgs: [userId]);
                return res.isNotEmpty ? (res.first['balance'] as double) : 0.0;
        }
       // دالة تحديث الرصيد
    Future<void> updateUserBalance(int userId, double newBalance) async {
      final db = await database;
      await db.update('users', {'balance': newBalance}, where: 'id = ?', whereArgs: [userId]);
            }
       //دالة جلب العمليات الأخيرة
    Future<List<Map<String, dynamic>>> getRecentTransactions(int userId) async {
      final db = await database          
      return await db.query('transactions', where: 'user_id = ?', orderBy: 'date DESC', limit: 5);
                                    
            }
        // دالة جلب كل العمليات
    Future<List<Map<String, dynamic>>> getUserTransactions(int userId) async {
       final db = await database;
      return await db.query('transactions', where: 'user_id = ?', orderBy: 'date DESC');
             }

      // دالة التحقق من وجود عملية (لمنع التكرار)
     Future<bool> isTransactionExists(String txId) async {
       final db = await database;
      final res = await db.query('transactions', where: 'tx_id = ?', whereArgs: [txId]);
       return res.isNotEmpty;
           }

         // دالة استقبال العملا
     Future<void> receiveTokens({required int userId, required double amount, required String txId}) async {
       final db = await database;
        await db.transaction((txn) async {
       await txn.rawUpdate('UPDATE users SET balance = balance + ? WHERE id = ?', [amount, userId]);
        await txn.insert('transactions', {
            'user_id':                           
            'amount': amount,
            'tx_id': txId,
             'type': 'receive',
             'date': DateTime.now().toIso8601String(),                                                                                                                                     
              'is_synced': 0
                });
                 });
               }
                  // دوال التزامن (لخدمة SyncService)
      Future<List<Map<String, dynamic>>> getPendingTransactions() async {
        final db = await database;
        return await db.query('transactions', where: 'is_synced = ?', whereArgs: [0]);
      }
      Future<void> markAsSynced(String txId) async {
        final db = await database;
       await db.update('transactions', {'is_synced': 1}, where: 'tx_id = ?', whereArgs: [txId]);
         }

}