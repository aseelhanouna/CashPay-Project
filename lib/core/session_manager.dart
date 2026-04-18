import 'package:shared_preferences/shared_preferences.dart';

class SessionManager {
  static const String _lastOnlineKey = "last_online";
  static const String _fraudCountKey = "fraud_count";
  static const String _blockedUntilKey = "blocked_until";

  // 1. تحديث وقت الاتصال (عند نجاح أي مزامنة مع السيرفر)
  static Future<void> updateLastOnline() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastOnlineKey, DateTime.now().millisecondsSinceEpoch);
  }

  // 2. فحص هل انتهت مدة الـ 48 ساعة (Offline Limit)
  static Future<bool> isOfflineExpired() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_lastOnlineKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    const limit = 48 * 60 * 60 * 1000;
    return (now - last) > limit;
  }

  // 3. منطق الحظر عند اكتشاف تلاعب
  static Future<void> applyFraudBlock() async {
    final prefs = await SharedPreferences.getInstance();
    
    // زيادة عدد محاولات الاحتيال المخزنة
    int currentCount = (prefs.getInt(_fraudCountKey) ?? 0) + 1;
    await prefs.setInt(_fraudCountKey, currentCount);

    // حساب مدة الحظر بناءً على العدد
    int duration;
   if (currentCount == 1) {
      duration = 5 * 60 * 1000;       // 5 دقائق
    } else if (currentCount == 2) {
      duration = 15 * 60 * 1000;      // 15 دقيقة
    } else if (currentCount == 3) {
      duration = 60 * 60 * 1000;      // ساعة
    } else {
      duration = 24 * 60 * 60 * 1000; // 24 ساعة
    }

    int blockUntil = DateTime.now().millisecondsSinceEpoch + duration;
    await prefs.setInt(_blockedUntilKey, blockUntil);
  }

  // 4. التحقق هل المستخدم محظور حالياً؟
  static Future<bool> isBlocked() async {
    final prefs = await SharedPreferences.getInstance();
    final blockedUntil = prefs.getInt(_blockedUntilKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    // محظور إذا كان الوقت الحالي أقل من وقت نهاية الحظر
    // أو إذا انتهت مدة الـ 48 ساعة أوفلاين
    return (now < blockedUntil) || await isOfflineExpired();
  }

  // 5. معرفة الوقت المتبقي لفك الحظر (بالثواني)
  static Future<int> getRemainingTime() async {
    final prefs = await SharedPreferences.getInstance();
    final blockedUntil = prefs.getInt(_blockedUntilKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    int diff = blockedUntil - now;
    return diff > 0 ? (diff / 1000).round() : 0;
  }
  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('user_id'); 
  }
}