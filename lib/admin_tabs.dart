import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'main.dart';

class AdminHome extends StatefulWidget {
  final String token;
  final String refreshToken;
  final String adminEmail;
  final VoidCallback onLogout;
  const AdminHome({
    super.key,
    required this.token,
    required this.refreshToken,
    this.adminEmail = 'allendii57@gmail.com',
    required this.onLogout,
  });
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _tab = 0;
  late String _tok;
  Timer? _timer;
  Map<String, dynamic> _drivers = {};
  Map<String, dynamic> _rides = {};
  Map<String, dynamic> _passengers = {};

  @override
  void initState() {
    super.initState();
    _tok = widget.token;
    _sync();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _sync());
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
        http.get(Uri.parse('$kDbUrl/users/passengers.json?auth=$_tok')),
      ]);
      if (!mounted) return;
      setState(() {
        _drivers = (jsonDecode(res[0].body) as Map?)?.cast<String, dynamic>() ?? {};
        _rides = (jsonDecode(res[1].body) as Map?)?.cast<String, dynamic>() ?? {};
        _passengers = (jsonDecode(res[2].body) as Map?)?.cast<String, dynamic>() ?? {};
      });
    } catch (_) {}
  }

  Future<void> _patch(String path, Map<String, dynamic> body) async {
    await http.patch(Uri.parse('$kDbUrl/$path.json?auth=$_tok'), body: jsonEncode(body));
    await _sync();
  }

  Future<void> _deleteNode(String path) async {
    await http.delete(Uri.parse('$kDbUrl/$path.json?auth=$_tok'));
    await _sync();
  }

  double _fare(dynamic v) => double.tryParse((v ?? '').toString().replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
  String _fmt(dynamic ts) => ts is num ? DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(ts.toInt())) : 'No date';

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      backgroundColor: isError ? kRed : kGreen,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _confirmAndDelete({
    required String title,
    required String targetName,
    required Future<void> Function() onVerifiedDelete,
  }) async {
    final passCtrl = TextEditingController();
    bool checking = false;
    String? errText;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: kSurface,
          title: Text(title, style: const TextStyle(color: kRed, fontWeight: FontWeight.bold, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Permanently delete "$targetName"?'),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(hintText: 'Enter Admin Password', filled: true, fillColor: kSurface2),
              ),
              if (errText != null)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(errText!, style: const TextStyle(color: kRed, fontSize: 12))),
            ],
          ),
          actions: [
            TextButton(onPressed: checking ? null : () => Navigator.pop(ctx), child: const Text('CANCEL')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kRed),
              onPressed: checking
                  ? null
                  : () async {
                      if (passCtrl.text.isEmpty) {
                        setSt(() => errText = 'Password required');
                        return;
                      }
                      setSt(() { checking = true; errText = null; });
                      final email = widget.adminEmail.isNotEmpty ? widget.adminEmail : 'allendii57@gmail.com';
                      final r = await http.post(
                        Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$kApiKey'),
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode({'email': email, 'password': passCtrl.text, 'returnSecureToken': true}),
                      );
                      if (r.statusCode != 200) {
                        setSt(() { checking = false; errText = 'Wrong admin password!'; });
                        return;
                      }
                      await onVerifiedDelete();
                      if (mounted) Navigator.pop(ctx);
                      _snack('Deleted $targetName');
                    },
              child: const Text('DELETE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, double> _calcPeriods(Iterable completedRides) {
    final now = DateTime.now();
    final cut7 = now.subtract(const Duration(days: 7));
    final cut14 = now.subtract(const Duration(days: 14));
    final cut30 = now.subtract(const Duration(days: 30));
    double today = 0, w1 = 0, w2 = 0, m1 = 0, total = 0;
    for (final r in completedRides) {
      if (r['status'] != 'COMPLETED') continue;
      final f = _fare(r['fare']);
      total += f;
      if (r['timestamp'] is num) {
        final dt = DateTime.fromMillisecondsSinceEpoch((r['timestamp'] as num).toInt());
        if (dt.year == now.year && dt.month == now.month && dt.day == now.day) today += f;
        if (dt.isAfter(cut7)) w1 += f;
        if (dt.isAfter(cut14)) w2 += f;
        if (dt.isAfter(cut30)) m1 += f;
      }
    }
    return {'today': today, 'w1': w1, 'w2': w2, 'm1': m1, 'total': total};
  }

  Widget _periodCard(String title, double gross) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: kOrange, fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Gross: K ${gross.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          Text('Driver 90%: K ${(gross * 0.9).toStringAsFixed(2)}', style: const TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.bold)),
          Text('Flising 10%: K ${(gross * 0.1).toStringAsFixed(2)}', style: const TextStyle(color: kOrange, fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_dashTab(), _driversTab(), _mapTab(), _ridesTab(), _usersTab(), _revTab()];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('FLISING ADMIN PORTAL', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
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
        selectedFontSize: 11,
        unselectedFontSize: 10,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.directions_car_outlined), label: 'Drivers'),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: 'Live Map'),
          BottomNavigationBarItem(icon: Icon(Icons.route_outlined), label: 'Rides'),
          BottomNavigationBarItem(icon: Icon(Icons.people_outline), label: 'Users'),
          BottomNavigationBarItem(icon: Icon(Icons.payments_outlined), label: 'Revenue'),
        ],
      ),
    );
  }

  Widget _stat(String label, String val, Color col, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 165,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(10), border: Border(top: BorderSide(color: col, width: 3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(val, style: TextStyle(color: col, fontSize: 20, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _dashTab() {
    final rList = _rides.values.whereType().toList();
    final dList = _drivers.values.whereType().toList();
    final p = _calcPeriods(rList);
    final verified = dList.where((d) => (d['profile'] is Map) && d['profile']['isVerified'] == true).toList();
    final online = verified.where((d) => d['isOnline'] == true).length;
    final pending = dList.where((d) => (d['profile'] is Map) && d['profile']['pendingApproval'] == true && d['profile']['isVerified'] != true).length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 10, runSpacing: 10, children: [
        _stat('TODAY GROSS', 'K ${p['today']!.toStringAsFixed(2)}', kGreen, onTap: () => setState(() => _tab = 5)),
        _stat('FLISING 10%', 'K ${(p['today']! * 0.1).toStringAsFixed(2)}', kOrange, onTap: () => setState(() => _tab = 5)), _stat('ONLINE DRIVERS', '$online / ${verified.length}', kGreen, onTap: () => setState(() => _tab = 2)), _stat('PENDING DRIVERS', '$pending', pending > 0 ? kRed : Colors.white54, onTap: () => setState(() => _tab = 1)),
        _stat('TOTAL RIDES', '${rList.length}', Colors.white, onTap: () => setState(() => _tab = 3)), _stat('PASSENGERS', '${_passengers.length}', Colors.white70, onTap: () => setState(() => _tab = 4)),
      ]),
      const SizedBox(height: 18),
      _periodCard('WEEKLY (LAST 7 DAYS)', p['w1']!),
      _periodCard('2 WEEKS (LAST 14 DAYS)', p['w2']!),
      _periodCard('MONTHLY (LAST 30 DAYS)', p['m1']!),
      _periodCard('ALL-TIME TOTAL', p['total']!),
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
        final pending = p['pendingApproval'] == true && !verified;
        final online = d['isOnline'] == true && verified;
        final name = (p['fullName'] ?? d['name'] ?? 'Driver').toString();
        final vType = (p['vehicleType'] ?? 'car').toString();
        final photo = (p['profileImageUrl'] ?? '').toString();

        return Card(
          color: kSurface,
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            onTap: () => _driverDetailDialog(uid, d),
            leading: CircleAvatar(
              backgroundColor: kSurface2,
              backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
              child: photo.isEmpty ? const Icon(Icons.person, color: Colors.white54) : null,
            ),
            title: Text('$name ${online ? "🟢 ONLINE" : ""}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${verified ? "✅ VERIFIED" : (pending ? "⏳ PENDING" : "❌ UNVERIFIED")} • $vType'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: kOrange),
                  onPressed: () => _driverDetailDialog(uid, d),
                  child: const Text('PROFILE', style: TextStyle(color: Colors.white, fontSize: 11)),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: kRed),
                  onPressed: () => _confirmAndDelete(
                    title: 'DELETE DRIVER',
                    targetName: name,
                    onVerifiedDelete: () => _deleteNode('drivers/$uid'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _driverDetailDialog(String uid, Map<String, dynamic> d) {
    final p = (d['profile'] as Map?)?.cast<String, dynamic>() ?? {};
    final name = (p['fullName'] ?? d['name'] ?? 'Driver').toString();
    String vType = (p['vehicleType'] ?? 'car').toString().toLowerCase() == 'motorcycle' ? 'motorcycle' : 'car';
    final modelC = TextEditingController(text: (p['vehicleModel'] ?? '').toString());
    final colorC = TextEditingController(text: (p['vehicleColor'] ?? '').toString());
    final plateC = TextEditingController(text: (p['plateNumber'] ?? '').toString());
    final phoneC = TextEditingController(text: (p['phoneNumber'] ?? p['phone'] ?? '').toString());

    final driverRides = _rides.entries
        .where((e) => e.value is Map && (e.value as Map)['assignedDriverId'] == uid)
        .toList()
      ..sort((a, b) => (((b.value as Map)['timestamp'] ?? 0) as num).compareTo(((a.value as Map)['timestamp'] ?? 0) as num));
    final stats = _calcPeriods(driverRides.map((e) => e.value as Map));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: kSurface,
          title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(child: Text(name)),
            IconButton(
              icon: const Icon(Icons.delete_forever, color: kRed),
              onPressed: () {
                Navigator.pop(ctx);
                _confirmAndDelete(title: 'DELETE DRIVER', targetName: name, onVerifiedDelete: () => _deleteNode('drivers/$uid'));
              },
            ),
          ]),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Wrap(spacing: 8, children: [
                  if (p['profileImageUrl'] != null) TextButton(onPressed: () => launchUrl(Uri.parse(p['profileImageUrl'])), child: const Text('Face')),
                  if (p['licenseImageUrl'] != null) TextButton(onPressed: () => launchUrl(Uri.parse(p['licenseImageUrl'])), child: const Text('License')),
                  if (p['vehicleImageUrl'] != null) TextButton(onPressed: () => launchUrl(Uri.parse(p['vehicleImageUrl'])), child: const Text('Vehicle')),
                ]),
                _periodCard('WEEKLY (7 DAYS)', stats['w1']!),
                _periodCard('2 WEEKS (14 DAYS)', stats['w2']!),
                _periodCard('MONTHLY (30 DAYS)', stats['m1']!),
                _periodCard('ALL-TIME TOTAL', stats['total']!),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: ChoiceChip(label: const Text('Car (K6.70)'), selected: vType == 'car', selectedColor: kOrange, onSelected: (_) => setSt(() => vType = 'car'))),
                  const SizedBox(width: 8),
                  Expanded(child: ChoiceChip(label: const Text('Bike (K5.50)'), selected: vType == 'motorcycle', selectedColor: kOrange, onSelected: (_) => setSt(() => vType = 'motorcycle'))),
                ]),
                const SizedBox(height: 8),
                TextField(controller: modelC, decoration: const InputDecoration(labelText: 'Make & Model', filled: true, fillColor: kSurface2)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: TextField(controller: colorC, decoration: const InputDecoration(labelText: 'Color', filled: true, fillColor: kSurface2))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: plateC, decoration: const InputDecoration(labelText: 'Plate No', filled: true, fillColor: kSurface2))),
                ]),
                const SizedBox(height: 6),
                TextField(controller: phoneC, decoration: const InputDecoration(labelText: 'Phone Number', filled: true, fillColor: kSurface2)),
                const Divider(color: Colors.white12, height: 20),
                Text('ALL-TIME HISTORY (${driverRides.length} trips)', style: const TextStyle(color: kOrange, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                ...driverRides.map((e) {
                  final r = e.value as Map;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• [${_fmt(r['timestamp'])}] ${r['pickupText'] ?? ''} → ${r['dropoffText'] ?? ''} (${r['fare'] ?? ''}) - ${r['status'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  );
                }),
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _patch('drivers/$uid/profile', {'isVerified': false, 'pendingApproval': false});
                await _patch('drivers/$uid', {'isOnline': false});
                if (mounted) Navigator.pop(ctx);
              },
              child: const Text('SUSPEND', style: TextStyle(color: kRed)),
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
                  if (phoneC.text.trim().isNotEmpty) 'phoneNumber': phoneC.text.trim(),
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

  Widget _mapTab() {
    final List<Marker> markers = [];
    _drivers.forEach((uid, val) {
      if (val is! Map) return;
      final profile = (val['profile'] as Map?)?.cast<String, dynamic>() ?? {};
      if (val['isOnline'] != true || profile['isVerified'] != true) return;
      final lat = val['latitude'];
      final lng = val['longitude'];
      if (lat is num && lng is num) {
        final photo = (profile['profileImageUrl'] ?? '').toString();
        final dMap = val.cast<String, dynamic>();
        markers.add(Marker(
          point: LatLng(lat.toDouble(), lng.toDouble()),
          width: 50,
          height: 50,
          child: GestureDetector(
            onTap: () {
              setState(() => _tab = 1);
              Future.microtask(() => _driverDetailDialog(uid, dMap));
            },
            child: Container(
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kGreen, width: 3), color: kSurface),
              clipBehavior: Clip.antiAlias,
              child: photo.isNotEmpty ? Image.network(photo, fit: BoxFit.cover) : const Icon(Icons.directions_car, color: Colors.white),
            ),
          ),
        ));
      }
    });

    _rides.forEach((rideId, rVal) {
      if (rVal is! Map || rVal['status'] != 'IN_PROGRESS') return;
      final dId = rVal['assignedDriverId']?.toString();
      final dObj = dId != null ? _drivers[dId] : null;
      final lat = (dObj is Map && dObj['latitude'] is num) ? dObj['latitude'] : rVal['pickupLat'];
      final lng = (dObj is Map && dObj['longitude'] is num) ? dObj['longitude'] : rVal['pickupLng'];
      if (lat is num && lng is num) {
        markers.add(Marker(
          point: LatLng(lat.toDouble() + 0.00035, lng.toDouble() + 0.00035),
          width: 90,
          height: 50,
          child: GestureDetector(
            onTap: () => setState(() => _tab = 4),
            child: const Icon(Icons.person_pin_circle, color: kOrange, size: 34),
          ),
        ));
      }
    });

    return FlutterMap(
      options: const MapOptions(initialCenter: LatLng(-2.6833, 141.3000), initialZoom: 14.0),
      children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.flising.admin'),
        MarkerLayer(markers: markers),
      ],
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
            subtitle: Text('${_fmt(r['timestamp'])} • $status • Passenger: ${r['passengerName'] ?? '—'}${pin.isNotEmpty ? " • PIN: $pin" : ""}'),
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
    final list = _passengers.entries.where((e) => e.value is Map).toList();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final uid = list[i].key;
        final u = (list[i].value as Map).cast<String, dynamic>();
        final name = (u['fullName'] ?? u['name'] ?? u['displayName'] ?? 'Passenger').toString();
        final email = (u['email'] ?? uid).toString();
        final phone = (u['phoneNumber'] ?? u['phone'] ?? 'No phone').toString();
        final pRides = _rides.entries
            .where((e) => e.value is Map && (e.value as Map)['passengerId'] == uid)
            .toList()
          ..sort((a, b) => (((b.value as Map)['timestamp'] ?? 0) as num).compareTo(((a.value as Map)['timestamp'] ?? 0) as num));

        void openModal() {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: kSurface,
              title: Text(name),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text('Email: $email\nPhone: $phone'),
                    const Divider(color: Colors.white12),
                    ...pRides.map((e) {
                      final r = e.value as Map;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('• [${_fmt(r['timestamp'])}] ${r['pickupText'] ?? ''} → ${r['dropoffText'] ?? ''} (${r['fare'] ?? ''}) - ${r['status'] ?? ''}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                      );
                    }),
                  ]),
                ),
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE'))],
            ),
          );
        }

        return Card(
          color: kSurface,
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            onTap: openModal,
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('$email • $phone (${pRides.length} rides)'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kOrange), onPressed: openModal, child: const Text('HISTORY', style: TextStyle(color: Colors.white, fontSize: 11))),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: kRed),
                onPressed: () => _confirmAndDelete(
                  title: 'DELETE PASSENGER',
                  targetName: name,
                  onVerifiedDelete: () async {
                    await _deleteNode('users/passengers/$uid');
                    await _deleteNode('passengers/$uid');
                  },
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _revTab() {
    final rList = _rides.values.whereType().toList();
    final p = _calcPeriods(rList);
    final Map<String, double> unsettled = {};
    final Map<String, List<String>> rideIds = {};
    for (final e in _rides.entries) {
      if (e.value is! Map) continue;
      final r = e.value as Map;
      if (r['status'] == 'COMPLETED' && r['payoutStatus'] == null && r['assignedDriverId'] != null) {
        final dId = r['assignedDriverId'].toString();
        unsettled[dId] = (unsettled[dId] ?? 0) + _fare(r['fare']);
        rideIds.putIfAbsent(dId, () => []).add(e.key);
      }
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('PLATFORM EARNINGS BREAKDOWN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      const SizedBox(height: 10),
      _periodCard('TODAY', p['today']!),
      _periodCard('WEEKLY (LAST 7 DAYS)', p['w1']!),
      _periodCard('2 WEEKS (LAST 14 DAYS)', p['w2']!),
      _periodCard('MONTHLY (LAST 30 DAYS)', p['m1']!),
      _periodCard('ALL-TIME TOTAL', p['total']!),
      const SizedBox(height: 16),
      const Text('UNSETTLED DRIVER WALLETS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      const SizedBox(height: 8),
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
                _snack('Settled payouts for $dName!');
              },
              child: const Text('SETTLE', style: TextStyle(color: Colors.white)),
            ),
          ),
        );
      }),
    ]);
  }
}
