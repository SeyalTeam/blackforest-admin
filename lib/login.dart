import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'home.dart';
import 'kitchen_order.dart'; // ADDED: Import for KitchenOrderPage

class IdleTimeoutWrapper extends StatefulWidget {
  final Widget child;
  final Duration timeout;
  const IdleTimeoutWrapper({
    super.key,
    required this.child,
    this.timeout = const Duration(hours: 6),
  });
  @override
  _IdleTimeoutWrapperState createState() => _IdleTimeoutWrapperState();
}

class _IdleTimeoutWrapperState extends State<IdleTimeoutWrapper> with WidgetsBindingObserver {
  Timer? _timer;
  DateTime? _pauseTime;

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(widget.timeout, _logout);
  }

  Future<void> _logout() async {
    const storage = FlutterSecureStorage();
    await storage.deleteAll();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      _timer?.cancel();
      _pauseTime = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_pauseTime != null) {
        final duration = DateTime.now().difference(_pauseTime!);
        if (duration > widget.timeout) {
          _logout();
        } else {
          _startTimer();
        }
        _pauseTime = null;
      } else {
        _startTimer();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _startTimer(),
      onPointerMove: (_) => _startTimer(),
      onPointerUp: (_) => _startTimer(),
      child: widget.child,
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final username = _usernameController.text.trim();
      final fullEmail = '$username@bf.com';
      final response = await http.post(
        Uri.parse('https://admin.theblackforestcakes.com/api/users/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': fullEmail,
          'password': _passwordController.text.trim(),
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final user = data['user'];
        final role = user['role'];
        if (role != 'superadmin' && role != 'kitchen') { // CHANGED: Allow 'kitchen' role in addition to 'superadmin'
          _showError('Access denied: Only superadmin or kitchen roles can use this app.');
          setState(() => _isLoading = false);
          return;
        }
        const storage = FlutterSecureStorage();
        await storage.write(key: 'token', value: data['token']);
        await storage.write(key: 'email', value: fullEmail);
        await storage.write(key: 'role', value: role);
        if (mounted) {
          Widget targetPage;
          if (role == 'kitchen') { // ADDED: Navigate to KitchenOrderPage for 'kitchen' role
            targetPage = const KitchenOrderPage();
          } else {
            targetPage = const HomePage();
          }
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => IdleTimeoutWrapper(child: targetPage),
            ),
          );
        }
      } else if (response.statusCode == 401) {
        _showError('Invalid credentials');
      } else {
        _showError('Server error: ${response.statusCode}');
      }
    } catch (e) {
      _showError('Network error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent, // CHANGED: Updated error color for premium feel
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900], // CHANGED: Darker background for premium look
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Card(
              elevation: 8, // CHANGED: Increased elevation for depth
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), // CHANGED: Softer corners
              color: Colors.white.withOpacity(0.95), // CHANGED: Slight transparency for premium overlay
              child: Padding(
                padding: const EdgeInsets.all(32), // CHANGED: More padding for spacious feel
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Admin Login', // CHANGED: Updated title to reflect broader access
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87, // CHANGED: Darker text for contrast
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          labelText: 'Username',
                          prefixIcon: const Icon(Icons.person, color: Colors.black54), // CHANGED: Colored icon
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12), // CHANGED: Rounded borders
                          ),
                          filled: true, // ADDED: Filled background
                          fillColor: Colors.grey[200], // ADDED: Light fill color
                        ),
                        validator: (v) => v!.isEmpty ? 'Enter username' : null,
                        keyboardType: TextInputType.text,
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock, color: Colors.black54), // CHANGED: Colored icon
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12), // CHANGED: Rounded borders
                          ),
                          filled: true, // ADDED: Filled background
                          fillColor: Colors.grey[200], // ADDED: Light fill color
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off : Icons.visibility,
                              color: Colors.black54, // CHANGED: Colored icon
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (v) => v!.isEmpty ? 'Enter password' : null,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _login(),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black, // Kept black for premium
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 56), // CHANGED: Taller button
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), // CHANGED: Rounded button
                          elevation: 4, // ADDED: Button elevation
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Login', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), // CHANGED: Larger text
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}