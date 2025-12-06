import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../branchwise_bills.dart';
import '../bills_date_time_page.dart';
import '../timewise_report.dart';
import '../waiterwise_report.dart';
import '../closingentry_report.dart';
import '../expensewise_report.dart';
import '../return_orders.dart';
import '../stockorder_report.dart';
import '../login.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
    );
  }

  void _navigateTo(BuildContext context, Widget page) {
    if (Scaffold.maybeOf(context)?.hasDrawer ?? false) {
      Navigator.pop(context); // Close drawer on mobile
    }
    
    if (MediaQuery.of(context).size.width >= 1024) {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => page),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DrawerHeader(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.black, Colors.grey],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: const Row(
            children: [
              Icon(Icons.admin_panel_settings, size: 40, color: Colors.white),
              SizedBox(width: 12),
              Text('SuperAdmin', style: TextStyle(color: Colors.white, fontSize: 20)),
            ],
          ),
        ),
        // --------- Drawer Items ----------
        // 1. Branch
        ListTile(
          leading: const Icon(Icons.receipt_long, color: Colors.black87),
          title: const Text('Branch-wise Bills'),
          onTap: () => _navigateTo(context, const BranchwiseBillsPage()),
        ),
        // 2. Time
        ListTile(
          leading: const Icon(Icons.access_time, color: Colors.black87),
          title: const Text('Time-wise Report'),
          onTap: () => _navigateTo(context, const TimewiseReportPage()),
        ),
        // 3. Waiter
        ListTile(
          leading: const Icon(Icons.person, color: Colors.black87),
          title: const Text('Waiter-wise Reports'),
          onTap: () => _navigateTo(context, const WaiterwiseReportPage()),
        ),
        // 4. Live
        ListTile(
          leading: const Icon(Icons.schedule, color: Colors.black87),
          title: const Text('Live'),
          onTap: () => _navigateTo(context, const BillsDateTimePage()),
        ),
        // 5. Expense
        ListTile(
          leading: const Icon(Icons.money_off, color: Colors.black87),
          title: const Text('Expense List & Details'),
          onTap: () => _navigateTo(context, const ExpensewiseReportPage()),
        ),
        // 6. Closing
        ListTile(
          leading: const Icon(Icons.account_balance_wallet, color: Colors.black87),
          title: const Text('Closing Entries'),
          onTap: () => _navigateTo(context, const ClosingEntryReportPage()),
        ),
        // 7. Return
        ListTile(
          leading: const Icon(Icons.assignment_return, color: Colors.black87),
          title: const Text('Return Orders'),
          onTap: () => _navigateTo(context, const ReturnOrdersPage()),
        ),
        // 8. Stock Order
        ListTile(
          leading: const Icon(Icons.inventory, color: Colors.black87),
          title: const Text('Stock Orders'),
          onTap: () => _navigateTo(context, const StockOrderReportPage()),
        ),
        const Spacer(),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.black87),
          title: const Text('Logout'),
          onTap: () => _logout(context),
        ),
      ],
    );
  }
}
