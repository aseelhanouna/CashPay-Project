import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:myapp/core/session_manager.dart';
import 'package:myapp/core/transaction_service.dart';
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
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    final balance = await DatabaseHelper.instance.getUserBalance(widget.userId);
    if (mounted) setState(() => currentBalance = balance);
  }

  Future<void> _generateQR() async {
  if (_isGenerating) return;

  final amount = double.tryParse(_amountController.text.trim());

  if (amount == null || amount <= 0) {
    _showError("أدخل مبلغاً صحيحاً");
    return;
  }

  if (amount > currentBalance) {
    _showError("رصيدك الحالي غير كافٍ");
    return;
  }

  setState(() => _isGenerating = true);

  try {

    // 🔴 خصم الرصيد الحقيقي من قاعدة البيانات
    await DatabaseHelper.instance.updateBalance(
      widget.userId,
      -amount,
    );

    final String qrJson =
        await TransactionService.generateTransferToken(
      senderId: widget.userId,
      amount: amount,
    );

    // 🔄 إعادة تحميل الرصيد الحقيقي
    await _loadBalance();

    if (mounted) {
      setState(() {
        _qrData = qrJson;
      });
    }

  } catch (e) {

    // إذا فشل الإنشاء رجّع المبلغ
    await DatabaseHelper.instance.updateBalance(
      widget.userId,
      amount,
    );

    _showError(
      e.toString().replaceFirst("Exception: ", ""),
    );

  } finally {
    if (mounted) {
      setState(() => _isGenerating = false);
    }
  }
}

  void _showError(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("خطأ"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("حسناً"),
          ),
        ],
      ),
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
                leading: const Icon(Icons.account_balance_wallet,
                    color: Colors.blue),
                title: const Text("رصيدك الحالي"),
                trailing: Text(
                  "${currentBalance.toStringAsFixed(2)} ₪",
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 30),
            if (_qrData != null)
              Column(
                children: [
                  QrImageView(
                      data: _qrData!, size: 220.0, backgroundColor: Colors.white),
                  const SizedBox(height: 10),
                  const Text(
                    "⚠️ الرمز صالح لمدة 5 دقائق فقط",
                    style: TextStyle(color: Colors.orange, fontSize: 13),
                  ),
                ],
              )
            else
              const Icon(Icons.qr_code_scanner, size: 150, color: Colors.grey),
            const SizedBox(height: 30),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: "المبلغ",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
              ),
            ),
            const SizedBox(height: 20),
            _isGenerating
                ? const CircularProgressIndicator()
                : ElevatedButton.icon(
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text("إنشاء الرمز"),
                    onPressed: _generateQR,
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50)),
                  ),
          ],
        ),
      ),
    );
  }
}