import 'package:flutter/material.dart';
import 'api.dart';
import 'util.dart';

const stdIncludes = [
  'Complete source code', 'Executable / build files', 'Abstract & synopsis', 'Project report', 'Documentation', 'PPT',
  'Research paper', 'Diagrams', 'Database & sample data', 'Configuration files', 'Installation & deployment',
  'Customization', 'Demo video', 'Viva questions & explanation', 'Hardware components', 'Maintenance & support',
];

class PackagesScreen extends StatefulWidget {
  const PackagesScreen({super.key});
  @override
  State<PackagesScreen> createState() => _PackagesState();
}

class _PackagesState extends State<PackagesScreen> {
  List rows = [];
  bool loading = true;
  String? err;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await Api.get('e/presets');
      if (mounted) setState(() {
        rows = (r as List).reversed.toList();
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

  Future<void> edit([Map? p]) async {
    final name = TextEditingController(text: p?['name'] ?? '');
    final price = TextEditingController(text: p == null ? '' : '${p['price']}');
    final tax = TextEditingController(text: p == null ? '18' : '${p['tax_rate']}');
    final inc = TextEditingController(text: p?['includes'] ?? '');
    var active = p == null ? true : (p['active'] == 1);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(c).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(p == null ? 'New package' : 'Edit package', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: navy)),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: dec('Package name (e.g. Source Code Only)')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: dec('Price', prefix: '₹ '))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: tax, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: dec('Tax %'))),
              ]),
              const SizedBox(height: 10),
              TextField(controller: inc, minLines: 5, maxLines: 9, decoration: dec('What is included - one per line')),
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                for (final s in stdIncludes)
                  ActionChip(
                    label: Text(s, style: const TextStyle(fontSize: 12)),
                    onPressed: () {
                      final have = inc.text.split('\n').map((e) => e.trim()).toList();
                      if (!have.contains(s)) inc.text = (inc.text.trim().isEmpty ? '' : '${inc.text.trim()}\n') + s;
                      set(() {});
                    },
                  ),
              ]),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Active'), value: active, onChanged: (v) => set(() => active = v)),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(50)),
                child: const Text('Save package', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      ),
    );
    if (ok != true) return;
    final body = {'name': name.text, 'price': price.text, 'tax_rate': tax.text, 'includes': inc.text, 'active': active ? 1 : 0};
    try {
      if (p == null) {
        await Api.post('e/presets', body);
      } else {
        await Api.put('e/presets/${p['id']}', body);
      }
      load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(onPressed: () => edit(), backgroundColor: gold, foregroundColor: Colors.black, icon: const Icon(Icons.add), label: const Text('Package')),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
          if (loading) const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator())),
          if (err != null) Panel(child: Text(err!, style: const TextStyle(color: errRed))),
          for (final p in rows)
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => edit(p as Map),
              child: Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${p['name']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: navy))),
                    Text(inr(p['price']), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: errRed),
                      onPressed: () async {
                        if (!await confirm(context, 'Delete package "${p['name']}"?', ok: 'Delete')) return;
                        try {
                          await Api.delete('e/presets/${p['id']}');
                          load();
                        } catch (e) {
                          if (mounted) toast(context, '$e', error: true);
                        }
                      },
                    ),
                  ]),
                  for (final l in '${p['includes'] ?? ''}'.split('\n').where((e) => e.trim().isNotEmpty))
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(children: [const Icon(Icons.check_circle, size: 16, color: okGreen), const SizedBox(width: 6), Expanded(child: Text(l, style: const TextStyle(fontSize: 13)))]),
                    ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
