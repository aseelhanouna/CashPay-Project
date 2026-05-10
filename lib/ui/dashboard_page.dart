import 'package:flutter/material.dart';
import '../data/database_helper.dart';
import 'package:myapp/ui/scan_money_page.dart';
import 'package:myapp/ui/send_money_page.dart';
import 'package:myapp/ui/history_page.dart';
import '../core/session_manager.dart';
import 'package:myapp/sync/sync_service.dart';
import 'package:myapp/main.dart' show LoginPage;
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardPage extends StatefulWidget {
  final int userId;
  const DashboardPage({super.key, required this.userId});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  double _balance = 0.0;
  bool _isLoading = true;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    SyncService.syncTransactions(widget.userId);
    _syncTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        SyncService.syncTransactions(widget.userId);
      }
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

Future<void> _loadUserData() async {
  if (!mounted) return;
  setState(() => _isLoading = true);

  try {
    // 1. جلب الرصيد المحلي أولاً وعرضه فوراً
    double localBalance = await DatabaseHelper.instance.getUserBalance(widget.userId);
    if (mounted) {
      setState(() {
        _balance = localBalance;
        _isLoading = false;
      });
    }

    // 2. محاولة التحديث من السيرفر فقط إذا وجد إنترنت
    DocumentSnapshot userDoc = await FirebaseFirestore.instance
        .collection("users")
        .doc(widget.userId.toString())
        .get(const GetOptions(source: Source.server)); // إجبار الجلب من السيرفر وليس الكاش

    if (userDoc.exists && mounted) {
      double serverBalance = (userDoc.data() as Map<String, dynamic>)['balance']?.toDouble() ?? 100.0;
      
      // لا تحدث القيمة المحلية إلا إذا كان هناك فرق (منع الوميض في الواجهة)
      if (serverBalance != localBalance) {
        setState(() {
          _balance = serverBalance;
        });
        await DatabaseHelper.instance.updateUserBalance(widget.userId, serverBalance);
      }
    }
  } catch (e) {
    debugPrint("أنت تعمل حالياً بالوضع الأوفلاين: يتم عرض الرصيد المحلي.");
    if (mounted) setState(() => _isLoading = false);
  }
}


  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: SessionManager.isBlocked(),
      builder: (context, snapshot) {
        if (snapshot.data == true) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.lock, size: 80),
                  SizedBox(height: 20),
                  Text(
                    "التطبيق مقفل مؤقتًا\nيرجى الاتصال بالإنترنت",
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        return _buildNormalDashboard();
      },
    );
  }

  Widget _buildNormalDashboard() {
    const Color primaryColor = Color(0xFF001F3F);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          "CashPay",
          style: TextStyle(
            color: primaryColor,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF001F3F)),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadUserData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 20),
              _buildBalanceCard(primaryColor),
              const SizedBox(height: 35),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildActionButton(
                    Icons.qr_code_scanner, "مسح QR", primaryColor,
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ScanMoneyPage(receiverId: widget.userId),
                        ),
                      ).then((_) => _loadUserData());
                    },
                  ),
                  _buildActionButton(
                    Icons.qr_code_2, "توليد QR", primaryColor,
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SendMoneyPage(userId: widget.userId),
                        ),
                      ).then((_) => _loadUserData());
                    },
                  ),
                  _buildActionButton(Icons.history, "السجل", primaryColor, () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HistoryPage(userId: widget.userId),
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 40),
              const Text(
                "العمليات الأخيرة",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF001F3F),
                ),
              ),
              const SizedBox(height: 15),
              _buildTransactionsList(primaryColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceCard(Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("الرصيد المتوفر", style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 10),
          _isLoading
              ? const CircularProgressIndicator(color: Colors.white)
              : Text(
                  "\$${_balance.toStringAsFixed(2)}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 8),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildTransactionsList(Color primaryColor) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper.instance.getRecentTransactions(widget.userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(30),
            child: Text("لا توجد عمليات بعد"),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, index) {
            final tx = snapshot.data![index];
            final bool isSent = tx['sender_id'] == widget.userId;
            final DateTime date = DateTime.fromMillisecondsSinceEpoch(tx['created_at'] as int);
            String twoDigits(int n) => n.toString().padLeft(2, '0');
            final dateDisplay = "${twoDigits(date.day)}/${twoDigits(date.month)} - "
                "${twoDigits(date.hour)}:${twoDigits(date.minute)}";
            return Row(
              children: [
                CircleAvatar(
                  backgroundColor: isSent
                      ? Colors.red.withValues(alpha: 0.2)
                      : Colors.green.withValues(alpha: 0.2),
                  child: Icon(
                    isSent ? Icons.call_made : Icons.call_received,
                    color: isSent ? Colors.red : Colors.green,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSent ? "إرسال" : "استلام",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        dateDisplay,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
        Text(
  "${isSent ? '-' : '+'}${tx['amount']} ₪",
  style: TextStyle(
    color: isSent ? Colors.red : Colors.green,
    fontWeight: FontWeight.bold,
  ),
),
                
              ],
            );
          },
        );
      },
    );
  }
} 