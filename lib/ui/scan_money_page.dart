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

  void _onDetect(BarcodeCapture capture) async {
    if (capture.barcodes.isEmpty || isProcessing) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null) return;

    setState(() => isProcessing = true);
    try {
      if (_controller.value.isRunning) await _controller.stop();

      await Future.any([
        _processQR(raw),
        Future.delayed(const Duration(seconds: 8), () => throw Exception("انتهى الوقت"))
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

  Future<void> _processQR(String raw) async {
    if (await SessionManager.isBlocked()) throw Exception("التطبيق محظور مؤقتاً");

    final data = jsonDecode(raw);
    final String txId = data['tx_id'].toString().trim();
    final int senderId = int.tryParse(data['sender_id'].toString()) ?? 0;
    final String amountStr = data['amount'].toString().trim();
    final int timestamp = int.tryParse(data['timestamp'].toString()) ?? 0;
    final String signature = data['signature'].toString().trim();

    if (txId.isEmpty || senderId <= 0) throw Exception("بيانات الرمز غير مكتملة");

    // 1. التحقق من التوقيع باستخدام الـ Helper الموحد
    final String rawData = "$txId|$senderId|$amountStr|$timestamp";
    final expected = CryptoHelper.sign(rawData, senderId);

    if (expected != signature) throw Exception("تم التلاعب بالبيانات");

    // 2. التحقق من الوقت (5 دقائق)
    final now = DateTime.now().millisecondsSinceEpoch;
    if ((now - timestamp).abs() > 5 * 60 * 1000) throw Exception("انتهت صلاحية الرمز");

    // 3. التحقق من التكرار
    if (await DatabaseHelper.instance.isTransactionExists(txId)) throw Exception("الرمز مستخدم مسبقاً");

    final double amount = double.parse(amountStr);

    final confirmed = await _confirmDialog(senderId: senderId, amount: amount);
    if (!confirmed) throw Exception("تم إلغاء العملية");

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
    if (mounted) Navigator.pop(context);
  }

  Future<bool> _confirmDialog({required int senderId, required double amount}) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("تأكيد الاستلام"),
        content: Text("هل تريد استلام $amount شيكل من $senderId؟"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("إلغاء")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("تأكيد")),
        ],
      ),
    ) ?? false;
  }

  void _handleError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
  }

  void _showSuccess(double amount) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("تم استلام $amount بنجاح"), backgroundColor: Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(child: Container(width: 250, height: 250, decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2)))),
          if (isProcessing) Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }

  @override void dispose() { _controller.dispose(); super.dispose(); }
}
