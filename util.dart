import 'package:flutter/material.dart';

const navy = Color(0xFF0B1F44);
const navy2 = Color(0xFF1A3F8A);
const gold = Color(0xFFC9A227);
const bg = Color(0xFFF4F6FB);
const okGreen = Color(0xFF1F9D55);
const errRed = Color(0xFFD64545);

String inr(dynamic v) {
  final n = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;
  final s = n.abs().toStringAsFixed(2);
  final parts = s.split('.');
  var i = parts[0];
  if (i.length > 3) {
    var h = i.substring(i.length - 3);
    var r = i.substring(0, i.length - 3);
    final g = <String>[];
    while (r.length > 2) {
      g.insert(0, r.substring(r.length - 2));
      r = r.substring(0, r.length - 2);
    }
    if (r.isNotEmpty) g.insert(0, r);
    i = [...g, h].join(',');
  }
  return '${n < 0 ? '-' : ''}₹$i.${parts[1]}';
}

num numOf(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;
String today() => DateTime.now().toIso8601String().substring(0, 10);

InputDecoration dec(String label, {String? hint, String? prefix}) => InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefix,
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE1E6F0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE1E6F0))),
    );

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(14)});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x140B1F44), blurRadius: 18, offset: Offset(0, 6))],
        ),
        child: child,
      );
}

class Stat extends StatelessWidget {
  final String label;
  final String value;
  const Stat(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: const Border(left: BorderSide(color: gold, width: 4)),
          boxShadow: const [BoxShadow(color: Color(0x120B1F44), blurRadius: 14, offset: Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7690))),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: navy)),
        ]),
      );
}

Color statusColor(String s) {
  if (s == 'Paid' || s == 'Issued' || s == 'Sent') return okGreen;
  if (s == 'Overdue' || s == 'Cancelled' || s == 'Refunded') return errRed;
  if (s == 'Partially Paid') return const Color(0xFFB8860B);
  return const Color(0xFF6B7690);
}

class StatusChip extends StatelessWidget {
  final String s;
  const StatusChip(this.s, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = statusColor(s);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: c.withAlpha(34), borderRadius: BorderRadius.circular(99)),
      child: Text(s, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

PreferredSizeWidget topBar(String title, {List<Widget>? actions}) => AppBar(
      backgroundColor: navy,
      foregroundColor: Colors.white,
      elevation: 0,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      actions: actions,
    );

void toast(BuildContext c, String m, {bool error = false}) {
  ScaffoldMessenger.of(c).hideCurrentSnackBar();
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(
    content: Text(m),
    backgroundColor: error ? errRed : navy,
    behavior: SnackBarBehavior.floating,
  ));
}

Future<bool> confirm(BuildContext c, String msg, {String ok = 'Yes'}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (_) => AlertDialog(
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}
