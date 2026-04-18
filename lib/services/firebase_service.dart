import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FirebaseService {

  // 1. دالة إرسال العمليات
  static Future<void> sendTransaction(Map<String, dynamic> tx) async {
    await FirebaseFirestore.instance
        .collection("transactions")
        .doc(tx["tx_id"])
        .set(tx);
  }

  // 2. إنشاء سجل المستخدم برصيد 100 شيكل
  static Future<void> createUserInFirestore({
    required int userId,
    required String name,
    required String phone,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection("users")
          .doc(userId.toString())
          .set({
        'id': userId,
        'name': name,
        'phone': phone,
        'balance': 100.0, // 👈 القيمة الابتدائية
        'created_at': FieldValue.serverTimestamp(),
        'isBlocked': false,
      });
      debugPrint("✅ User created on Firestore with 100 ILS");
    } catch (e) {
      debugPrint("❌ Firestore Create Error: $e");
    }
  }
}