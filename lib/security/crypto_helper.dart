import 'dart:convert';
import 'package:crypto/crypto.dart';

class CryptoHelper {

  // =========================
  // 🔐 SIGN DATA (HMAC SHA256)
  // =========================
  static String sign(String data) {
    const secret = "CP_CORE_GLOBAL_SECRET_2026";

    final key = utf8.encode(secret);
    final bytes = utf8.encode(data);

    final hmac = Hmac(sha256, key);
    return hmac.convert(bytes).toString();
  }

  // =========================
  // 🔍 VERIFY SIGNATURE
  // =========================
  static bool verify(String data, String signature) {
    return sign(data) == signature;
  }

  // =========================
  // 📦 BUILD RAW DATA
  // =========================
  static String buildRawData({
    required String txId,
    required int senderId,
    required int receiverId,
    required double amount,
    required int timestamp,
  }) {
    return "$txId|$senderId|$receiverId|$amount|$timestamp";
  }
}