import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:crypto/crypto.dart';
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
  // SIGNATURE
  // =========================
  String generateSignature(String data, int userId) {
    final secretKey = "CP_CORE_${userId}_X7!2026";
    final key = utf8.encode(secretKey);
    final bytes = utf8.encode(data);
    final hmac = Hmac(sha256, key);
    return hmac.convert(bytes).toString();
  }

  String simpleSign(String data, int userId) {
    final secret = "CP_CORE_${userId}_X7!2026";
    final key = utf8.encode(secret);
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(data)).toString();
  }

  // =========================
  // ON DETECT
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
      // 1. فحص الحظر
      if (await SessionManager.isBlocked()) {
        int seconds = ((await SessionManager.getRemainingTime()) / 1000).round();
        throw Exception("🚨 التطبيق محظور ($seconds ثانية متبقية)");
      }

      // 2. تحليل البيانات
      final data = jsonDecode(raw);
      final String txId = data['tx_id']?.toString() ?? '';
      final int senderId = (num.tryParse(data['sender_id']?.toString() ?? '') ?? 0).toInt();
      final int receiverId = (num.tryParse(data['receiver_id']?.toString() ?? '') ?? 0).toInt();
      final double amount = (num.tryParse(data['amount']?.toString() ?? '') ?? 0.0).toDouble();
      final String formattedAmount = amount.toStringAsFixed(2);
      final int timestamp = (num.tryParse(data['timestamp']?.toString() ?? '') ?? 0).toInt();
      final String signature = data['signature']?.toString() ?? '';

      // 3. التحققات المنطقية
      if (txId.isEmpty || senderId <= 0 || amount <= 0 || signature.isEmpty) {
        throw Exception("بيانات الرمز غير مكتملة");
      }

      if (amount > 1000) throw Exception("مبلغ غير مسموح");

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - timestamp > 5 * 60 * 1000) throw Exception("QR منتهي الصلاحية");

      final exists = await DatabaseHelper.instance.isTransactionExists(txId);
      if (exists) throw Exception("تم استخدام هذا الرمز مسبقاً");

      // 4. التحقق من التوقيع
      final rawData = "$txId|$senderId|$receiverId|$formattedAmount|$timestamp";
      final expected = CryptoHelper.sign(rawData, senderId);

      if (expected != signature) {
        print("Expected: $expected");
        print("Found: $signature");
        throw Exception("تحذير: الرمز غير موثوق (تلاعب بالبيانات)");
      }

      // 5. تأكيد المستخدم
      await _controller.stop();
      final confirmed = await _confirmDialog(senderId: senderId, amount: amount);

      if (!confirmed) {
        await _controller.start();
        return;
      }

      // 6. التنفيذ النهائي
      await DatabaseHelper.instance.receiveTokens(
        txId: txId,
        senderId: senderId,
        receiverId: widget.receiverId,
        amount: amount,
        signature: signature,
        timestamp: timestamp,
      );

      SyncService.syncTransactions(widget.receiverId);
      _showSuccess(amount);

      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) Navigator.pop(context);
      });

    } catch (e) {
      _handleError(e.toString().replaceFirst("Exception: ", ""));
      await _controller.start();
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  // =========================
  // CONFIRM DIALOG
  // =========================
  Future<bool> _confirmDialog({required int senderId, required double amount}) async {
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
  // HELPERS
  // =========================
  void _handleError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(double amount) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("تم استلام $amount بنجاح"),
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
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error, child) {
                return Center(
                  child: Text(
                    'خطأ في الكاميرا: ${error.errorCode}',
                    style: const TextStyle(color: Colors.white),
                  ),
                );
              },
            ),
          ),
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

  // =========================
  // LIFECYCLE
  // =========================
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
