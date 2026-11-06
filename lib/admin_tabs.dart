import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'main.dart';

class AdminHome extends StatefulWidget {
  final String token;
  final String refreshToken;
  final VoidCallback onLogout;
  const AdminHome({super.key, required this.token, required this.refreshToken, required this.onLogout});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _tab = 0;
  late String _tok;
  Timer? _timer;
  Map<String, dynamic> _drivers = {};
  Map<String, dynamic> _rides = {};
  Map<String, dynamic> _users = {};

  @override
  void initState() {
    super.initState();
    _tok = widget.token;
    _sync();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _sync());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sync() async {
    try {
      final res = await Future.wait([
        http.get(Uri.parse('$kDbUrl/drivers.json?auth=$_tok')),
        http.get(Uri.parse('$kDbUrl/rides.json?auth=$_tok')),
        http.get(Uri.parse('$kDbUrl/users.json?auth=$_tok')),
      ]);
      if (!mounted) return;
      setState(() {
        _drivers = (jsonDecode(res[0].body) as Map?)?.cast<String, dynamic>() ?? {};
        _rides = (jsonDecode(res[1].body) as Map?)?.cast<String, dynamic>() ?? {};
        _users = (jsonDecode(res[2].body) as Map?)?.cast<String, dynamic>() ?? {};
      });
    } catch (_) {}
  }

  Future<void> _patch(String path, Map<String, dynamic> body) async {
    await http.patch(Uri.parse('$kDbUrl/$path.json?auth=$_tok'), body: jsonEncode(body));
    await _sync();
  }

