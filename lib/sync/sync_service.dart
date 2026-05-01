import 'package:myapp/data/database_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class SyncService {
  
  static Future<void> syncAll(int userId) async {
    debugPrint("🔄 بدء عملية المزامنة الشاملة للمستخدم: $userId");
    await syncTransactions(userId);
    await syncUserProfile(userId);
  }

  /// 1. مزامنة العمليات (Transactions)
  static Future<void> syncTransactions(int userId) async {
    final db = DatabaseHelper.instance;

    // جلب العمليات التي لم تُرفع بعد (pending) أو التي فشلت سابقاً (failed)
    final pending = await db.getPendingTransactions();

    if (pending.isEmpty) {
      debugPrint("✅ لا توجد عمليات معلقة للمزامنة.");
      return;
    }

    for (var tx in pending) {
      try {
        // أ. الرفع إلى سجل العمليات الخاص بالمستخدم في Firebase
        await FirebaseFirestore.instance
            .collection("users")
            .doc(userId.toString())
            .collection("transactions")
            .doc(tx["tx_id"]) 
            .set({
              ...tx,
              "synced_at": FieldValue.serverTimestamp(),
            });

        // ب. تحديث الرصيد سحابياً (الزيادة التراكمية) لضمان دقة الرصيد في السحاب
        await FirebaseFirestore.instance
            .collection("users")
            .doc(userId.toString())
            .update({
          "balance": FieldValue.increment(tx['amount']), 
        });

        // ج. تحديث الحالة في SQLite محلياً لعدم تكرار المزامنة
        await db.markAsSynced(tx["tx_id"]);
        debugPrint("Successfully synced transaction: ${tx["tx_id"]}");

      } catch (e) {
        debugPrint("❌ خطأ في مزامنة العملية ${tx["tx_id"]}: $e");
        // نتركها pending للمحاولة في وقت لاحق عند توفر إنترنت
      }
    }
  }

  /// 2. مزامنة بيانات الملف الشخصي (Profile/Balance Sync)
  /// هذه الدالة تضمن أن بيانات المستخدم الأساسية محدثة دائماً في Firebase
  static Future<void> syncUserProfile(int userId) async {
    try {
      final db = DatabaseHelper.instance;
      // جلب رصيد المستخدم الحالي من القاعدة المحلية
      double currentBalance = await db.getUserBalance(userId);
      String userName = await db.getUserName(userId);

      // تحديث البيانات الأساسية في مستند المستخدم الرئيسي
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
