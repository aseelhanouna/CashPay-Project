import 'package:flutter/material.dart';
import '../data/database_helper.dart';

class HistoryPage extends StatefulWidget {
  final int userId;

  const HistoryPage({super.key, required this.userId});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> allTx = [];
  List<Map<String, dynamic>> filteredTx = [];
  bool loading = true;

  final TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DatabaseHelper.instance
        .getUserTransactions(widget.userId);

    setState(() {
      allTx = data;
      filteredTx = data;
      loading = false;
    });
  }

  void _search(String value) {
    setState(() {
      filteredTx = allTx.where((tx) {
        final sender = (tx['sender_name'] ?? "").toString().toLowerCase();
        final receiver = (tx['receiver_name'] ?? "").toString().toLowerCase();
        final amount = tx['amount'].toString();

        return sender.contains(value.toLowerCase()) ||
            receiver.contains(value.toLowerCase()) ||
            amount.contains(value);
      }).toList();
    });
  }

  String formatDate(int time) {
    final d = DateTime.fromMillisecondsSinceEpoch(time);
    return "${d.day}/${d.month}/${d.year} - "
        "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF001F3F);

    return Scaffold(
      appBar: AppBar(
        title: const Text("سجل العمليات"),
        backgroundColor: primaryColor,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 🔍 Search
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: TextField(
                    controller: searchController,
                    onChanged: _search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: "ابحث بالاسم أو المبلغ",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                Expanded(
                  child: ListView.builder(
                    itemCount: filteredTx.length,
                    itemBuilder: (context, index) {
                      final tx = filteredTx[index];

                      final isSent =
                          tx['sender_id'] == widget.userId;

                      final sender =
                          tx['sender_name'] ?? "مستخدم";
                      final receiver =
                          tx['receiver_name'] ?? "مستخدم";

                      return Card(
                        margin: const EdgeInsets.all(8),
                        color: isSent
                            ? Colors.red.shade50
                            : Colors.green.shade50,
                        child: ListTile(
                          leading: Icon(
                            isSent
                                ? Icons.call_made
                                : Icons.call_received,
                            color:
                                isSent ? Colors.red : Colors.green,
                          ),

                          title: Text(
                            isSent
                                ? "أرسلت إلى: $receiver"
                                : "استلمت من: $sender",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold),
                          ),

                          subtitle: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(formatDate(tx['created_at'])),
                              Text("ID: ${tx['tx_id']}"),
                            ],
                          ),

                          trailing: Text(
                            "${isSent ? '-' : '+'}${tx['amount']} ₪",
                            style: TextStyle(
                              color: isSent
                                  ? Colors.red
                                  : Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}