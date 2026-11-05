import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'api.dart';
import 'util.dart';
import 'pdf_doc.dart';

class StatementScreen extends StatefulWidget {
  const StatementScreen({super.key});
  @override
  State<StatementScreen> createState() => _StatementState();
}

class _StatementState extends State<StatementScreen> {
  List rows = [];
  bool loading = true;
  String? err;
  String q = '';
  String status = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await Api.get('docs?types=invoice,quotation,proforma');
      if (!mounted) return;
      setState(() {
        rows = r as List;
        loading = false;
        err = null;
      });
    } catch (e) {
      if (mounted) setState(() {
        loading = false;
        err = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = rows.map((r) => '${r['label']}').toSet().toList()..sort();
    final cur = rows.where((r) {
      final hay = '${r['number']} ${r['cname']} ${r['project']}'.toLowerCase();
      return (q.isEmpty || hay.contains(q.toLowerCase())) && (status.isEmpty || r['label'] == status);
    }).toList();
    final inv = cur.where((r) => r['type'] == 'invoice' && r['status'] == 'issued');
    num sum(String k) => inv.fold<num>(0, (a, r) => a + numOf(r[k]));
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        TextField(decoration: dec('Search customer, bill no, project').copyWith(prefixIcon: const Icon(Icons.search)), onChanged: (v) => setState(() => q = v)),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final s in ['', ...labels])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(s.isEmpty ? 'All' : s), selected: status == s, onSelected: (_) => setState(() => status = s)),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Stat('Billed', inr(sum('total')))),
          const SizedBox(width: 8),
          Expanded(child: Stat('Received', inr(sum('net_paid')))),
          const SizedBox(width: 8),
          Expanded(child: Stat('Due', inr(sum('balance')))),
        ]),
        const SizedBox(height: 12),
        if (loading) const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator())),
        if (err != null) Panel(child: Text(err!, style: const TextStyle(color: errRed))),
        if (!loading && err == null && cur.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(30), child: Text('No bills yet'))),
        for (final r in cur)
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => DocScreen(id: r['id'] as int)));
              load();
            },
            child: Panel(
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r['number'] ?? 'Draft #${r['id']}'}', style: const TextStyle(fontWeight: FontWeight.w700, color: navy)),
                    const SizedBox(height: 2),
                    Text('${r['cname'] ?? ''}', style: const TextStyle(fontSize: 14)),
                    Text('${r['issue_date']}${'${r['project'] ?? ''}'.isNotEmpty && '${r['project']}' != 'null' ? ' · ${r['project']}' : ''}', style: const TextStyle(fontSize: 12, color: Color(0xFF6B7690))),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(inr(r['total']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  if (r['type'] == 'invoice' && numOf(r['balance']) > 0) Text('Due ${inr(r['balance'])}', style: const TextStyle(fontSize: 12, color: errRed)),
                  const SizedBox(height: 4),
                  StatusChip('${r['label']}'),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }
}

class DocScreen extends StatefulWidget {
  final int id;
  const DocScreen({super.key, required this.id});
  @override
  State<DocScreen> createState() => _DocState();
}

