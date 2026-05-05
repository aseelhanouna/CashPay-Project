import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:myapp/core/session_manager.dart';
import 'package:myapp/security/crypto_helper.dart';
import '../data/database_helper.dart';

class SendMoneyPage extends StatefulWidget {
  final int userId;
  const SendMoneyPage({super.key, required this.userId});

  @override
  State<SendMoneyPage> createState() => _SendMoneyPageState();
}

class _SendMoneyPageState extends State<SendMoneyPage> {
  final _amountController = TextEditingController();
  String? _qrData;
  double currentBalance = 0.0;

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    double balance = await DatabaseHelper.instance.getUserBalance(widget.userId);
    if (mounted) setState(() => currentBalance = balance);
  }

  Future<void> _generateQR() async {
    try {
      if (await SessionManager.isBlocked()) throw Exception("التطبيق محظور مؤقتاً");

      final amount = double.tryParse(_amountController.text);
      if (amount == null || amount <= 0) throw Exception("أدخل مبلغاً صحيحاً");
      if (amount > currentBalance) throw Exception("رصيدك الحالي غير كافٍ");

      final String txId = "TX${DateTime.now().millisecondsSinceEpoch}";
      final int timestamp = DateTime.now().millisecondsSinceEpoch;
      final String amountStr = amount.toStringAsFixed(2); // توحيد التنسيق لـ 10.00 مثلاً

      // بناء النص الموحد للتوقيع
      final String rawData = CryptoHelper.buildRawData(
        txId: txId,
        senderId: widget.userId,
        amountStr: amountStr,
        timestamp: timestamp,
      );

      final String signature = CryptoHelper.sign(rawData, widget.userId);

      final qrPayload = {
        'tx_id': txId,
        'sender_id': widget.userId,
        'amount': amountStr,
        'timestamp': timestamp,
        'signature': signature,
      };

      setState(() {
        _qrData = jsonEncode(qrPayload);
      });
    } catch (e) {
      _showErrorDialog(e.toString().replaceFirst("Exception: ", ""));
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("خطأ"), 
        content: Text(message), 
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("حسناً"))]
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("إرسال الأموال")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Card(
              color: Colors.blue.shade50,
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet, color: Colors.blue),
                title: const Text("رصيدك الحالي"),
                trailing: Text("${currentBalance.toStringAsFixed(2)} ₪", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 30),
            if (_qrData != null)
              QrImageView(data: _qrData!, size: 220.0, backgroundColor: Colors.white)
            else
              const Icon(Icons.qr_code_scanner, size: 150, color: Colors.grey),
            const SizedBox(height: 30),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: "المبلغ", border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money)),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.qr_code_2),
              label: const Text("إنشاء الرمز"),
              onPressed: _generateQR,
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            ),
          ],
        ),
      ),
    );
  }
}
