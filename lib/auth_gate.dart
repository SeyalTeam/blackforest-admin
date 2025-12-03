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
    // Show splash screen for at least 2 seconds
    await Future.delayed(const Duration(seconds: 2));
    
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
      // Splash Screen with large app icon
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Large App Icon
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Image.asset(
                    'assets/icon/my_icon.png',
                    width: 180,
                    height: 180,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              // App Name
              const Text(
                'Admin',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 50),
              // Loading Indicator
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              ),
            ],
          ),
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
