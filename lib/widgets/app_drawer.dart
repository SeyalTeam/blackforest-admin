import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../home.dart';
import '../admin_chat_page.dart';
import '../branchwise_bills.dart';
import '../bills_date_time_page.dart';
import '../timewise_report.dart';
import '../waiterwise_report.dart';
import '../closingentry_report.dart';
import '../expensewise_report.dart';
import '../return_orders.dart';
import '../stockorder_report.dart';
import '../categorywise_report.dart';
import '../productwise_report.dart';
import '../kitchen_order.dart';
import '../login.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  Future<void> _logout(BuildContext context) async {
    const storage = FlutterSecureStorage();
    await storage.deleteAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!context.mounted) return;
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
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 250),
          reverseTransitionDuration: const Duration(milliseconds: 250),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => page),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(top: 48, bottom: 20, left: 20, right: 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF07213A), Color(0xFF0B355B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.admin_panel_settings_rounded, size: 28, color: Colors.white),
                ),
                const SizedBox(width: 14),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'BLACKFOREST',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                    Text(
                      'Admin Control Center',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              children: [
                _drawerTile(
                  context,
                  icon: Icons.dashboard_rounded,
                  title: 'Dashboard',
                  color: const Color(0xFF0B355B),
                  onTap: () => _navigateTo(context, const HomePage()),
                ),
                const Divider(height: 16, thickness: 1, indent: 8, endIndent: 8),

                _sectionHeader('BILLING & ORDERS'),
                _drawerTile(
                  context,
                  icon: Icons.receipt_long_rounded,
                  title: 'Live Billing',
                  color: const Color(0xFF0284C7),
                  onTap: () => _navigateTo(context, const BillsDateTimePage()),
                ),
                _drawerTile(
                  context,
                  icon: Icons.storefront_rounded,
                  title: 'Branch-wise Bills',
                  color: const Color(0xFF0F766E),
                  onTap: () => _navigateTo(context, const BranchwiseBillsPage()),
                ),
                _drawerTile(
                  context,
                  icon: Icons.restaurant_rounded,
                  title: 'Kitchen Orders (KOT)',
                  color: const Color(0xFFEA580C),
                  onTap: () => _navigateTo(context, const KitchenOrderPage()),
                ),
                _drawerTile(
                  context,
                  icon: Icons.assignment_return_rounded,
                  title: 'Return Orders',
                  color: const Color(0xFFDC2626),
                  onTap: () => _navigateTo(context, const ReturnOrdersPage()),
                ),

                const Divider(height: 16, thickness: 1, indent: 8, endIndent: 8),
                _sectionHeader('SALES ANALYTICS'),
                _drawerTile(
                  context,
                  icon: Icons.cake_rounded,
                  title: 'Category-wise Report',
                  color: const Color(0xFF9333EA),
                  onTap: () => _navigateTo(context, const CategorywiseReportPage()),
                ),
                _drawerTile(
                  context,
                  icon: Icons.fastfood_rounded,
                  title: 'Product-wise Report',
                  color: const Color(0xFF2563EB),
                  onTap: () => _navigateTo(context, const ProductwiseReportPage()),
                ),
                _drawerTile(
                  context,
                  icon: Icons.alarm_rounded,
                  title: 'Time-wise Report',
                  color: const Color(0xFF4F46E5),
                  onTap: () => _navigateTo(context, const TimewiseReportPage()),
                ),
                _drawerTile(
                  context,
                  icon: Icons.badge_rounded,
                  title: 'Waiter Performance',
                  color: const Color(0xFFD97706),
                  onTap: () => _navigateTo(context, const WaiterwiseReportPage()),
                ),

                const Divider(height: 16, thickness: 1, indent: 8, endIndent: 8),
                _sectionHeader('FINANCE & OPERATIONS'),
                _drawerTile(
                  context,
                  icon: Icons.account_balance_wallet_rounded,
                  title: 'Store Expenses',
                  color: const Color(0xFFE11D48),
                  onTap: () => _navigateTo(context, const ExpensewiseReportPage()),
                ),
                _drawerTile(
                  context,
                  icon: Icons.point_of_sale_rounded,
                  title: 'Closing Entries',
                  color: const Color(0xFF059669),
                  onTap: () => _navigateTo(context, const ClosingEntryReportPage()),
                ),
                _drawerTile(
                  context,
                  icon: Icons.inventory_2_rounded,
                  title: 'Stock Orders',
                  color: const Color(0xFF78350F),
                  onTap: () => _navigateTo(context, const StockOrderReportPage()),
                ),
                _drawerTile(
                  context,
                  icon: Icons.forum_rounded,
                  title: 'Staff Comms',
                  color: const Color(0xFF0284C7),
                  onTap: () => _navigateTo(context, const AdminChatPage()),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey[200]!)),
            ),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
              ),
              title: const Text(
                'Logout',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              onTap: () => _logout(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 14, top: 8, bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.grey[400],
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _drawerTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: 0, vertical: -1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF1E293B),
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey[400]),
      onTap: onTap,
    );
  }
}
