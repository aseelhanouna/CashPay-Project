import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import '../sync/sync_service.dart';
import '../data/database_helper.dart';
import '../core/session_manager.dart';

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
  // 🔐 SIGNATURE
  // =========================
  String generateSignature(String data, int userId) {
    final secretKey = "CP_CORE_${userId}_X7!2026";

    final key = utf8.encode(secretKey);
    final bytes = utf8.encode(data);

    final hmac = Hmac(sha256, key);
    return hmac.convert(bytes).toString();
  }

  // =========================
  // 📷 ON SCAN
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
     
      if (await SessionManager.isBlocked()) {
        int seconds = ((await SessionManager.getRemainingTime()) / 1000).round();
        throw Exception("🚨 التطبيق محظور ($seconds ثانية متبقية)");
      }

     
      final data = jsonDecode(raw);
      final String txId = data['tx_id']?.toString() ?? '';
      final int senderId = (num.tryParse(data['sender_id']?.toString() ?? '') ?? 0).toInt();
      final int receiverId = (num.tryParse(data['receiver_id']?.toString() ?? '') ?? 0).toInt();
      final double amount = (num.tryParse(data['amount']?.toString() ?? '') ?? 0.0).toDouble();
      final int timestamp = (num.tryParse(data['timestamp']?.toString() ?? '') ?? 0).toInt();
      final String signature = data['signature']?.toString() ?? '';

    
      if (txId.isEmpty || senderId <= 0 || amount <= 0 || signature.isEmpty) {
        throw Exception("بيانات الرمز غير مكتملة");
      }
      if (amount > 50) throw Exception("مبلغ غير مسموح");
      if (receiverId != widget.receiverId) throw Exception("هذا الرمز مخصص لمستلم آخر");

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - timestamp > 5 * 60 * 1000) throw Exception("الرمز منتهي الصلاحية");

      final exists = await DatabaseHelper.instance.isTransactionExists(txId);
      if (exists) throw Exception("هذا الرمز تم استخدامه مسبقاً");

      
      final rawData = "$txId|$senderId|$receiverId|$amount|$timestamp";
      final expected = generateSignature(rawData, senderId);
      if (expected != signature) throw Exception("توقيع غير صالح (تلاعب بالبيانات)");

      
      await _controller.stop();
      final confirmed = await _confirmDialog(senderId: senderId, amount: amount);

      if (!confirmed) {
        await _controller.start();
        setState(() => isProcessing = false);
        return;
      }

     
      await DatabaseHelper.instance.receiveTokens(
        txId: txId,
        senderId: senderId,
        receiverId: receiverId,
        amount: amount,
        signature: signature,
        timestamp: timestamp,
      );

      
      SyncService.syncTransactions(widget.receiverId);

      _showSuccess(amount);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.pop(context);
      });

    } catch (e) {
      
      _handleError(e.toString().replaceFirst("Exception: ", ""));
      // إعادة تشغيل الكاميرا في حال الفشل
      await _controller.start(); 
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }
} 
  // =========================
  // 🔐 CONFIRM DIALOG
  // =========================
  Future<bool> _confirmDialog({
    required int senderId,
    required double amount,
  }) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text("تأكيد الاستلام"),
            content: Text("استلام \$${amount.toStringAsFixed(2)} من $senderId"),
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
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (isProcessing)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
        ],
      ),
    );
  }

  // =========================
  // ERROR
  // =========================
  void _handleError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // =========================
  // SUCCESS
  // =========================
  void _showSuccess(double amount) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("تم استلام $amount بنجاح"),
        backgroundColor: Colors.green,
      ),
    );
  }

  // =========================
  // SECURITY
  // =========================
  @override
  void initState() {
    super.initState();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
