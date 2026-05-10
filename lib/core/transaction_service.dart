import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../data/database_helper.dart';
import '../core/session_manager.dart';
import '../security/crypto_helper.dart';

class TransactionService {

  static Future<String> generateTransferToken({
    required int senderId,
    required double amount,
  }) async {

    if (await SessionManager.isBlocked()) {
      throw Exception("التطبيق مقفل مؤقتاً");
    }

    await checkFraudLimit(senderId);

    final db = DatabaseHelper.instance;
    

    final String txId =
        "TX_${senderId}_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}";
    final int timestamp = DateTime.now().millisecondsSinceEpoch;
    final String amountStr = amount.toStringAsFixed(2);

    final String rawData = CryptoHelper.buildRawData(
      txId: txId,
      senderId: senderId,
      amountStr: amountStr,
      timestamp: timestamp,
    );

    final String signature = CryptoHelper.sign(rawData, senderId);

    
    
    debugPrint("Transaction generated: $txId | amount: $amountStr");

    return jsonEncode({
      "tx_id": txId,
      "sender_id": senderId,
      "amount": amountStr,
      "timestamp": timestamp,
      "signature": signature,
    });
  }

  static Future<void> processReceivedToken(
    Map<String, dynamic> tokenData,
    int currentUserId,
  ) async {
    final int timestamp = int.tryParse(tokenData['timestamp'].toString()) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if ((now - timestamp).abs() > 5 * 60 * 1000) {
      throw Exception("انتهت صلاحية الرمز");
    }

    final int senderId = int.tryParse(tokenData['sender_id'].toString()) ?? 0;
    final String amountStr =
        double.parse(tokenData['amount'].toString()).toStringAsFixed(2);
    final String txId = tokenData['tx_id'].toString().trim();
    final String signature = tokenData['signature'].toString().trim();

    if (txId.isEmpty || senderId <= 0) {
      throw Exception("بيانات الرمز ناقصة");
    }

    final String rawData = CryptoHelper.buildRawData(
      txId: txId,
      senderId: senderId,
      amountStr: amountStr,
      timestamp: timestamp,
    );

    if (!CryptoHelper.verify(rawData, signature, senderId)) {
      await SessionManager.applyFraudBlock();
      throw Exception("فشل التحقق من التوقيع");
    }

    try {
      await DatabaseHelper.instance.receiveTokens(
        txId: txId,
        senderId: senderId,
        receiverId: currentUserId,
        amount: double.parse(amountStr),
        signature: signature,
        timestamp: timestamp,
      );
    } on Exception catch (e) {
      debugPrint("receiveTokens failed: $e");
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
      throw Exception("تم حظرك مؤقتاً بسبب نشاط مشبوه");
    }
  }
}