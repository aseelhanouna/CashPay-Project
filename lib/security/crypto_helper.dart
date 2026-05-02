import 'dart:convert';
import 'package:crypto/crypto.dart';

class CryptoHelper {

  // =========================
  // SIGN DATA (HMAC SHA256)
  // =========================
  static String sign(String data, int userId) {
     
    final secret = "CP_CORE_${userId}_X7!2026";

    final key = utf8.encode(secret);
    final bytes = utf8.encode(data);

    final hmac = Hmac(sha256, key);
    return hmac.convert(bytes).toString();
  }

  // =========================
  //  VERIFY SIGNATURE
  // =========================
 
  static bool verify(String data, String signature, int userId) {
    return sign(data, userId) == signature;
  }

  // =========================
  // BUILD RAW DATA
  // =========================
  static String buildRawData({
    required String txId,
    required int senderId,
    required int receiverId,
    required double amount,
    required int timestamp,
  }) {
   
    final formattedAmount = amount.toStringAsFixed(2);
    return "$txId|$senderId|$receiverId|$formattedAmount|$timestamp";
  }
}
