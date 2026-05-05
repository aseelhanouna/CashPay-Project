import 'dart:convert';
import 'package:crypto/crypto.dart';

class CryptoHelper {
  // المفتاح السري الثابت للنظام (Secret Salt)
  static const String _systemSalt = "CP_CORE_X7!2026";

  // =========================
  // SIGN DATA (HMAC SHA256)
  // =========================
  static String sign(String data, int userId) {
    // دمج معرف المستخدم مع الملح السري لإنشاء مفتاح فريد لكل مستخدم
    final secretKey = "${_systemSalt}_$userId";
    
    final key = utf8.encode(secretKey);
    final bytes = utf8.encode(data);

    final hmac = Hmac(sha256, key);
    return hmac.convert(bytes).toString();
  }

  // =========================
  // VERIFY SIGNATURE
  // =========================
  static bool verify(String data, String signature, int userId) {
    final expected = sign(data, userId);
    return expected == signature;
  }

  // =========================
  // BUILD RAW DATA (الدالة الموحدة)
  // =========================
  // ملاحظة: تأكد من استخدام هذه الدالة في التوقيع وعند التحقق
  static String buildRawData({
    required String txId,
    required int senderId,
    required String amountStr, // نمرر النص الجاهز للمبلغ لضمان الدقة
    required int timestamp,
  }) {
    // تم اعتماد 4 حقول لضمان التوافق مع ملفات Scan و Send التي أعددناها
    return "${txId.trim()}|$senderId|$amountStr|$timestamp";
  }
}
