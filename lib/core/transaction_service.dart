import '../data/database_helper.dart';
import '../core/session_manager.dart';
import 'dart:convert';

class TransactionService {

  // 🔐 إرسال أموال (توليد البيانات الموقعة)
  static Future<String> generateTransferToken({
    required int senderId,
    required int receiverId,
    required double amount,
  }) async {
    
    // 1) فحص حالة الحظر
    if (await SessionManager.isBlocked()) {
      throw Exception("🚨 التطبيق مقفل - اتصل بالإنترنت");
    }

    // 2) فحص عدد العمليات المتكررة
    await checkFraudLimit(senderId);

    final db = DatabaseHelper.instance;

    // 3) فحص الرصيد محلياً
    final balance = await db.getUserBalance(senderId);
    if (balance < amount) {
      throw Exception("❌ الرصيد غير كافي");
    }

    // ⭐ الإضافة الجديدة: خصم المبلغ من الرصيد فوراً عند توليد التوكن
    // هذا يحول الرصيد النقدي إلى "توكن" معلق داخل الـ QR
    await db.updateUserBalance(senderId, -amount);

    // 4) إنشاء بيانات التوكن
    String txId = "TX_${senderId}_${DateTime.now().millisecondsSinceEpoch}";
    int timestamp = DateTime.now().millisecondsSinceEpoch;

    String signature = db.generateSignature(
      txId: txId,
      senderId: senderId,
      receiverId: receiverId,
      amount: amount,
      timestamp: timestamp,
    );

    // 5) تحويل البيانات لـ JSON
    return jsonEncode({
      "tx_id": txId,
      "sender": senderId,
      "receiver": receiverId,
      "amount": amount,
      "time": timestamp,
      "sig": signature
    });

  }

  // 📥 استقبال أموال
  static Future<void> receiveMoney({
    required Map<String, dynamic> tokenData,
    required int currentUserId,
  }) async {
    
    if (await SessionManager.isBlocked()) {
      throw Exception("🚨 التطبيق مقفل - وضع قراءة فقط");
    }

    if (tokenData['receiver'] != currentUserId) {
      throw Exception("❌ هذا الـ QR ليس موجهاً لك");
    }

    final db = DatabaseHelper.instance;

    try {
      await db.receiveTokens(
        txId: tokenData['tx_id'],
        senderId: tokenData['sender'],
        receiverId: tokenData['receiver'],
        amount: tokenData['amount'],
        signature: tokenData['sig'],
        timestamp: tokenData['time'],
      );
    } catch (e) {
      if (e.toString().contains("توقيع رقمي غير صالح")) {
        await SessionManager.applyFraudBlock();
      }
      rethrow;
    }
  }

  // 🛡️ دالة فحص حدود الاحتيال
  static Future<void> checkFraudLimit(int userId) async {
    final count = await DatabaseHelper.instance.countRecentTransactions(userId);
    
    if (count >= 5) {
      await DatabaseHelper.instance.logFraud("MULTI_TX", "نشاط مكثف في وقت قصير");
      await SessionManager.applyFraudBlock();
      throw Exception("🚨 تم حظرك مؤقتاً بسبب نشاط مشبوه");
    }
  } 

  // 🔍 دالة التحقق من حالة الجلسة
  static Future<void> verifySessionStatus() async {
    if (await SessionManager.isBlocked()) {
      throw Exception("التطبيق مقفل - وضع قراءة فقط");
    }
  }
  Future<void> receiveTokens({
  required String txId,
  required int senderId,
  required int receiverId,
  required double amount,
  required String signature,
  required int timestamp,
}) async {
  final db = await DatabaseHelper.instance.database;

  // استخدام Transaction لضمان تنفيذ كل شيء أو لا شيء
  await db.transaction((txn) async {
    
    // 1. التأكد من أن هذه العملية (txId) لم يتم استقبالها من قبل (منع التكرار)
    final alreadyReceived = await txn.query('transactions', where: 'tx_id = ?', whereArgs: [txId]);
    if (alreadyReceived.isNotEmpty) {
      throw Exception("هذه العملية تم استلامها مسبقاً");
    }

    // 2. التحقق من التوقيع الرقمي (Signature Validation)
    // (هنا تضع منطق التحقق الخاص بك)

    // 3. ⭐ إضافة المبلغ لرصيد المستلم
    await txn.rawUpdate(
      'UPDATE users SET balance = balance + ? WHERE id = ?',
      [amount, receiverId],
    );

    // 4. تسجيل العملية في جدول العمليات للتوثيق
    await txn.insert('transactions', {
      'tx_id': txId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'amount': amount,
      'timestamp': timestamp,
    });
  });
}
} 