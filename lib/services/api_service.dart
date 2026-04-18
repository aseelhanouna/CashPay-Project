import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class ApiService {
  static const String baseUrl = "https://your-server.com/api";

  // 🔐 إرسال عملية
  static Future<bool> sendTransaction(Map<String, dynamic> tx) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/transaction"),
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode(tx),
      );

      if (response.statusCode == 200) {
        debugPrint("📡 Synced: $tx");
        return true;
      } else {
        debugPrint("❌ Server error: ${response.statusCode}");
        return false;
      }

    } catch (e) {
      debugPrint("❌ Network error: $e");
      return false;
    }
  }
  static Future<bool> receiveTransaction(
    Map<String, dynamic> tx) async {

  try {
    final response = await http.post(
      Uri.parse("$baseUrl/receive"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(tx),
    );

    return response.statusCode == 200;

  } catch (e) {
    return false;
  }
}

}