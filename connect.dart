import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'util.dart';
import 'main.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});
  @override
  State<ConnectScreen> createState() => _ConnectState();
}

class _ConnectState extends State<ConnectScreen> {
  final addr = TextEditingController(text: Api.base.replaceFirst('http://', ''));
  final user = TextEditingController();
  final pass = TextEditingController();
  bool busy = false;
  String? err;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final u = p.getString('user');
      if (u != null && user.text.isEmpty) setState(() => user.text = u);
    });
  }

  Future<void> go() async {
    setState(() {
      busy = true;
      err = null;
    });
    try {
      await Api.setServer(addr.text);
      await Api.get('ping');
      await Api.login(user.text.trim(), pass.text);
      final p = await SharedPreferences.getInstance();
      await p.setString('user', user.text.trim());
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const Home()), (r) => false);
    } on ApiError catch (e) {
      setState(() => err = e.message);
    } catch (e) {
      setState(() => err = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: navy,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 84,
                height: 84,
                alignment: Alignment.center,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: gold, width: 3)),
                child: const Text('P', style: TextStyle(color: gold, fontSize: 44, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 14),
              const Text('PERIXA', style: TextStyle(color: gold, fontSize: 26, letterSpacing: 5, fontWeight: FontWeight.w800)),
              const Text('Billing Pro', style: TextStyle(color: Colors.white70, fontSize: 15)),
              const SizedBox(height: 26),
              Panel(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Connect to your PC', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: navy)),
                  const SizedBox(height: 4),
                  const Text('Same Wi-Fi as the PC. On the PC: Settings > Phone > turn on, then type the address shown there.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6B7690))),
                  const SizedBox(height: 14),
                  TextField(controller: addr, keyboardType: TextInputType.url, decoration: dec('PC address', hint: '192.168.1.5:5057')),
                  const SizedBox(height: 10),
                  TextField(controller: user, decoration: dec('Username')),
                  const SizedBox(height: 10),
                  TextField(controller: pass, obscureText: true, decoration: dec('Password'), onSubmitted: (_) => go()),
                  if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: const TextStyle(color: errRed))),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy ? null : go,
                    style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(50)),
                    child: busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Connect', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
