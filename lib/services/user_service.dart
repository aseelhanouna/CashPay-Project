import 'package:cloud_firestore/cloud_firestore.dart';

class UserService {

  static Future<double> getBalance(int userId) async {
    final doc = await FirebaseFirestore.instance
        .collection("users")
        .doc(userId.toString())
        .get();

    if (!doc.exists) return 0.0;

    return (doc.data()?['balance'] ?? 0.0).toDouble();
  }
}