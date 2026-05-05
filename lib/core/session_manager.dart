import 'package:shared_preferences/shared_preferences.dart';

class SessionManager {
  static const String _lastOnlineKey = "last_online";
  static const String _fraudCountKey = "fraud_count";
  static const String _blockedUntilKey = "blocked_until";
  static const String _userIdKey = "user_id"; // مفتاح معرف المستخدم

  // 1. حفظ بيانات الجلسة عند تسجيل الدخول (هام جداً)
  static Future<void> saveLoginSession(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_userIdKey, userId);
    await updateLastOnline(); // نعتبر وقت الدخول هو آخر ظهور أونلاين
  }

  // 2. تحديث وقت الاتصال (عند نجاح أي مزامنة مع السيرفر)
  static Future<void> updateLastOnline() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastOnlineKey, DateTime.now().millisecondsSinceEpoch);
  }

  // 3. فحص هل انتهت مدة الـ 48 ساعة (Offline Limit)
  static Future<bool> isOfflineExpired() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_lastOnlineKey) ?? 0;
    
    // إذا كان المستخدم جديداً ولم يتصل أبداً، لا نحظره فوراً بل نطلب مزامنة
    if (last == 0) return false; 

    final now = DateTime.now().millisecondsSinceEpoch;
    const limit = 48 * 60 * 60 * 1000; // 48 ساعة بالميلي ثانية
    return (now - last) > limit;
  }

  // 4. منطق الحظر عند اكتشاف تلاعب (مثل خطأ التوقيع الرقمي المتكرر)
  static Future<void> applyFraudBlock() async {
    final prefs = await SharedPreferences.getInstance();

    int currentCount = (prefs.getInt(_fraudCountKey) ?? 0) + 1;
    await prefs.setInt(_fraudCountKey, currentCount);

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

  // 5. التحقق هل المستخدم محظور حالياً؟
  static Future<bool> isBlocked() async {
    final prefs = await SharedPreferences.getInstance();
    final blockedUntil = prefs.getInt(_blockedUntilKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    // محظور إذا كان وقت الحظر لم ينتهِ، أو إذا تجاوز مدة الأوفلاين المسموحة
    bool fraudBlocked = now < blockedUntil;
    bool offlineExpired = await isOfflineExpired();

    return fraudBlocked || offlineExpired;
  }

  // 6. معرفة الوقت المتبقي لفك الحظر (بالثواني)
  static Future<int> getRemainingTime() async {
    final prefs = await SharedPreferences.getInstance();
    final blockedUntil = prefs.getInt(_blockedUntilKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    int diff = blockedUntil - now;
    return diff > 0 ? (diff / 1000).round() : 0;
  }

  // 7. جلب معرف المستخدم الحالي (يستخدم في كل الصفحات)
  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_userIdKey); 
  }

  // 8. تسجيل الخروج ومسح البيانات الحساسة
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    // لا نمسح الـ fraudCount لكي لا يتلاعب المستخدم بالخروج والدخول لفك الحظر
  }
}
