import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login.dart';
import 'branchwise_bills.dart';
import 'bills_date_time_page.dart';
import 'timewise_report.dart';
import 'waiterwise_report.dart';
import 'closingentry_report.dart'; // Import for Closing Entries
import 'expensewise_report.dart'; // Import for Expense List
import 'return_orders.dart'; // Import for Return Orders
import 'stockorder_report.dart'; // Import for Stock Orders

import 'widgets/app_drawer.dart';

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

  void _navigateTo(BuildContext context, Widget page) {
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
    double width = MediaQuery.of(context).size.width;
    bool isDesktop = width >= 1024;
    int crossAxisCount;

    if (width < 1024) {
      crossAxisCount = 3; // Mobile & Tablet
    } else {
      // Desktop: Calculate columns based on available space
      // Sidebar = 250, Padding = 32 (16 left + 16 right)
      double availableWidth = width - 250 - 32;
      // Target card width ~200px for a comfortable UI
      crossAxisCount = (availableWidth / 200).floor();
      // Clamp to reasonable limits to avoid items being too huge or too tiny
      if (crossAxisCount < 4) crossAxisCount = 4;
      if (crossAxisCount > 8) crossAxisCount = 8;
    }

    Widget mainContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 18.0),
      child: Column(
        children: [
          // Grid view for premium layout
          Expanded(
            child: GridView.count(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 20,
              crossAxisSpacing: 20,
              childAspectRatio: 1.0,
              children: [
                _gridItem(
                  context,
                  'Branch',
                  Icons.location_on,
                  () => _navigateTo(context, const BranchwiseBillsPage()),
                  Colors.blueGrey[700]!,
                  Colors.blueGrey[400]!,
                ),
                _gridItem(
                  context,
                  'Time',
                  Icons.access_time,
                  () => _navigateTo(context, const TimewiseReportPage()),
                  Colors.teal[700]!,
                  Colors.teal[400]!,
                ),
                _gridItem(
                  context,
                  'Waiter',
                  Icons.person_search,
                  () => _navigateTo(context, const WaiterwiseReportPage()),
                  Colors.indigo[700]!,
                  Colors.indigo[400]!,
                ),
                _gridItem(
                  context,
                  'Live',
                  Icons.schedule,
                  () => _navigateTo(context, const BillsDateTimePage()),
                  Colors.green[700]!,
                  Colors.green[400]!,
                ),
                _gridItem(
                  context,
                  'Expense',
                  Icons.receipt,
                  () => _navigateTo(context, const ExpensewiseReportPage()),
                  Colors.orange[700]!,
                  Colors.orange[400]!,
                ),
                _gridItem(
                  context,
                  'Closing',
                  Icons.account_balance_wallet,
                  () => _navigateTo(context, const ClosingEntryReportPage()),
                  Colors.deepPurple[700]!,
                  Colors.deepPurple[400]!,
                ),
                _gridItem(
                  context,
                  'Return',
                  Icons.assignment_return,
                  () => _navigateTo(context, const ReturnOrdersPage()),
                  Colors.red[700]!,
                  Colors.red[400]!,
                ),
                _gridItem(
                  context,
                  'Stock Order',
                  Icons.inventory,
                  () => _navigateTo(context, const StockOrderReportPage()),
                  Colors.brown[700]!,
                  Colors.brown[400]!,
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
    );

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
          if (!isDesktop) // Only show logout in AppBar on mobile
            IconButton(
              tooltip: 'Logout',
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: () => _logout(context),
            ),
        ],
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.5),
      ),
      // ================= DRAWER (Mobile Only) ==================
      drawer: isDesktop
          ? null
          : const Drawer(
        backgroundColor: Colors.white,
        child: SafeArea(
          child: AppDrawer(),
        ),
      ),
      // ================= MAIN BODY ==================
      body: isDesktop
          ? Row(
        children: [
          // Fixed Sidebar
          Container(
            width: 250,
            color: Colors.white,
            child: const AppDrawer(),
          ),
          // Main Content
          Expanded(child: mainContent),
        ],
      )
          : mainContent,
    );
  }
}