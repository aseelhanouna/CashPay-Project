import 'package:myapp/data/database_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class SyncService {

  static Future<void> syncAll(int userId) async {
    debugPrint("🔄 بدء عملية المزامنة الشاملة للمستخدم: $userId");
    await syncTransactions(userId);
    await syncUserProfile(userId);
  }

    static Future<void> syncTransactions(int userId) async {
    final db = DatabaseHelper.instance;
    final pending = await db.getPendingTransactions();

    if (pending.isEmpty) return;

    for (var tx in pending) {
      try {
        // استخدمي writeBatch إذا كانت العمليات كثيرة، لكن حالياً الكود سليم
        await FirebaseFirestore.instance
            .collection("transactions") // يفضل وضع كل العمليات في كولكشن موحد للبحث لاحقاً
            .doc(tx["tx_id"])
            .set({
              ...tx,
              "synced_at": FieldValue.serverTimestamp(),
            });

        // تحديث رصيد المستخدم في السيرفر بناءً على هذه العملية
        final bool isSender = tx['sender_id'] == userId;
        final double amount = (tx['amount'] as num).toDouble();
        final double balanceDelta = isSender ? -amount : amount;

        await FirebaseFirestore.instance
            .collection("users")
            .doc(userId.toString())
            .update({
              "balance": FieldValue.increment(balanceDelta),
            });

        await db.markAsSynced(tx["tx_id"]);
      } catch (e) {
        debugPrint("❌ فشل رفع العملية ${tx["tx_id"]}: $e");
        // لا تكمل المزامنة إذا انقطع الإنترنت تماماً
        break; 
      }
    }
  }


  static Future<void> syncUserProfile(int userId) async {
    try {
      final db = DatabaseHelper.instance;
      double currentBalance = await db.getUserBalance(userId);
      String userName = await db.getUserName(userId);

      await FirebaseFirestore.instance
          .collection("users")
          .doc(userId.toString())
          .update({
        "name": userName,
        "last_sync_balance": currentBalance,
        "last_online": FieldValue.serverTimestamp(),
      });

      debugPrint("✅ تم تحديث بيانات الملف الشخصي سحابياً.");
    } catch (e) {
      debugPrint("⚠️ فشل تحديث بيانات الملف الشخصي: $e");
    }
  }
}