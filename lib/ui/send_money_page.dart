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
    // 2. استدعاء الدالة عند التشغيل
    _loadBalance();
  }

  // =========================
  // DIALOG
  // =========================
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("حدث خطأ"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("حسناً"),
          ),
        ],
      ),
    );
  }

  // =========================
  //  GENERATE QR
  // =========================
  Future<void> _generateQR() async {
    try {
      if (await SessionManager.isBlocked()) {
        int seconds = (await SessionManager.getRemainingTime() / 1000).round();
        throw Exception("التطبيق محظور ($seconds ثانية متبقية)");
      }

      final amount = double.tryParse(_amountController.text);
      if (amount == null || amount <= 0) {
        throw Exception("الرجاء إدخال مبلغ صحيح.");
      }
final String formattedAmount = amount.toStringAsFixed(2);


      final String txId = "TX${DateTime.now().millisecondsSinceEpoch}"; 
    final int senderId = widget.userId;
    final int timestamp = DateTime.now().millisecondsSinceEpoch;

    
    final String rawData = "$txId|$senderId|. $formattedAmount|$timestamp";

    final String signature = CryptoHelper.sign(rawData, senderId);

   
    final qrPayload = {
      'tx_id': txId,
      'sender_id': senderId,
      'amount': amount,
      'timestamp': timestamp,
      'signature': signature,
    };

    setState(() {
      _qrData = jsonEncode(qrPayload);
    });
  } catch (e) {
    rethrow;
  }
}

  Future<void> _loadBalance() async {
    int? myId = await SessionManager.getUserId();

    if (myId != null) {
      double balance = await DatabaseHelper.instance.getUserBalance(myId);
      if (mounted) {
        setState(() {
          currentBalance = balance;
        });
      }
     
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("إرسال الأموال")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
            color: Colors.blue.shade50,
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet, color: Colors.blue),
              title: const Text("رصيدك الحالي"),
              trailing: Text(
                "${currentBalance.toStringAsFixed(2)} شيكل", 
                style: const TextStyle(
                  fontSize: 20, 
                  fontWeight: FontWeight.bold, 
                  color: Colors.blueGrey
                ),
              ),
            ),
          ),
            // =========================
            // 🖼️ QR DISPLAY
            // =========================
            if (_qrData != null)
              QrImageView(data: _qrData!, version: QrVersions.auto, size: 200.0)
            else
              const Icon(Icons.qr_code_scanner, size: 150, color: Colors.grey),

            const SizedBox(height: 40),

            // =========================
            // 💰 AMOUNT INPUT
            // =========================
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: "المبلغ",
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            // =========================
            // 🚀 GENERATE BUTTON
            // =========================
            ElevatedButton.icon(
              icon: const Icon(Icons.qr_code_2),
              label: const Text("إنشاء رمز QR"),
              onPressed: () async {
                try {
                  await _generateQR();
                } catch (e) {
                  _showErrorDialog(
                    e.toString().replaceFirst("Exception: ", ""),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
