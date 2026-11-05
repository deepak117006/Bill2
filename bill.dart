import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'util.dart';
import 'statement.dart';

class BillScreen extends StatefulWidget {
  const BillScreen({super.key});
  @override
  State<BillScreen> createState() => _BillState();
}

class _BillState extends State<BillScreen> {
  List cust = [], cat = [], pre = [];
  Map biz = {};
  String? loadErr;

  // customer typed on the bill (existing customers auto-fill)
  final fields = {for (final k in ['phone', 'email', 'state', 'org', 'gstin', 'address']) k: TextEditingController()};
  TextEditingController? nameCtl;
  int? customerId;
  String type = 'invoice';
  final project = TextEditingController();
  final items = <Map<String, dynamic>>[];
  final charges = <Map<String, dynamic>>[];
  String discType = 'percent';
  final discVal = TextEditingController();
  final coupon = TextEditingController();
  final notes = TextEditingController();
  final paid = TextEditingController();
  String method = 'cash';
  String taxMode = 'intra';
  bool inclusive = false;
  Map? R;
  String? calcErr;
  Timer? timer;
  int uid = 0;
  bool busy = false;
  TextEditingController? addCtl;

  @override
  void initState() {
    super.initState();
    init();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> init() async {
    try {
      final r = await Future.wait([Api.get('e/customers'), Api.get('e/catalogue'), Api.get('e/presets'), Api.get('settings')]);
      if (!mounted) return;
      setState(() {
        cust = (r[0] as List).where((c) => c['archived'] != 1).toList();
        cat = (r[1] as List).where((c) => c['active'] == 1).toList();
        pre = (r[2] as List).where((c) => c['active'] == 1).toList();
        biz = r[3] as Map;
        loadErr = null;
      });
      recalc();
    } catch (e) {
      if (mounted) setState(() => loadErr = '$e');
    }
  }

  List<Map<String, dynamic>> get sellables => [
        for (final c in cat) {'name': c['name'], 'price': c['price'], 'tax': c['tax_rate'], 'cat': c['category'] ?? '', 'id': c['id'], 'desc': '', 'pkg': false},
        for (final p in pre) {'name': p['name'], 'price': p['price'], 'tax': p['tax_rate'], 'cat': 'Package', 'id': null, 'desc': p['includes'] ?? '', 'pkg': true},
      ];

  Map<String, dynamic> payload() => {
        'type': type,
        'customer_id': customerId,
        'customer': {for (final e in fields.entries) e.key: e.value.text, 'name': nameCtl?.text ?? ''},
        'project': project.text,
        'items': [
          for (final i in items)
            {'name': i['name'], 'desc': i['desc'], 'qty': i['qty'], 'rate': i['rate'], 'disc': i['disc'], 'tax_rate': i['tax'], 'item_id': i['id'], 'cat': i['cat']}
        ],
        'charges': [for (final c in charges) {'name': c['name'], 'amount': c['amount'], 'tax_rate': c['tax']}],
        'disc_type': discType,
        'disc_val': num.tryParse(discVal.text) ?? 0,
        'coupon': coupon.text.trim().toUpperCase(),
        'tax_mode': taxMode,
        'inclusive': inclusive ? 1 : 0,
        'round_off': 1,
        'notes': notes.text,
        'terms': biz['terms'] ?? '',
        'issue_date': today(),
      };

  void recalc() {
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final r = await Api.post('calc', payload());
        if (mounted) setState(() {
          R = r as Map;
          calcErr = null;
        });
      } catch (e) {
        if (mounted) setState(() => calcErr = '$e');
      }
    });
  }

  void autoTax() {
    final mine = '${biz['state'] ?? ''}'.trim().toLowerCase();
    final theirs = fields['state']!.text.trim().toLowerCase();
    if (mine.isNotEmpty && theirs.isNotEmpty) taxMode = mine == theirs ? 'intra' : 'inter';
  }

  void pickCustomer(Map c) {
    customerId = c['id'] as int;
    for (final k in fields.keys) {
      fields[k]!.text = '${c[k] ?? ''}';
    }
    setState(autoTax);
    recalc();
  }

  void addSellable(Map<String, dynamic> s) {
    final nm = (s['pkg'] == true && project.text.trim().isNotEmpty) ? '${project.text.trim()} - ${s['name']}' : '${s['name']}';
    setState(() => items.add({'uid': uid++, 'name': nm, 'desc': s['desc'], 'qty': 1, 'rate': s['price'], 'disc': 0, 'tax': s['tax'], 'id': s['id'], 'cat': s['cat']}));
    recalc();
  }

  void addCustom(String name) {
    setState(() => items.add({'uid': uid++, 'name': name, 'desc': '', 'qty': 1, 'rate': 0, 'disc': 0, 'tax': num.tryParse('${biz['default_tax'] ?? 18}') ?? 18, 'id': null, 'cat': ''}));
    recalc();
  }

  Future<void> save(bool issue) async {
    setState(() => busy = true);
    try {
      final r = await Api.post('docs', payload());
      final id = r['id'] as int;
      if (issue) {
        await Api.post('docs/$id/issue');
        final p = num.tryParse(paid.text) ?? 0;
        if (p > 0 && type == 'invoice') await Api.post('docs/$id/payments', {'amount': p, 'method': method});
      }
      reset();
      init();
      if (!mounted) return;
      toast(context, issue ? 'Bill issued' : 'Draft saved');
      Navigator.push(context, MaterialPageRoute(builder: (_) => DocScreen(id: id)));
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void reset() {
    setState(() {
      for (final c in fields.values) {
        c.clear();
      }
      nameCtl?.clear();
      project.clear();
      discVal.clear();
      coupon.clear();
      notes.clear();
      paid.clear();
      items.clear();
      charges.clear();
      customerId = null;
      R = null;
    });
  }

  Widget numField(String label, dynamic init, void Function(num) set, {String? prefix, Key? key}) => TextFormField(
        key: key,
        initialValue: init is num ? (init == init.roundToDouble() ? init.toInt().toString() : '$init') : '',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: dec(label, prefix: prefix),
        onChanged: (v) {
          set(num.tryParse(v) ?? 0);
          recalc();
        },
      );

  @override
  Widget build(BuildContext context) {
    final r = R;
    return Scaffold(
      backgroundColor: Colors.transparent,
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x260B1F44), blurRadius: 20, offset: Offset(0, -6))]),
        child: SafeArea(
          top: false,
          child: Row(children: [
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Total', style: TextStyle(fontSize: 11, color: Color(0xFF6B7690))),
                Text(inr(r?['total'] ?? 0), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: navy)),
              ]),
            ),
            OutlinedButton(onPressed: busy ? null : () => save(false), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)), child: const Text('Draft')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: busy ? null : () => save(true),
              style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black, minimumSize: const Size(130, 48)),
              child: busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save & Issue', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          if (loadErr != null) Panel(child: Column(children: [Text(loadErr!, style: const TextStyle(color: errRed)), TextButton(onPressed: init, child: const Text('Retry'))])),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                SegmentedButton<String>(
                  segments: const [ButtonSegment(value: 'invoice', label: Text('Invoice')), ButtonSegment(value: 'quotation', label: Text('Quote')), ButtonSegment(value: 'proforma', label: Text('Pro forma'))],
                  selected: {type},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => type = s.first),
                ),
              ]),
              const SizedBox(height: 12),
              Autocomplete<Map>(
                displayStringForOption: (o) => '${o['name']}',
                optionsBuilder: (t) {
                  final q = t.text.trim().toLowerCase();
                  if (q.isEmpty) return const Iterable<Map>.empty();
                  return cust.where((c) => '${c['name']} ${c['phone']}'.toLowerCase().contains(q)).take(6).cast<Map>();
                },
                onSelected: pickCustomer,
                fieldViewBuilder: (ctx, ctl, focus, submit) {
                  nameCtl = ctl;
                  return TextField(
                    controller: ctl,
                    focusNode: focus,
                    textCapitalization: TextCapitalization.words,
                    decoration: dec('Customer name *').copyWith(suffixIcon: customerId != null ? const Icon(Icons.verified, color: okGreen, size: 20) : null),
                    onChanged: (v) {
                      final m = cust.where((c) => '${c['name']}'.toLowerCase() == v.trim().toLowerCase());
                      setState(() => customerId = m.isEmpty ? null : m.first['id'] as int);
                      if (m.isNotEmpty) pickCustomer(m.first as Map);
                    },
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 4),
                child: Text(customerId != null ? 'Existing customer - changes update their record' : ((nameCtl?.text ?? '').isNotEmpty ? 'New customer - saved automatically' : ''),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF6B7690))),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: fields['phone'], keyboardType: TextInputType.phone, decoration: dec('Phone'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: fields['state'], onChanged: (_) {
                  setState(autoTax);
                  recalc();
                }, decoration: dec('State'))),
              ]),
              const SizedBox(height: 8),
              TextField(controller: fields['org'], decoration: dec('College / Company')),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: fields['email'], keyboardType: TextInputType.emailAddress, decoration: dec('Email'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: fields['gstin'], textCapitalization: TextCapitalization.characters, decoration: dec('GSTIN'))),
              ]),
              const SizedBox(height: 8),
              TextField(controller: fields['address'], decoration: dec('Address')),
              const SizedBox(height: 8),
              TextField(controller: project, decoration: dec('Project / bill for')),
            ]),
          ),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Autocomplete<Map<String, dynamic>>(
                displayStringForOption: (o) => '${o['name']}',
                optionsBuilder: (t) {
                  final q = t.text.trim().toLowerCase();
                  final all = sellables;
                  return (q.isEmpty ? all : all.where((s) => '${s['name']}'.toLowerCase().contains(q))).take(8);
                },
                optionsViewBuilder: (ctx, onSel, opts) => Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: 280, maxWidth: MediaQuery.of(ctx).size.width - 48),
                      child: ListView(padding: EdgeInsets.zero, shrinkWrap: true, children: [
                        for (final o in opts)
                          ListTile(
                            dense: true,
                            leading: Icon(o['pkg'] == true ? Icons.inventory_2_outlined : Icons.apps, size: 20, color: gold),
                            title: Text('${o['name']}'),
                            trailing: Text(inr(o['price']), style: const TextStyle(fontWeight: FontWeight.w700)),
                            onTap: () => onSel(o),
                          ),
                      ]),
                    ),
                  ),
                ),
                onSelected: (s) {
                  addSellable(s);
                  WidgetsBinding.instance.addPostFrameCallback((_) => addCtl?.clear());
                },
                fieldViewBuilder: (ctx, ctl, focus, submit) {
                  addCtl = ctl;
                  return TextField(
                    controller: ctl,
                    focusNode: focus,
                    decoration: dec('Add item or package').copyWith(
                      prefixIcon: const Icon(Icons.add_shopping_cart),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add_circle, color: navy),
                        tooltip: 'Add as custom item',
                        onPressed: () {
                          if (ctl.text.trim().isEmpty) return;
                          addCustom(ctl.text.trim());
                          ctl.clear();
                        },
                      ),
                    ),
                  );
                },
              ),
              for (var n = 0; n < items.length; n++) itemCard(n),
              for (var n = 0; n < charges.length; n++) chargeCard(n),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() => charges.add({'uid': uid++, 'name': 'Delivery fee', 'amount': 0, 'tax': num.tryParse('${biz['default_tax'] ?? 18}') ?? 18}));
                    recalc();
                  },
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('Add charge (delivery / installation)'),
                ),
              ),
            ]),
          ),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: discType,
                    decoration: dec('Discount'),
                    items: const [DropdownMenuItem(value: 'percent', child: Text('Percent %')), DropdownMenuItem(value: 'fixed', child: Text('Fixed ₹'))],
                    onChanged: (v) {
                      setState(() => discType = v ?? 'percent');
                      recalc();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: discVal, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: dec('Value'), onChanged: (_) => recalc())),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: coupon, textCapitalization: TextCapitalization.characters, decoration: dec('Coupon code'), onChanged: (_) => recalc())),
                const SizedBox(width: 8),
                FilledButton(onPressed: recalc, style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black, minimumSize: const Size(80, 48)), child: const Text('Apply')),
              ]),
              if (r != null && '${r['coupon_error']}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${r['coupon_error']}', style: const TextStyle(color: errRed, fontSize: 13))),
              if (r != null && '${r['coupon_info']}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Applied ${r['coupon_info']} - saves ${inr(r['coupon_disc'])}', style: const TextStyle(color: okGreen, fontSize: 13))),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: taxMode,
                    decoration: dec('Tax'),
                    items: const [DropdownMenuItem(value: 'intra', child: Text('CGST+SGST')), DropdownMenuItem(value: 'inter', child: Text('IGST')), DropdownMenuItem(value: 'none', child: Text('No tax'))],
                    onChanged: (v) {
                      setState(() => taxMode = v ?? 'intra');
                      recalc();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<bool>(
                    value: inclusive,
                    decoration: dec('Prices'),
                    items: const [DropdownMenuItem(value: false, child: Text('Excl. tax')), DropdownMenuItem(value: true, child: Text('Incl. tax'))],
                    onChanged: (v) {
                      setState(() => inclusive = v ?? false);
                      recalc();
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              TextField(controller: notes, decoration: dec('Notes')),
            ]),
          ),
          Panel(
            child: Column(children: [
              if (calcErr != null) Text(calcErr!, style: const TextStyle(color: errRed)),
              if (r != null) ...[
                tot('Subtotal', r['subtotal']),
                if (numOf(r['disc_total']) > 0) tot('Discount', r['disc_total'], neg: true),
                if (numOf(r['coupon_disc']) > 0) tot('Coupon', r['coupon_disc'], neg: true),
                if (numOf(r['charges_total']) > 0) tot('Charges', r['charges_total']),
                if (taxMode == 'intra' && numOf(r['tax']) > 0) ...[tot('CGST', r['cgst']), tot('SGST', r['sgst'])],
                if (taxMode == 'inter' && numOf(r['tax']) > 0) tot('IGST', r['igst']),
                if (numOf(r['round_amt']) != 0) tot('Round off', r['round_amt']),
                const Divider(),
                tot('Total', r['total'], bold: true),
              ],
              if (type == 'invoice') ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: paid, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: dec('Paid now', prefix: '₹ '))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: method,
                      decoration: dec('Method'),
                      items: ['cash', 'upi', 'bank transfer', 'card'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                      onChanged: (v) => setState(() => method = v ?? 'cash'),
                    ),
                  ),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget tot(String a, dynamic b, {bool bold = false, bool neg = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.normal, fontSize: bold ? 17 : 14)),
          Text('${neg ? '- ' : ''}${inr(b)}', style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.normal, fontSize: bold ? 17 : 14)),
        ]),
      );

  Widget itemCard(int n) {
    final it = items[n];
    final k = ValueKey('i${it['uid']}');
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Row(children: [
          Expanded(child: TextFormField(key: ValueKey('n${it['uid']}'), initialValue: '${it['name']}', decoration: dec('Item'), onChanged: (v) {
            it['name'] = v;
          })),
          IconButton(
            icon: const Icon(Icons.close, color: errRed),
            onPressed: () {
              setState(() => items.removeAt(n));
              recalc();
            },
          ),
        ]),
        if ('${it['desc']}'.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextFormField(key: ValueKey('d${it['uid']}'), initialValue: '${it['desc']}', minLines: 1, maxLines: 6, style: const TextStyle(fontSize: 12), decoration: dec('Includes'), onChanged: (v) => it['desc'] = v),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: numField('Qty', it['qty'], (v) => it['qty'] = v, key: ValueKey('q${it['uid']}'))),
          const SizedBox(width: 6),
          Expanded(flex: 2, child: numField('Rate', it['rate'], (v) => it['rate'] = v, prefix: '₹ ', key: ValueKey('r${it['uid']}'))),
          const SizedBox(width: 6),
          Expanded(child: numField('Disc%', it['disc'], (v) => it['disc'] = v, key: ValueKey('x${it['uid']}'))),
          const SizedBox(width: 6),
          Expanded(child: numField('Tax%', it['tax'], (v) => it['tax'] = v, key: ValueKey('t${it['uid']}'))),
        ]),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(inr(numOf(it['qty']) * numOf(it['rate'])), key: k, style: const TextStyle(fontWeight: FontWeight.w700, color: navy)),
          ),
        ),
      ]),
    );
  }

  Widget chargeCard(int n) {
    final c = charges[n];
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Expanded(flex: 3, child: TextFormField(key: ValueKey('cn${c['uid']}'), initialValue: '${c['name']}', decoration: dec('Charge'), onChanged: (v) => c['name'] = v)),
        const SizedBox(width: 6),
        Expanded(flex: 2, child: numField('Amount', c['amount'], (v) => c['amount'] = v, key: ValueKey('ca${c['uid']}'))),
        const SizedBox(width: 6),
        Expanded(child: numField('Tax%', c['tax'], (v) => c['tax'] = v, key: ValueKey('ct${c['uid']}'))),
        IconButton(
          icon: const Icon(Icons.close, color: errRed),
          onPressed: () {
            setState(() => charges.removeAt(n));
            recalc();
          },
        ),
      ]),
    );
  }
}
