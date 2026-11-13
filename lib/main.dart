import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'admin_tabs.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FlisingAdminApp());
}

const String kApiKey = 'AIzaSyDA2PL8HUBr6sSvQ-j8Eb54MOayxGZ_LpU';
const String kDbUrl = 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app';
const Color kOrange = Color(0xFFE9692C);
const Color kBg = Color(0xFF0A0A0A);
const Color kSurface = Color(0xFF141414);
const Color kSurface2 = Color(0xFF1F1F1F);
const Color kGreen = Color(0xFF4CAF50);
const Color kRed = Color(0xFFD32F2F);

const List<String> kMasterAdminEmails = [
  'allendii57@gmail.com',
  'grassrootsgenius@gmail.com',
  'allen@westsepikinvestments.com',
];

class FlisingPinLogo extends StatelessWidget {
  final double size;
  const FlisingPinLogo({super.key, this.size = 84});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0D1117),
        border: Border.all(color: kOrange, width: 2.5),
        boxShadow: [
          BoxShadow(color: kOrange.withOpacity(0.45), blurRadius: 24, spreadRadius: 2),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/flising_admin.jpg',
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class FlisingAdminApp extends StatelessWidget {
  const FlisingAdminApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flising Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: kBg,
        primaryColor: kOrange,
        colorScheme: const ColorScheme.dark(primary: kOrange, secondary: kOrange, surface: kSurface),
      ),
      home: const AdminGate(),
    );
  }
}

class AdminGate extends StatefulWidget {
  const AdminGate({super.key});
  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  String? _token;
  String? _refresh;
  String? _uid;
  bool _loading = true;
  String? _err;
  String? _info;
  final _emailCtrl = TextEditingController(text: 'allendii57@gmail.com');
  final _passCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final p = await SharedPreferences.getInstance();
    final ref = p.getString('adm_ref');
    final savedEmail = p.getString('adm_email') ?? '';
    if (savedEmail.isNotEmpty) _emailCtrl.text = savedEmail;
    if (ref != null && ref.isNotEmpty) {
      try {
        final r = await http.post(
          Uri.parse('https://securetoken.googleapis.com/v1/token?key=$kApiKey'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: 'grant_type=refresh_token&refresh_token=$ref',
        );
        if (r.statusCode == 200) {
          final d = jsonDecode(r.body);
          if (await _checkAdmin(d['user_id'], d['id_token'], savedEmail)) {
            setState(() {
              _token = d['id_token'];
              _refresh = d['refresh_token'];
              _uid = d['user_id'];
              _loading = false;
            });
            return;
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<bool> _checkAdmin(String uid, String tok, String email) async {
    if (kMasterAdminEmails.contains(email.toLowerCase().trim())) {
      try {
        await http.put(Uri.parse('$kDbUrl/admins/$uid.json?auth=$tok'), body: 'true');
      } catch (_) {}
      return true;
    }
    final r = await http.get(Uri.parse('$kDbUrl/admins/$uid.json?auth=$tok'));
    return r.statusCode == 200 && jsonDecode(r.body) == true;
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    setState(() { _loading = true; _err = null; _info = null; });
    try {
      final r = await http.post(
        Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$kApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': _passCtrl.text, 'returnSecureToken': true}),
      );
      final d = jsonDecode(r.body);
      if (r.statusCode != 200) {
        setState(() { _err = d['error']?['message'] ?? 'Login failed'; _loading = false; });
        return;
      }
      if (!await _checkAdmin(d['localId'], d['idToken'], email)) {
        setState(() { _err = 'Account is not authorized in admins/${d['localId']}'; _loading = false; });
        return;
      }
      final p = await SharedPreferences.getInstance();
      await p.setString('adm_ref', d['refreshToken']);
      await p.setString('adm_email', email);
      setState(() {
        _token = d['idToken'];
        _refresh = d['refreshToken'];
        _uid = d['localId'];
        _loading = false;
      });
    } catch (e) {
      setState(() { _err = '$e'; _loading = false; });
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() { _err = 'Enter your email above first, then tap Forgot Password.'; _info = null; });
      return;
    }
    setState(() { _err = null; _info = 'Sending reset link...'; });
    try {
      final r = await http.post(
        Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=$kApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'requestType': 'PASSWORD_RESET', 'email': email}),
      );
      if (r.statusCode == 200) {
        setState(() { _info = 'Password reset link sent to $email! Check your inbox/spam.'; _err = null; });
      } else {
        final d = jsonDecode(r.body);
        setState(() { _err = d['error']?['message'] ?? 'Could not send reset email'; _info = null; });
      }
    } catch (e) {
      setState(() { _err = '$e'; _info = null; });
    }
  }

  Future<void> _logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('adm_ref');
    setState(() { _token = null; _refresh = null; _uid = null; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: kOrange)));
    if (_token != null && _uid != null) {
      return AdminHome(token: _token!, refreshToken: _refresh ?? '', adminEmail: _emailCtrl.text.trim(), onLogout: _logout);
    }
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Container(
                width: 360,
                margin: const EdgeInsets.only(top: 42),
                padding: const EdgeInsets.fromLTRB(28, 64, 28, 28),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: const Border(top: BorderSide(color: kOrange, width: 3)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('FLISING ADMIN', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 4)),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _emailCtrl,
                      decoration: const InputDecoration(hintText: 'Admin Email', filled: true, fillColor: kSurface2),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passCtrl,
                      obscureText: true,
                      onSubmitted: (_) => _login(),
                      decoration: const InputDecoration(hintText: 'Password', filled: true, fillColor: kSurface2),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kOrange,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        onPressed: _login,
                        child: const Text('SIGN IN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _resetPassword,
                      child: const Text('Forgot Password? Send Reset Email', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                    if (_err != null)
                      Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: const TextStyle(color: kRed, fontSize: 12), textAlign: TextAlign.center)),
                    if (_info != null)
                      Padding(padding: const EdgeInsets.only(top: 8), child: Text(_info!, style: const TextStyle(color: kGreen, fontSize: 12), textAlign: TextAlign.center)),
                  ],
                ),
              ),
              const Positioned(
                top: 0,
                child: FlisingPinLogo(size: 86),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
