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
        int seconds = ((await SessionManager.getRemainingTime()) / 1000)
            .round();
        throw Exception("🚨 التطبيق محظور ($seconds ثانية متبقية)");
      }

      if (await SessionManager.isBlocked()) {
        _handleError("التطبيق في وضع القراءة فقط");
        return;
      }

      final data = jsonDecode(raw);

      final String txId = data['tx_id'] ?? '';

      final int senderId = int.parse(data['sender_id'].toString());
      final int receiverId = int.parse(data['receiver_id'].toString());
      final double amount = double.parse(data['amount'].toString());
      final int timestamp = int.parse(data['timestamp'].toString());
      final String signature = data['signature'] ?? '';

      if (txId.isEmpty || senderId <= 0 || amount <= 0 || signature.isEmpty) {
        throw Exception("QR غير صالح");
      }

      if (amount > 50) {
        throw Exception("مبلغ غير مسموح");
      }

      if (receiverId != widget.receiverId) {
        throw Exception("هذا QR ليس لك");
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - timestamp > 5 * 60 * 1000) {
        throw Exception("QR منتهي");
      }

      final exists = await DatabaseHelper.instance.isTransactionExists(txId);

      if (exists) {
        throw Exception("مستخدم مسبقاً");
      }

      final rawData = "$txId|$senderId|$receiverId|$amount|$timestamp";

      final expected = generateSignature(rawData, senderId);

      if (expected != signature) {
        throw Exception("QR معدل");
      }

      await _controller.stop();

      final confirmed = await _confirmDialog(
        senderId: senderId,
        amount: amount,
      );

      if (!confirmed) {
        await _controller.start();
        setState(() => isProcessing = false);
        return;
      }

      try {
        // 1. الحفظ في قاعدة البيانات المحلية (SQLite) فوراً (Offline-First)
        // الحالة الافتراضية ستكون 'pending' داخل الدالة
        await DatabaseHelper.instance.receiveTokens(
          txId: txId,
          senderId: senderId,
          receiverId: receiverId,
          amount: amount,
          signature: signature,
          timestamp: timestamp,
        );

        // 2. محاولة المزامنة الفورية مع السيرفر في الخلفية
        // لا نستخدم 'await' هنا لكي لا نُعطل المستخدم إذا كان الإنترنت بطيئاً
        SyncService.syncTransactions(widget.receiverId);

        // 3. إظهار النجاح للمستخدم بناءً على الحفظ المحلي
        _showSuccess(amount);

        // العودة للداشبورد بعد النجاح
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context);
        });
      } catch (e) {
        _handleError("فشل حفظ العملية محلياً: ${e.toString()}");
      } finally {
        setState(() => isProcessing = false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar
      (SnackBar(content: Text("فشلت العملية: ${e.toString()}")));
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
