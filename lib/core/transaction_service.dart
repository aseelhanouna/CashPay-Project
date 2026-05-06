import 'dart:convert';
import '../data/database_helper.dart';
import '../core/session_manager.dart';
import '../security/crypto_helper.dart';

class TransactionService {

  static Future<String> generateTransferToken({
    required int senderId,
    required double amount,
  }) async {

    if (await SessionManager.isBlocked()) {
      throw Exception("🚨 التطبيق مقفل مؤقتاً");
    }

    await checkFraudLimit(senderId);

    final db = DatabaseHelper.instance;

    final balance = await db.getUserBalance(senderId);
    if (balance < amount) {
      throw Exception("❌ الرصيد غير كافي");
    }

    final String txId = "TX_${senderId}_${DateTime.now().millisecondsSinceEpoch}";
    final int timestamp = DateTime.now().millisecondsSinceEpoch;
    final String amountStr = amount.toStringAsFixed(2);

    final String rawData = CryptoHelper.buildRawData(
      txId: txId,
      senderId: senderId,
      amountStr: amountStr,
      timestamp: timestamp,
    );

    final String signature = CryptoHelper.sign(rawData, senderId);

    final double newBalance = balance - amount;
    await db.updateUserBalance(senderId, newBalance);

    return jsonEncode({
      "tx_id": txId,
      "sender_id": senderId,
      "amount": amountStr,
      "timestamp": timestamp,
      "signature": signature
    });
  }

  static Future<void> processReceivedToken(Map<String, dynamic> tokenData, int currentUserId) async {
    final db = DatabaseHelper.instance;
    try {
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

  static Future<void> checkFraudLimit(int userId) async {
    final count = await DatabaseHelper.instance.countRecentTransactions(userId);
    if (count >= 5) {
      await DatabaseHelper.instance.logFraud(
        "FRAUD_MULTI_TX_${userId}_${DateTime.now().millisecondsSinceEpoch}",
        "نشاط مكثف في وقت قصير (أكثر من 5 عمليات)",
      );
      await SessionManager.applyFraudBlock();
      throw Exception("🚨 تم حظرك مؤقتاً بسبب نشاط مشبوه (أكثر من 5 عمليات)");
    }
  }
}