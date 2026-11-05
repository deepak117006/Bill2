import 'package:flutter/material.dart';
import 'api.dart';
import 'util.dart';
import 'connect.dart';
import 'bill.dart';
import 'statement.dart';
import 'packages.dart';
import 'dashboard.dart';

final navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.load();
  Api.onAuthLost = () => navKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ConnectScreen()), (r) => false);
  runApp(const PerixaApp());
}

class PerixaApp extends StatelessWidget {
  const PerixaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: navKey,
        title: 'Perixa Billing',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: navy, primary: navy, secondary: gold),
          scaffoldBackgroundColor: bg,
        ),
        home: Api.hasSession ? const Home() : const ConnectScreen(),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int i = 0;
  static const titles = ['New Bill', 'Statement', 'Packages', 'Dashboard'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: topBar(titles[i], actions: [
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'out') {
              try {
                await Api.post('logout');
              } catch (_) {}
              await Api.logout();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const ConnectScreen()), (r) => false);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(enabled: false, child: Text('PC: ${Api.base}', style: const TextStyle(fontSize: 12))),
            const PopupMenuItem(value: 'out', child: Text('Sign out / change PC')),
          ],
        ),
      ]),
      // Bill stays alive so a half-filled bill is not lost when switching tabs
      body: IndexedStack(index: i, children: [
        const BillScreen(),
        i == 1 ? const StatementScreen() : const SizedBox(),
        i == 2 ? const PackagesScreen() : const SizedBox(),
        i == 3 ? const DashboardScreen() : const SizedBox(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        backgroundColor: Colors.white,
        indicatorColor: gold.withAlpha(60),
        onDestinationSelected: (v) => setState(() => i = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Bill'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: 'Statement'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Packages'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Dashboard'),
        ],
      ),
    );
  }
}