class _DocState extends State<DocScreen> {
  Map? d;
  String? err;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await Api.get('docs/${widget.id}');
      if (mounted) setState(() => d = r as Map);
    } catch (e) {
      if (mounted) setState(() => err = '$e');
    }
  }

  Future<void> act(String a) async {
    try {
      if (a == 'delete') {
        final paid = (d!['payments'] as List).isNotEmpty;
        if (!await confirm(context, d!['status'] == 'draft' ? 'Delete this draft?' : 'Permanently delete this bill${paid ? ' and its payments' : ''}? This cannot be undone.', ok: 'Delete')) return;
        await Api.delete('docs/${widget.id}');
        if (mounted) Navigator.pop(context);
        return;
      }
      if (a == 'void' && !await confirm(context, 'Void this document? This cannot be undone.', ok: 'Void')) return;
      await Api.post('docs/${widget.id}/$a');
      if (a == 'duplicate' || a == 'convert') {
        if (mounted) {
          toast(context, 'Draft created - open Statement to issue it');
        }
        return;
      }
      if (mounted) toast(context, 'Done');
      load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Future<void> pdf({bool share = true, bool dn = false}) async {
    setState(() => busy = true);
    try {
      final biz = await Api.get('settings') as Map;
      final bytes = await buildPdf(d!, biz, deliveryNote: dn);
      final name = '${d!['number'] ?? 'draft-${widget.id}'}${dn ? '-delivery' : ''}.pdf';
      if (share) {
        await Printing.sharePdf(bytes: bytes, filename: name);
      } else {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
      }
    } catch (e) {
      if (mounted) toast(context, 'PDF failed: $e', error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> addPayment() async {
    final amt = TextEditingController(text: numOf(d!['balance']) > 0 ? '${d!['balance']}' : '');
    final ref = TextEditingController();
    var method = 'cash';
    var kind = 'payment';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Record payment'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: amt, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: dec('Amount', prefix: '₹ ')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: method,
                decoration: dec('Method'),
                items: ['cash', 'upi', 'bank transfer', 'card', 'other'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (v) => set(() => method = v ?? 'cash'),
              ),
              const SizedBox(height: 10),
              TextField(controller: ref, decoration: dec('Reference (optional)')),
              const SizedBox(height: 6),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('This is a refund'), value: kind == 'refund', onChanged: (v) => set(() => kind = v ? 'refund' : 'payment')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await Api.post('docs/${widget.id}/payments', {'amount': num.tryParse(amt.text) ?? 0, 'method': method, 'ref': ref.text, 'kind': kind});
      if (mounted) toast(context, 'Recorded');
      load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (d == null) {
      return Scaffold(appBar: topBar('Bill'), body: Center(child: err != null ? Text(err!) : const CircularProgressIndicator()));
    }
    final x = d!;
    final isInv = x['type'] == 'invoice';
    final issued = x['status'] == 'issued';
    final tax = numOf(x['tax']);
    Widget row(String a, dynamic b, {bool bold = false, bool neg = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.normal, fontSize: bold ? 16 : 14)),
            Text('${neg ? '- ' : ''}${inr(b)}', style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.normal, fontSize: bold ? 16 : 14)),
          ]),
        );
    return Scaffold(
      appBar: topBar('${x['number'] ?? 'Draft #${x['id']}'}'),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(10),
          color: Colors.white,
          child: Row(children: [
            if (isInv && issued) Expanded(child: FilledButton.icon(onPressed: addPayment, icon: const Icon(Icons.payments_outlined), label: const Text('Payment'), style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(48)))),
            if (x['status'] == 'draft') Expanded(child: FilledButton.icon(onPressed: () => act('issue'), icon: const Icon(Icons.check), label: const Text('Issue'), style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(48)))),
            if (x['status'] == 'sent') Expanded(child: FilledButton(onPressed: () => act('convert'), style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(48)), child: const Text('Convert to invoice'))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton.icon(onPressed: busy ? null : () => pdf(), icon: const Icon(Icons.share), label: const Text('Share PDF'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)))),
          ]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Text('${x['cname'] ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: navy))),
              StatusChip('${x['label']}'),
            ]),
            const SizedBox(height: 4),
            Text('${x['issue_date']}${x['due_date'] != null ? ' · due ${x['due_date']}' : ''}', style: const TextStyle(color: Color(0xFF6B7690))),
            if ('${x['project'] ?? ''}'.isNotEmpty && '${x['project']}' != 'null') Text('${x['project']}'),
          ]),
        ),
        Panel(
          child: Column(children: [
            for (final l in (x['items'] as List))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${l['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      if ('${l['desc'] ?? ''}'.trim().isNotEmpty) Text('${l['desc']}', style: const TextStyle(fontSize: 12, color: Color(0xFF6B7690))),
                      Text('${l['qty']} × ${inr(l['rate'])}${numOf(l['disc']) > 0 ? ' − ${l['disc']}%' : ''} · tax ${l['tax_rate']}%', style: const TextStyle(fontSize: 12, color: Color(0xFF6B7690))),
                    ]),
                  ),
                  Text(inr(l['gross']), style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
              ),
            for (final l in (x['charges'] as List)) row('${l['name']}', l['amount']),
            const Divider(),
            row('Subtotal', x['subtotal']),
            if (numOf(x['disc_total']) > 0) row('Discount', x['disc_total'], neg: true),
            if (numOf(x['coupon_disc']) > 0) row('Coupon ${x['coupon'] ?? ''}', x['coupon_disc'], neg: true),
            if (tax > 0) row(x['tax_mode'] == 'inter' ? 'IGST' : 'CGST + SGST', tax),
            if (numOf(x['round_amt']) != 0) row('Round off', x['round_amt']),
            row('Total', x['total'], bold: true),
            if (isInv && issued) ...[row('Paid', x['net_paid']), row('Balance', x['balance'], bold: true)],
          ]),
        ),
        if (isInv && issued)
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Payments', style: TextStyle(fontWeight: FontWeight.w800, color: navy)),
              if ((x['payments'] as List).isEmpty) const Padding(padding: EdgeInsets.only(top: 6), child: Text('No payments yet')),
              for (final p in (x['payments'] as List))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('${p['kind'] == 'refund' ? '- ' : ''}${inr(p['amount'])}  ·  ${p['method']}'),
                  subtitle: Text('${p['date']}  ${p['receipt'] ?? ''}'),
                ),
            ]),
          ),
        Wrap(spacing: 8, runSpacing: 4, children: [
          OutlinedButton.icon(onPressed: busy ? null : () => pdf(share: false), icon: const Icon(Icons.print_outlined), label: const Text('Print')),
          OutlinedButton.icon(onPressed: busy ? null : () => pdf(dn: true), icon: const Icon(Icons.local_shipping_outlined), label: const Text('Delivery note')),
          OutlinedButton.icon(onPressed: () => act('duplicate'), icon: const Icon(Icons.copy), label: const Text('Duplicate')),
          if (issued || x['status'] == 'sent') OutlinedButton.icon(onPressed: () => act('void'), icon: const Icon(Icons.block), label: const Text('Void')),
          OutlinedButton.icon(onPressed: () => act('delete'), icon: const Icon(Icons.delete_outline, color: errRed), label: const Text('Delete', style: TextStyle(color: errRed))),
        ]),
        const SizedBox(height: 20),
      ]),
    );
  }
}
