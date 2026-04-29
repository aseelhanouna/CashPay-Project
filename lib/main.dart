import 'package:myapp/data/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/session_manager.dart';  
import 'package:firebase_core/firebase_core.dart';   
import 'package:myapp/ui/dashboard_page.dart';


 void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // هذا هو المفتاح الذي يربط التطبيق بالسيرفر
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CashPay',
      theme: ThemeData(
        primaryColor: const Color(0xFF001F3F),
        fontFamily: 'Cairo',
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
          filled: true,
          fillColor: Colors.grey[50],
        ),
      ),
      supportedLocales: const [Locale('ar')],
      locale: const Locale('ar'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SplashScreen(),
    );
  }
}

// ---------------- SplashScreen ----------------
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
    SessionManager.updateLastOnline();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(milliseconds: 1200));
    
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    bool isBlocked = prefs.getBool('is_blocked') ?? false;
    if (isBlocked && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const BlockedPage()),
      );
      return; 
    }

    bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    int userId = prefs.getInt('userId') ?? 0;

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => isLoggedIn ? DashboardPage(userId: userId) : const LoginPage(),
        ),
      );
    }
}

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF001F3F),
      body: Center(
        child: Icon(
          Icons.account_balance_wallet,
          size: 100,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ---------------- LoginPage ----------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _passController = TextEditingController();
  bool _isLoading = false;
  bool _hidePass = true;


  @override
  void dispose() {
    _idController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
  // 1. التحقق من الحقول أولاً
  if (!_formKey.currentState!.validate()) return;
  
  setState(() => _isLoading = true);

  try {
    // 2. محاولة تسجيل الدخول وجلب بيانات المستخدم
    final user = await DatabaseHelper.instance.login(
      _idController.text.trim(),
      _passController.text,
    );

    // 3. إذا نجح تسجيل الدخول
    if (user != null && mounted) {
      final prefs = await SharedPreferences.getInstance();
      final int userId = user['id']; // استخراج الـ ID من قاعدة البيانات

      // حفظ بيانات الجلسة (بما فيها
      await prefs.setBool('isLoggedIn', true);
      await prefs.setInt('user_id', userId); // تأكد من استخدام 'user_id' كما سميناها في SessionManager
      await prefs.setString('userName', user['name']);

      // 4. الانتقال لصفحة اللوحة الرئيسية (Dashboard)
      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => DashboardPage(userId: userId)),
        (route) => false,
      );
    } else {
      // إذا كانت البيانات خاطئة
      _showSnackBar("بيانات الدخول غير صحيحة", Colors.orange);
    }
  } catch (e) {
    debugPrint("Login Error: $e");
    _showSnackBar("حدث خطأ، تأكد من الاتصال", Colors.red);
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("تسجيل الدخول"), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const SizedBox(height: 40),
              _buildField(
                c: _idController,
                label: "رقم الهوية",
                icon: Icons.badge,
                enabled: !_isLoading,
                type: TextInputType.number,
          
                validator: (v) =>
                    (v != null && v.length >= 9) ? null : "رقم غير صحيح",
              ),
              const SizedBox(height: 20),
              _buildField(
                c: _passController,
                label: "كلمة المرور",
                icon: Icons.lock,
                isPass: true,
                hide: _hidePass,
                enabled: !_isLoading,
                onToggle: () => setState(() => _hidePass = !_hidePass),
              ),
              const SizedBox(height: 30),
              _buildButton(text: "دخول", onPressed: _handleLogin),
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const RegisterPage()),
                      ),
                child: const Text("إنشاء حساب جديد"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController c,
    required String label,
    required IconData icon,
    bool isPass = false,
    bool hide = false,
    bool enabled = true,
    VoidCallback? onToggle,
    TextInputType type = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: c,
      obscureText: isPass ? hide : false,
      keyboardType: type,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: isPass
            ? IconButton(
                icon: Icon(hide ? Icons.visibility_off : Icons.visibility),
                onPressed: onToggle,
              )
            : null,
      ),
      validator: validator ?? (v) => (v == null || v.isEmpty) ? "مطلوب" : null,
    );
  }

  Widget _buildButton({required String text, required VoidCallback onPressed}) {
    return ElevatedButton(
      onPressed: _isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF001F3F),
        minimumSize: const Size(double.infinity, 55),
      ),
      child: _isLoading
          ? const CircularProgressIndicator(color: Colors.white)
          : Text(text, style: const TextStyle(color: Colors.white)),
          
    );
  }
}

