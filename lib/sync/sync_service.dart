import 'package:myapp/data/database_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';


class SyncService {
  // أضفنا معرف المستخدم لضمان رفع البيانات للمكان الصحيح
  static Future<void> syncTransactions(int userId) async {
    final db = DatabaseHelper.instance;

    // 1. جلب العمليات المعلقة من SQLite
    final pending = await db.getPendingTransactions();

    if (pending.isEmpty) {
      debugPrint("لا توجد عمليات معلقة للمزامنة.");
      return;
    }

    for (var tx in pending) {
      try {
        // 2. الرفع إلى Firebase
        // تم استخدام هيكلية (Users -> UserId -> Transactions) لتنظيم البيانات بالسيرفر
        await FirebaseFirestore.instance
            .collection("users")
            .doc(userId.toString())
            .collection("transactions")
            .doc(tx["tx_id"]) // نستخدم نفس المعرف لمنع التكرار
            .set({
              ...tx, // رفع كل البيانات الموجودة في Map العملية
              "synced_at": FieldValue.serverTimestamp(), // توثيق وقت الرفع الرسمي من السيرفر
            });

        // 3. التحديث في SQLite
        await db.markAsSynced(tx["tx_id"]);
        debugPrint("تمت مزامنة العملية: ${tx["tx_id"]}");

      } catch (e) {
        debugPrint("خطأ في مزامنة العملية ${tx["tx_id"]}: $e");
        // ملاحظة: لا نغير الحالة لـ failed فوراً، نتركها pending للمحاولة عند توفر إنترنت أفضل
      }
    }
  }
}