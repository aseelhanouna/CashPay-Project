import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../core/session_manager.dart';
import 'package:flutter/foundation.dart';
import '../security/crypto_helper.dart';

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
      key = base64Url.encode(
        List<int>.generate(32, (_) => Random.secure().nextInt(256)),
      );
      await _secureStorage.write(key: 'db_key', value: key);
    }
    return await openDatabase(
      path,
      version: 2,
      password: key,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

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
        balance REAL DEFAULT 100.0,
        sync_status TEXT DEFAULT 'pending'
      )
    ''');
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tx_id TEXT UNIQUE NOT NULL,
        sender_id INTEGER NOT NULL,
        receiver_id INTEGER,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        status TEXT NOT NULL,
        signature TEXT NOT NULL,
        used INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        sync_status TEXT DEFAULT 'pending',
        timestamp INTEGER,
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

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE transactions RENAME TO transactions_old');
      await db.execute('''
        CREATE TABLE transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tx_id TEXT UNIQUE NOT NULL,
          sender_id INTEGER NOT NULL,
          receiver_id INTEGER,
          amount REAL NOT NULL,
          type TEXT NOT NULL,
          status TEXT NOT NULL,
          signature TEXT NOT NULL,
          used INTEGER DEFAULT 0,
          created_at INTEGER NOT NULL,
          sync_status TEXT DEFAULT 'pending',
          timestamp INTEGER,
          synced_at INTEGER
        )
      ''');
      await db.execute('INSERT INTO transactions SELECT * FROM transactions_old');
      await db.execute('DROP TABLE transactions_old');
      debugPrint("DB upgraded to v2: receiver_id now nullable");
    }
  }

  Future<int> createUser(Map<String, dynamic> user) async {
    final dbClient = await database;
    final existing = await dbClient.query(
      'users',
      where: 'id_number = ?',
      whereArgs: [user['id_number']],
    );
    if (existing.isNotEmpty) {
      throw Exception("رقم الهوية هذا مستخدم مسبقاً");
    }
    return await dbClient.insert(
      'users',
      user,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<Map<String, dynamic>?> login(String idNumber, String password) async {
    final db = await database;
    final result = await db.query(
      'users',
      where: 'id_number = ?',
      whereArgs: [idNumber],
    );
    if (result.isEmpty) return null;
    final user = result.first;
    final salt = user['salt']?.toString() ?? "";
    final hashedPassword =
        sha256.convert(utf8.encode(password + salt)).toString();
    if (hashedPassword != user['password']) return null;
    return {'id': user['id'], 'name': user['name']};
  }

   
   
Future<void> receiveTokens({
  required String txId,
  required int senderId,
  required int receiverId,
  required double amount,
  required String signature,
  required int timestamp,
}) async {
  final db = await database;

  await db.transaction((txn) async {
    
    final existing = await txn.query('transactions', where: 'tx_id = ?', whereArgs: [txId]);
    if (existing.isNotEmpty) throw Exception("الرمز مستخدم مسبقاً");

    
    int count = await txn.rawUpdate(
      'UPDATE users SET balance = balance + ? WHERE id = ?',
      [amount, receiverId],
    );

    
    if (count == 0) throw Exception("فشل تحديث الرصيد للمستخدم رقم $receiverId");

  
    await txn.insert('transactions', {
      'tx_id': txId,
      'sender_id': senderId, 
      'receiver_id': receiverId,
      'amount': amount,
      'type': 'receive', 
      'status': 'completed',
      'signature': signature,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'timestamp': timestamp,
      'sync_status': 'pending',
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
      return (result.first['balance'] as num).toDouble();
    }
    return 100.0;
  }

  Future<List<Map<String, dynamic>>> getRecentTransactions(int userId) async {
    final db = await database;
    return await db.query(
      'transactions',
      where: '(sender_id = ? OR receiver_id = ?) AND status = ?',
      whereArgs: [userId, userId, 'completed'],
      orderBy: 'created_at DESC',
      limit: 20,
    );
  }

  Future<List<Map<String, dynamic>>> getUserTransactions(int userId) async {
  final db = await database;
  return await db.rawQuery('''
    SELECT t.*,
      -- إذا لم يجد اسم المرسل محلياً، يكتب "مرسل (رقم المعرف)"
      IFNULL(sender.name, 'مرسل رقم: ' || t.sender_id) AS sender_name,
      -- إذا لم يجد اسم المستقبل محلياً، يكتب "مستقبل (رقم المعرف)"
      IFNULL(receiver.name, 'مستقبل رقم: ' || t.receiver_id) AS receiver_name
    FROM transactions t
    LEFT JOIN users sender ON sender.id = t.sender_id
    LEFT JOIN users receiver ON receiver.id = t.receiver_id
    WHERE (t.sender_id = ? OR t.receiver_id = ?) 
      AND t.status = 'completed'
    ORDER BY t.created_at DESC
  ''', [userId, userId]);
}


  Future<bool> isTransactionExists(String txId) async {
    final db = await database;
    final result = await db.query(
      'transactions',
      where: 'tx_id = ? AND status = ?',
      whereArgs: [txId, 'completed'],
    );
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
    if (res.isNotEmpty) return res.first['name'] as String;
    return "مستخدم";
  }

  Future<List<Map<String, dynamic>>> getPendingTransactions() async {
    final db = await instance.database;
    return await db.query(
      'transactions',
      where: '(sync_status = ? OR sync_status = ?) AND status = ?',
      whereArgs: ['pending', 'failed', 'completed'],
    );
  }

  Future<int> countRecentTransactions(int userId) async {
    final db = await database;
    final int fiveMinutesAgo = DateTime.now()
        .subtract(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as total
      FROM transactions
      WHERE (sender_id = ? OR receiver_id = ?)
      AND created_at > ?
      AND status = 'completed'
    ''', [userId, userId, fiveMinutesAgo]);
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

  Future<int> topUpBalance(int userId, double amount) async {
    final db = await instance.database;
    return await db.rawUpdate(
      'UPDATE users SET balance = balance + ? WHERE id = ?',
      [amount, userId],
    );
  }

  Future<void> updateUserBalance(int userId, double newBalance) async {
    final db = await instance.database;
    await db.rawUpdate('''
      UPDATE users
      SET balance = ?,
          sync_status = 'pending'
      WHERE id = ?
    ''', [newBalance, userId]);
    debugPrint("تم تحديث الرصيد للمستخدم $userId إلى $newBalance");
  }

 Future<void> updateBalance(int userId, double amount) async {
  final db = await database;

  // استخدام Transaction لضمان دقة البيانات
  await db.transaction((txn) async {
    // 1. جلب الرصيد الحالي داخل الترانزاكشن
    final List<Map<String, dynamic>> res = await txn.query(
      'users',
      columns: ['balance'],
      where: 'id = ?',
      whereArgs: [userId],
    );

    if (res.isEmpty) return;

    double current = (res.first['balance'] as num).toDouble();

    // 2. التحقق: إذا كان المبلغ المطلوب خصمه (amount سالب) أكبر من الرصيد المتوفر
    if (amount < 0 && (current + amount) < 0) {
      throw Exception("عذراً، رصيدك الحالي ($current ₪) لا يكفي");
    }

    // 3. التحديث إذا نجح الفحص
    await txn.rawUpdate(
      '''
      UPDATE users
      SET balance = balance + ?,
          sync_status = 'pending'
      WHERE id = ?
      ''',
      [amount, userId],
    );
  });
}


  Future<void> saveOutgoingTransaction({
    required String txId,
    required int senderId,
    required double amount,
    required String signature,
    required int timestamp,
  }) async {
    final db = await database;
    await db.insert(
      'transactions',
      {
        'tx_id': txId,
        'sender_id': senderId,
        'receiver_id': null,
        'amount': amount,
        'signature': signature,
        'timestamp': timestamp,
        'type': 'outgoing',
        'status': 'pending',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'sync_status': 'pending',
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    debugPrint("Outgoing transaction saved: $txId");
  }
Future<void> saveCompletedOutgoingTransaction({
  required String txId,
  required int senderId,
  required double amount,
  required String signature,
  required int timestamp,
}) async {
  final db = await database;

  await db.insert(
    'transactions',
    {
      'tx_id': txId,
      'sender_id': senderId,
      'receiver_id': null,
      'amount': amount,
      'signature': signature,
      'timestamp': timestamp,
      'type': 'transfer',
      'status': 'completed',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'sync_status': 'pending',
    },
  );
}
Future<void> addTransaction({
  required int senderId,
  required int receiverId,
  required double amount,
  required String type,
}) async {
  final db = await database;

  await db.insert('transactions', {
    'sender_id': senderId,    
    'receiver_id': receiverId,
    'amount': amount,
    'type': type,
    'tx_id': DateTime.now().millisecondsSinceEpoch.toString(), 
    'status': 'completed', 
    'signature': 'manual',
    'created_at': DateTime.now().millisecondsSinceEpoch, 
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  });
}

}