import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'login.dart';
import 'home.dart';
import 'kitchen_order.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isChecking = true;
  bool _isAuthenticated = false;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'token');
    final role = await storage.read(key: 'role');
    
    // If token exists, trust it and proceed (offline-friendly)
    if (mounted) {
      setState(() {
        _isAuthenticated = token != null;
        _userRole = role;
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_isAuthenticated) {
      return const LoginPage();
    }

    // Route based on role
    Widget targetPage;
    if (_userRole == 'kitchen') {
      targetPage = const KitchenOrderPage();
    } else {
      targetPage = const HomePage();
    }

    return IdleTimeoutWrapper(child: targetPage);
  }
}
