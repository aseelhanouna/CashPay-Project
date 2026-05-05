import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter/services.dart';
import '../sync/sync_service.dart';
import '../data/database_helper.dart';
import '../core/session_manager.dart';
import '../security/crypto_helper.dart';

class ScanMoneyPage extends StatefulWidget {
  final int receiverId;
  const ScanMoneyPage({super.key, required this.receiverId});

  @override
  State<ScanMoneyPage> createState() => _ScanMoneyPageState();
}

class _ScanMoneyPageState extends State<ScanMoneyPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  bool isProcessing = false;

  // =========================
  // MAIN DETECT HANDLER
  // =========================
  void _onDetect(BarcodeCapture capture) async {
    if (capture.barcodes.isEmpty || isProcessing) return;

    final raw = capture.barcodes.first.rawValue;
    if (raw == null) {
      _handleError("QR غير صالح");
      return;
    }

    setState(() => isProcessing = true);

    try {
      print("🔍 بدأ الفحص");

      //  نوقف الكاميرا بأمان
      if (_controller.value.isRunning) {
        await _controller.stop();
      }

      // =========================
      // TIMEOUT WRAPPER
      // =========================
      await Future.any([
        _processQR(raw),
        Future.delayed(const Duration(seconds: 8), () {
          throw Exception("انتهى الوقت، حاول مرة أخرى");
        })
      ]);
    } catch (e) {
      _handleError(e.toString().replaceFirst("Exception: ", ""));
    } finally {
      
      if (mounted) {
        setState(() => isProcessing = false);
        await _controller.start();
      }
    }
  }

  // =========================
  // PROCESS QR
  // =========================
  Future<void> _processQR(String raw) async {
    print("📦 parsing");

    // 1. فحص الحظر
    if (await SessionManager.isBlocked()) {
      int seconds =
          ((await SessionManager.getRemainingTime()) / 1000).round();
      throw Exception("🚨 التطبيق محظور ($seconds ثانية)");
    }

    // 2. تحليل البيانات
    final data = jsonDecode(raw);

    final String txId = data['tx_id'] ?? '';
    final int senderId =
        int.tryParse(data['sender_id'].toString()) ?? 0;
    final int receiverId =
        int.tryParse(data['receiver_id'].toString()) ?? 0;
    final double amount =
        double.tryParse(data['amount'].toString()) ?? 0.0;
    final int timestamp =
        int.tryParse(data['timestamp'].toString()) ?? 0;
    final String signature = data['signature'] ?? '';

    print("📊 data جاهزة");

    if (txId.isEmpty || senderId <= 0 || amount <= 0) {
      throw Exception("بيانات ناقصة");
    }

    if (amount > 50) {
      throw Exception("المبلغ كبير");
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - timestamp > 5 * 60 * 1000) {
      throw Exception("QR منتهي");
    }

    final exists =
        await DatabaseHelper.instance.isTransactionExists(txId);
    if (exists) {
      throw Exception("تم استخدام الرمز");
    }

    // 3. التوقيع
     final amountStr = amount.toStringAsFixed(2);

    final rawData =
        "$txId|$senderId|$amountStr|$timestamp";

    final expected = CryptoHelper.sign(rawData, senderId);

    if (expected != signature) {
      throw Exception("تم التلاعب بالبيانات");
    }

    print("🔐 التوقيع صحيح");

    // 4. تأكيد
    final confirmed =
        await _confirmDialog(senderId: senderId, amount: amount);

    if (!confirmed) {
      throw Exception("تم الإلغاء");
    }

    print("✅ تم التأكيد");

    // 5. تنفيذ مع timeout
    await DatabaseHelper.instance
        .receiveTokens(
          txId: txId,
          senderId: senderId,
          receiverId: widget.receiverId,
          amount: amount,
          signature: signature,
          timestamp: timestamp,
        )
        .timeout(const Duration(seconds: 5));

    print("💰 تم التحويل");

    SyncService.syncTransactions(widget.receiverId);

    _showSuccess(amount);

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) Navigator.pop(context);
    });
  }

  // =========================
  // DIALOG
  // =========================
  Future<bool> _confirmDialog(
      {required int senderId, required double amount}) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text("تأكيد"),
            content: Text("استلام $amount من $senderId"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("إلغاء"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("تأكيد"),
              ),
            ],
          ),
        ) ??
        false;
  }

  // =========================
  // UI HELPERS
  // =========================
  void _handleError(String message) {
    if (!mounted) return;
    print("❌ ERROR: $message");

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(double amount) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("تم استلام $amount"),
        backgroundColor: Colors.green,
      ),
    );
  }

  // =========================
  // BUILD
  // =========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white),
              ),
            ),
          ),
          if (isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}