// ---------------- Register ----------------
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _id = TextEditingController();
  final _date = TextEditingController();
  final _pass = TextEditingController();
  final _pin = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _name.dispose();
    _id.dispose();
    _date.dispose();
    _pass.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    // 4. التحقق من تاريخ الميلاد
    if (_date.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("يرجى اختيار تاريخ الميلاد")),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      // الـ Hashing يتم داخل DatabaseHelper لحماية الـ PIN و Password
      await DatabaseHelper.instance.createUser({
        'id': _id.text.trim(),
        'name': _name.text.trim(),
        'password': _pass.text,
        'pin': _pin.text.trim(),
        'birthDate': _date.text,
      });
      if (mounted) Navigator.pop(context);
      if (!mounted) return;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("إنشاء حساب")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildSimpleField(_name, "الاسم الكامل", Icons.person),
              _buildSimpleField(
                _id,
                "رقم الهوية",
                Icons.badge,
                type: TextInputType.number,
                validator: (v) =>
                    (v != null && v.length >= 9) ? null : "رقم غير صالح",
              ),
              _buildDateField(),
              _buildSimpleField(
                _pass,
                "كلمة المرور",
                Icons.lock,
                isPass: true,
                validator: (v) =>
                    (v != null && v.length >= 6) ? null : "ضعيفة (6 خانات)",
              ),
              _buildSimpleField(
                _pin,
                "PIN (4 أرقام)",
                Icons.dialpad,
                type: TextInputType.number,
                isPass: true,
                validator: (v) =>
                    (v != null && v.length == 4) ? null : "يجب 4 أرقام",
              ),
              const SizedBox(height: 25),
              _buildRegButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextFormField(
        controller: _date,
        readOnly: true,
        onTap: () async {
          DateTime? d = await showDatePicker(
            context: context,
            initialDate: DateTime(2000),
            firstDate: DateTime(1950),
            lastDate: DateTime(2009),
          );
          if (d != null) _date.text = DateFormat('yyyy-MM-dd').format(d);
        },
        decoration: const InputDecoration(
          labelText: "تاريخ الميلاد",
          prefixIcon: Icon(Icons.calendar_today),
        ),
      ),
    );
  }

  Widget _buildSimpleField(
    TextEditingController c,
    String l,
    IconData i, {
    bool isPass = false,
    TextInputType type = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextFormField(
        controller: c,
        obscureText: isPass,
        keyboardType: type,
        decoration: InputDecoration(labelText: l, prefixIcon: Icon(i)),
        validator:
            validator ?? (v) => (v == null || v.isEmpty) ? "مطلوب" : null,
      ),
    );
  }

  Widget _buildRegButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _handleRegister,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF001F3F),
        minimumSize: const Size(double.infinity, 55),
      ),
      child: _isLoading
          ? const CircularProgressIndicator(color: Colors.white)
          : const Text("إنشاء الحساب", style: TextStyle(color: Colors.white)),
    );
  }
}


// صفحة الحظر التي تظهر للمستخدم المشبوه
class BlockedPage extends StatelessWidget {
  const BlockedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // أيقونة قفل باللون الأحمر للتنبيه
              const Icon(
                Icons.report_problem_rounded,
                color: Colors.red,
                size: 100,
              ),
              const SizedBox(height: 30),
              const Text(
                "تم حظر الحساب!",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF001F3F), // لون كحلي متناسق مع تطبيقك
                ),
              ),
              const SizedBox(height: 15),
              const Text(
                "نعتذر منك، لقد تم تجميد حسابك مؤقتاً بسبب رصد عمليات غير اعتيادية متكررة. يرجى مراجعة الدعم الفني لفك الحظر.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 40),
              // زر للخروج من التطبيق
              ElevatedButton(
                onPressed: () {
                  // هنا يمكن إضافة كود لإغلاق التطبيق نهائياً
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF001F3F),
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                ),
                child: const Text("موافق", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
