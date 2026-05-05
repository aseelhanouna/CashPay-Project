import 'dart:convert';
import '../data/database_helper.dart';
import '../core/session_manager.dart';
import '../security/crypto_helper.dart';

class TransactionService {

  // 🔐 إرسال أموال (توليد البيانات الموقعة لرمز QR)
  static Future<String> generateTransferToken({
    required int senderId,
    required double amount,
  }) async {

    // 1) فحص حالة الحظر
    if (await SessionManager.isBlocked()) {
      throw Exception("🚨 التطبيق مقفل مؤقتاً");
    }

    // 2) فحص عدد العمليات المتكررة (منع الاحتيال)
    await checkFraudLimit(senderId);

    final db = DatabaseHelper.instance;

    // 3) فحص الرصيد محلياً
    final balance = await db.getUserBalance(senderId);
    if (balance < amount) {
      throw Exception("❌ الرصيد غير كافي");
    }

    // 4) إنشاء بيانات العملية وتوحيد التنسيق
    final String txId = "TX_${senderId}_${DateTime.now().millisecondsSinceEpoch}";
    final int timestamp = DateTime.now().millisecondsSinceEpoch;
    final String amountStr = amount.toStringAsFixed(2); // توحيد الكسور

    // استخدام CryptoHelper الموحد لضمان مطابقة الـ Scan
    final String rawData = "$txId|$senderId|$amountStr|$timestamp";
    final String signature = CryptoHelper.sign(rawData, senderId);

    // ⭐ خصم المبلغ من الرصيد فوراً (لأن الـ QR أصبح يمثل المال)
    await db.updateUserBalance(senderId, -amount);

    // 5) تحويل البيانات لـ JSON (بالمفاتيح التي يتوقعها ScanMoneyPage)
    return jsonEncode({
      "tx_id": txId,
      "sender_id": senderId,
      "amount": amountStr,
      "timestamp": timestamp,
      "signature": signature
    });
  }

  // 📥 استقبال أموال (يتم استدعاؤها من الـ Scanner)
  static Future<void> processReceivedToken(Map<String, dynamic> tokenData, int currentUserId) async {
    final db = DatabaseHelper.instance;

    try {
      // التأكد أن المستلم هو المستخدم الحالي (اختياري حسب منطق مشروعك)
      // إذا كان الـ QR مخصص لشخص معين، نفحص tokenData['receiver_id']

      await db.receiveTokens(
        txId: tokenData['tx_id'],
        senderId: int.parse(tokenData['sender_id'].toString()),
        receiverId: currentUserId,
        amount: double.parse(tokenData['amount'].toString()),
        signature: tokenData['signature'],
        timestamp: int.parse(tokenData['timestamp'].toString()),
      );
    } catch (e) {
      if (e.toString().contains("التلاعب") || e.toString().contains("غير صالح")) {
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
      throw Exception("🚨 تم حظرك مؤقتاً بسبب نشاط مشبوه (أكثر من 5 عمليات)");
    }
  }
}
