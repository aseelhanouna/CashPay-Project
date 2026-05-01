import 'package:myapp/data/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/session_manager.dart';  
import 'package:firebase_core/firebase_core.dart';   
import 'package:myapp/ui/dashboard_page.dart';
import 'dart:convert';         
import 'package:crypto/crypto.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); 
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
    // تأكدي أن هذه الدالة موجودة في SessionManager
    SessionManager.updateLastOnline(); 
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(milliseconds: 1200));
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    bool isBlocked = prefs.getBool('is_blocked') ?? false;
    if (isBlocked && mounted) {
      // تأكدي من وجود BlockedPage في مشروعك أو استبدالها بصفحة أخرى
      return; 
    }

    bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    int userId = prefs.getInt('user_id') ?? 0;

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
      body: Center(child: Icon(Icons.account_balance_wallet, size: 100, color: Colors.white)),
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

  void _showSnackBar(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final String idInput = _idController.text.trim();
      final String passwordInput = _passController.text;

      final user = await DatabaseHelper.instance.login(idInput, passwordInput);

      if (user != null) {
        await _completeLogin(user['id'], user['name']);
      } else {
        final cloudDoc = await FirebaseFirestore.instance.collection('users').doc(idInput).get();
        if (cloudDoc.exists) {
          final cloudData = cloudDoc.data()!;
          String inputHash = sha256.convert(utf8.encode(passwordInput + idInput)).toString();

          if (inputHash == cloudData['password']) {
            await DatabaseHelper.instance.createUser({
              'id_number': idInput,
              'name': cloudData['name'],
              'password': cloudData['password'],
              'salt': idInput, 
              'balance': (cloudData['balance'] as num).toDouble(),
              'birthDate': cloudData['birthDate'] ?? '',
            });
            await _completeLogin(int.parse(idInput), cloudData['name']);
          } else {
            _showSnackBar("كلمة المرور غير صحيحة", Colors.orange);
          }
        } else {
          _showSnackBar("بيانات الدخول غير صحيحة أو الحساب غير موجود", Colors.orange);
        }
      }
    } catch (e) {
      _showSnackBar("حدث خطأ في الاتصال", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _completeLogin(int userId, String userName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    await prefs.setInt('user_id', userId);
    await prefs.setString('userName', userName);
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => DashboardPage(userId: userId)), (route) => false);
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
              _buildField(c: _idController, label: "رقم الهوية", icon: Icons.badge),
              const SizedBox(height: 20),
              _buildField(c: _passController, label: "كلمة المرور", icon: Icons.lock, isPass: true),
              const SizedBox(height: 30),
              _isLoading 
                ? const CircularProgressIndicator() 
                : ElevatedButton(
                    onPressed: _handleLogin,
                    child: const Text("دخول"),
                  ),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage())),
                child: const Text("لا تملك حساباً؟ سجل الآن"),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({required TextEditingController c, required String label, required IconData icon, bool isPass = false}) {
    return TextFormField(
      controller: c,
      obscureText: isPass && _hidePass,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: isPass ? IconButton(onPressed: () => setState(() => _hidePass = !_hidePass), icon: Icon(_hidePass ? Icons.visibility_off : Icons.visibility)) : null,
      ),
      validator: (v) => v!.isEmpty ? "مطلوب" : null,
    );
  }
}

// ---------------- RegisterPage ----------------
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  final _passController = TextEditingController();
  final _dateController = TextEditingController();
  bool _isLoading = false;

  void _showSnackBar(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dateController.text.isEmpty) {
      _showSnackBar("يرجى اختيار تاريخ الميلاد", Colors.orange);
      return;
    }

    setState(() => _isLoading = true);
    String nationalId = _idController.text.trim();
    String password = _passController.text;

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(nationalId).get();
      if (userDoc.exists) throw Exception("رقم الهوية مسجل مسبقاً");

      String hashedPassword = sha256.convert(utf8.encode(password + nationalId)).toString();

      await FirebaseFirestore.instance.collection('users').doc(nationalId).set({
        'id_number': nationalId,
        'name': _nameController.text,
        'password': hashedPassword,
        'birthDate': _dateController.text,
        'balance': 100.0,
        'created_at': FieldValue.serverTimestamp(),
      });

      await DatabaseHelper.instance.createUser({
        'id_number': nationalId,
        'name': _nameController.text,
        'password': hashedPassword,
        'birthDate': _dateController.text,
        'salt': nationalId,
        'balance': 100.0,
      });

      _showSnackBar("تم التسجيل بنجاح", Colors.green);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showSnackBar(e.toString().replaceFirst("Exception: ", ""), Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("إنشاء حساب")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildField(c: _idController, label: "رقم الهوية", icon: Icons.badge),
              _buildField(c: _nameController, label: "الاسم كامل", icon: Icons.person),
              _buildField(c: _passController, label: "كلمة المرور", icon: Icons.lock, isPass: true),
              _buildField(c: _dateController, label: "تاريخ الميلاد", icon: Icons.calendar_today, readOnly: true, onTap: () async {
                DateTime? picked = await showDatePicker(context: context, initialDate: DateTime(2000), firstDate: DateTime(1950), lastDate: DateTime.now());
                if (picked != null) setState(() => _dateController.text = DateFormat('yyyy-MM-dd').format(picked));
              }),
              const SizedBox(height: 30),
              _isLoading ? const CircularProgressIndicator() : ElevatedButton(onPressed: _handleRegister, child: const Text("تسجيل")),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({required TextEditingController c, required String label, required IconData icon, bool isPass = false, bool readOnly = false, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: TextFormField(
        controller: c,
        obscureText: isPass,
        readOnly: readOnly,
        onTap: onTap,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        validator: (v) => v!.isEmpty ? "مطلوب" : null,
      ),
    );
  }
}