  double _fare(dynamic v) => double.tryParse((v ?? '').toString().replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
  String _fmt(dynamic ts) => ts is num ? DateFormat('dd MMM, hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(ts.toInt())) : '—';

  @override
  Widget build(BuildContext context) {
    final pages = [_dashTab(), _driversTab(), _ridesTab(), _usersTab(), _revTab()];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('FLISING ADMIN PORTAL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: kOrange), onPressed: _sync),
          IconButton(icon: const Icon(Icons.logout), onPressed: widget.onLogout),
        ],
      ),
      body: pages[_tab],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        backgroundColor: kSurface,
        selectedItemColor: kOrange,
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.directions_car), label: 'Drivers'),
          BottomNavigationBarItem(icon: Icon(Icons.route), label: 'Rides'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Users'),
          BottomNavigationBarItem(icon: Icon(Icons.payments), label: 'Revenue'),
        ],
      ),
    );
  }

  Widget _stat(String label, String val, Color col) {
    return Container(
      width: 165,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(10), border: Border(top: BorderSide(color: col, width: 3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(val, style: TextStyle(color: col, fontSize: 20, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _dashTab() {
    final rList = _rides.values.whereType().toList();
    final dList = _drivers.values.whereType().toList();
    final now = DateTime.now();
    double today = 0;
    for (final r in rList) {
      if (r['status'] == 'COMPLETED' && r['timestamp'] is num) {
        final d = DateTime.fromMillisecondsSinceEpoch((r['timestamp'] as num).toInt());
        if (d.year == now.year && d.month == now.month && d.day == now.day) today += _fare(r['fare']);
      }
    }
    final pending = dList.where((d) => (d['profile'] is Map) && d['profile']['pendingApproval'] == true && d['profile']['isVerified'] != true).length;
    final online = dList.where((d) => d['isOnline'] == true).length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 10, runSpacing: 10, children: [
        _stat('TODAY GROSS', 'K ${today.toStringAsFixed(2)}', kGreen),
        _stat('FLISING 10%', 'K ${(today * 0.1).toStringAsFixed(2)}', kOrange),
        _stat('ONLINE DRIVERS', '$online / ${dList.length}', kGreen),
        _stat('PENDING DRIVERS', '$pending', pending > 0 ? kRed : Colors.white54),
        _stat('TOTAL RIDES', '${rList.length}', Colors.white),
        _stat('PASSENGERS', '${_users.length}', Colors.white70),
      ]),
    ]);
  }

  Widget _driversTab() {
    final entries = _drivers.entries.where((e) => e.value is Map).toList();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (ctx, i) {
        final uid = entries[i].key;
        final d = (entries[i].value as Map).cast<String, dynamic>();
        final p = (d['profile'] as Map?)?.cast<String, dynamic>() ?? {};
        final verified = p['isVerified'] == true;
        final vType = (p['vehicleType'] ?? 'car').toString();
        final vModel = (p['vehicleModel'] ?? '').toString();
        final plate = (p['plateNumber'] ?? '').toString();
        return Card(
          color: kSurface,
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            title: Text('${p['fullName'] ?? d['name'] ?? 'Driver'} (${verified ? "VERIFIED" : "PENDING"})', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${vType.toUpperCase()} • $vModel • Plate: $plate\nPhone: ${p['phoneNumber'] ?? p['phone'] ?? '—'}'),
            trailing: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kOrange),
              onPressed: () => _editDriverDialog(uid, p),
              child: const Text('MANAGE', style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
        );
      },
    );
  }

  void _editDriverDialog(String uid, Map<String, dynamic> p) {
    String vType = (p['vehicleType'] ?? 'car').toString() == 'motorcycle' ? 'motorcycle' : 'car';
    final modelC = TextEditingController(text: (p['vehicleModel'] ?? '').toString());
    final colorC = TextEditingController(text: (p['vehicleColor'] ?? '').toString());
    final plateC = TextEditingController(text: (p['plateNumber'] ?? '').toString());
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: kSurface,
          title: Text((p['fullName'] ?? 'Verify & Assign Vehicle').toString()),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 8, children: [
                if (p['profileImageUrl'] != null) TextButton(onPressed: () => launchUrl(Uri.parse(p['profileImageUrl'])), child: const Text('View Face')),
                if (p['licenseImageUrl'] != null) TextButton(onPressed: () => launchUrl(Uri.parse(p['licenseImageUrl'])), child: const Text('View License')),
                if (p['vehicleImageUrl'] != null) TextButton(onPressed: () => launchUrl(Uri.parse(p['vehicleImageUrl'])), child: const Text('View Vehicle')),
              ]),
              Row(children: [
                Expanded(child: ChoiceChip(label: const Text('Car (K6.70)'), selected: vType == 'car', onSelected: (_) => setSt(() => vType = 'car'))),
                const SizedBox(width: 8),
                Expanded(child: ChoiceChip(label: const Text('Bike (K5.50)'), selected: vType == 'motorcycle', onSelected: (_) => setSt(() => vType = 'motorcycle'))),
              ]),
              const SizedBox(height: 8),
              TextField(controller: modelC, decoration: const InputDecoration(labelText: 'Make & Model (e.g. Toyota Wish)')),
              TextField(controller: colorC, decoration: const InputDecoration(labelText: 'Color')),
              TextField(controller: plateC, decoration: const InputDecoration(labelText: 'Plate Number')),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _patch('drivers/$uid/profile', {'isVerified': false, 'pendingApproval': false});
                if (mounted) Navigator.pop(ctx);
              },
              child: const Text('SUSPEND / REJECT', style: TextStyle(color: kRed)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kGreen),
              onPressed: () async {
                await _patch('drivers/$uid/profile', {
                  'isVerified': true,
                  'pendingApproval': false,
                  'vehicleType': vType,
                  'vehicleModel': modelC.text.trim(),
                  'vehicleColor': colorC.text.trim(),
                  'plateNumber': plateC.text.trim(),
                });
                if (mounted) Navigator.pop(ctx);
              },
              child: const Text('SAVE & VERIFY', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ridesTab() {
    final list = _rides.entries.where((e) => e.value is Map).toList()
      ..sort((a, b) => (((b.value as Map)['timestamp'] ?? 0) as num).compareTo(((a.value as Map)['timestamp'] ?? 0) as num));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final id = list[i].key;
        final r = (list[i].value as Map).cast<String, dynamic>();
        final status = (r['status'] ?? '').toString();
        final live = ['PENDING', 'ACCEPTED', 'IN_PROGRESS'].contains(status);
        final pin = (r['deliveryPin'] ?? '').toString();
        return Card(
          color: kSurface,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text('${r['pickupText'] ?? 'Pickup'} → ${r['dropoffText'] ?? 'Dropoff'} (${r['fare'] ?? ''})'),
            subtitle: Text('$status • ${_fmt(r['timestamp'])}${pin.isNotEmpty ? " • 📦 PIN: $pin" : ""}'),
            trailing: live
                ? ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: kRed),
                    onPressed: () => _patch('rides/$id', {'status': 'CANCELLED_BY_ADMIN'}),
                    child: const Text('END', style: TextStyle(color: Colors.white)),
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _usersTab() {
    final list = _users.entries.where((e) => e.value is Map).toList();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final u = (list[i].value as Map).cast<String, dynamic>();
        return Card(
          color: kSurface,
          child: ListTile(
            title: Text((u['name'] ?? u['displayName'] ?? 'Passenger').toString()),
            subtitle: Text((u['email'] ?? list[i].key).toString()),
          ),
        );
      },
    );
  }

  Widget _revTab() {
    final Map<String, double> unsettled = {};
    final Map<String, List<String>> rideIds = {};
    double totalGross = 0;
    for (final e in _rides.entries) {
      if (e.value is! Map) continue;
      final r = e.value as Map;
      if (r['status'] == 'COMPLETED') {
        final f = _fare(r['fare']);
        totalGross += f;
        if (r['payoutStatus'] == null && r['assignedDriverId'] != null) {
          final dId = r['assignedDriverId'].toString();
          unsettled[dId] = (unsettled[dId] ?? 0) + f;
          rideIds.putIfAbsent(dId, () => []).add(e.key);
        }
      }
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 10, runSpacing: 10, children: [
        _stat('ALL-TIME GROSS', 'K ${totalGross.toStringAsFixed(2)}', Colors.white),
        _stat('FLISING 10% SHARE', 'K ${(totalGross * 0.1).toStringAsFixed(2)}', kGreen),
      ]),
      const SizedBox(height: 20),
      const Text('UNSETTLED DRIVER WALLETS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 10),
      ...unsettled.entries.map((e) {
        final dName = (_drivers[e.key] is Map && _drivers[e.key]['profile'] is Map) ? (_drivers[e.key]['profile']['fullName'] ?? e.key) : e.key;
        return Card(
          color: kSurface,
          child: ListTile(
            title: Text('$dName • Gross: K ${e.value.toStringAsFixed(2)}'),
            subtitle: Text('Driver 90%: K ${(e.value * 0.9).toStringAsFixed(2)} | Flising 10%: K ${(e.value * 0.1).toStringAsFixed(2)}'),
            trailing: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kOrange),
              onPressed: () async {
                for (final id in rideIds[e.key]!) {
                  await _patch('rides/$id', {'payoutStatus': 'PAID'});
                }
              },
              child: const Text('SETTLE', style: TextStyle(color: Colors.white)),
            ),
          ),
        );
      }),
    ]);
  }
}
