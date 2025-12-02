import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login.dart';
import 'branchwise_bills.dart';
import 'bills_date_time_page.dart';
import 'timewise_report.dart';
import 'waiterwise_report.dart';
import 'closingentry_report.dart'; // Import for Closing Entries
import 'expensewise_report.dart'; // Import for Expense List

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
    );
  }

  void _notImplemented(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature: Not implemented yet'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _gridItem(BuildContext context, String title, IconData icon, VoidCallback onTap, Color gradientStart, Color gradientEnd) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [gradientStart, gradientEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              spreadRadius: 2,
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 52, color: Colors.white),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'SuperAdmin Home',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => _logout(context),
          ),
        ],
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.5),
      ),
      // ================= DRAWER ==================
      drawer: Drawer(
        backgroundColor: Colors.white,
        child: SafeArea(
          child: Column(
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
              ListTile(
                leading: const Icon(Icons.receipt_long, color: Colors.black87),
                title: const Text('Branch-wise Bills'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BranchwiseBillsPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.access_time, color: Colors.black87),
                title: const Text('Time-wise Report'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TimewiseReportPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_wallet, color: Colors.black87),
                title: const Text('Closing Entries'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ClosingEntryReportPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.person, color: Colors.black87),
                title: const Text('Waiter-wise Reports'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WaiterwiseReportPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.money_off, color: Colors.black87),
                title: const Text('Expense List & Details'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ExpensewiseReportPage()),
                  );
                },
              ),
              const Spacer(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.black87),
                title: const Text('Logout'),
                onTap: () => _logout(context),
              ),
            ],
          ),
        ),
      ),
      // ================= MAIN BODY ==================
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 18.0),
        child: Column(
          children: [
            // Grid view for premium layout
            Expanded(
              child: GridView.count(
                crossAxisCount: 3,
                mainAxisSpacing: 20,
                crossAxisSpacing: 20,
                childAspectRatio: 1.0,
                children: [
                  _gridItem(
                    context,
                    'Branch',
                    Icons.location_on,
                        () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const BranchwiseBillsPage()),
                      );
                    },
                    Colors.blueGrey[700]!,
                    Colors.blueGrey[400]!,
                  ),
                  _gridItem(
                    context,
                    'Time',
                    Icons.access_time,
                        () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TimewiseReportPage()),
                      );
                    },
                    Colors.teal[700]!,
                    Colors.teal[400]!,
                  ),
                  _gridItem(
                    context,
                    'Waiter',
                    Icons.person_search,
                        () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const WaiterwiseReportPage()),
                      );
                    },
                    Colors.indigo[700]!,
                    Colors.indigo[400]!,
                  ),
                  _gridItem(
                    context,
                    'Live',
                    Icons.schedule,
                        () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const BillsDateTimePage()),
                      );
                    },
                    Colors.green[700]!,
                    Colors.green[400]!,
                  ),
                  _gridItem(
                    context,
                    'Expense',
                    Icons.receipt,
                        () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ExpensewiseReportPage()),
                      );
                    },
                    Colors.orange[700]!,
                    Colors.orange[400]!,
                  ),
                  _gridItem(
                    context,
                    'Closing',
                    Icons.account_balance_wallet,
                        () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ClosingEntryReportPage()),
                      );
                    },
                    Colors.deepPurple[700]!,
                    Colors.deepPurple[400]!,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: Colors.white,
              shadowColor: Colors.black.withOpacity(0.3),
              child: ListTile(
                leading: const Icon(Icons.settings, color: Colors.black87),
                title: const Text('Settings / Config', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                trailing: const Icon(Icons.chevron_right, color: Colors.black87),
                onTap: () => _notImplemented(context, 'Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}