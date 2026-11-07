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

  double _fare(dynamic v) => double.tryParse((v ?? '').toString().replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
  String _fmt(dynamic ts) => ts is num ? DateFormat('dd MMM, hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(ts.toInt())) : '—';

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      backgroundColor: isError ? kRed : kGreen,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_dashTab(), _driversTab(), _mapTab(), _ridesTab(), _usersTab(), _revTab()];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('FLISING ADMIN PORTAL', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: kOrange), tooltip: 'Sync Live', onPressed: _sync),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Sign Out', onPressed: widget.onLogout),
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
      width: 170,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(10), border: Border(top: BorderSide(color: col, width: 3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(val, style: TextStyle(color: col, fontSize: 20, fontWeight: FontWeight.bold)),
      ]),
    ));
  }

  // ================= DASHBOARD TAB =================
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
        _stat('TODAY GROSS', 'K ${today.toStringAsFixed(2)}', kGreen, onTap: () => setState(() => _tab = 5)),
        _stat('FLISING 10%', 'K ${(today * 0.1).toStringAsFixed(2)}', kOrange, onTap: () => setState(() => _tab = 5)),
        _stat('ONLINE DRIVERS', '$online / ${dList.length}', kGreen, onTap: () => setState(() => _tab = 1)),
        _stat('PENDING DRIVERS', '$pending', pending > 0 ? kRed : Colors.white54, onTap: () => setState(() => _tab = 1)),
        _stat('TOTAL RIDES', '${rList.length}', Colors.white, onTap: () => setState(() => _tab = 3)),
        _stat('PASSENGERS', '${_passengers.length}', Colors.white70, onTap: () => setState(() => _tab = 4)),
      ]),
    ]);
  }

  // ================= DRIVERS TAB =================
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
        final online = d['isOnline'] == true;
        final name = (p['fullName'] ?? d['name'] ?? 'Driver').toString();
        final vType = (p['vehicleType'] ?? 'car').toString();
        final model = (p['vehicleModel'] ?? '').toString();
        final plate = (p['plateNumber'] ?? '').toString();
        final photo = (p['profileImageUrl'] ?? '').toString();

        return Card(
          color: kSurface,
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: kSurface2,
              backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
              child: photo.isEmpty ? const Icon(Icons.person, color: Colors.white54) : null,
            ),
            title: Row(children: [
              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold))),
              if (online) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: kGreen.withOpacity(0.2), borderRadius: BorderRadius.circular(4)), child: const Text('ONLINE', style: TextStyle(color: kGreen, fontSize: 10, fontWeight: FontWeight.bold))),
            ]),
            subtitle: Text('${verified ? "✅ VERIFIED" : (pending ? "⏳ PENDING" : "❌ UNVERIFIED")} • $vType${model.isNotEmpty ? " • $model" : ""}${plate.isNotEmpty ? " • $plate" : ""}'),
            trailing: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kOrange),
              onPressed: () => _driverDetailDialog(uid, d),
            ),
            onTap: () => _driverDetailDialog(uid, d
              child: const Text('PROFILE', style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
        );
      },
    );
  }

  void _driverDetailDialog(String uid, Map<String, dynamic> d) {
    final p = (d['profile'] as Map?)?.cast<String, dynamic>() ?? {};
    String vType = (p['vehicleType'] ?? 'car').toString().toLowerCase() == 'motorcycle' ? 'motorcycle' : 'car';
    final modelC = TextEditingController(text: (p['vehicleModel'] ?? '').toString());
    final colorC = TextEditingController(text: (p['vehicleColor'] ?? '').toString());
    final plateC = TextEditingController(text: (p['plateNumber'] ?? '').toString());
    final phoneC = TextEditingController(text: (p['phoneNumber'] ?? p['phone'] ?? '').toString());

    final driverRides = _rides.entries.where((e) => e.value is Map && (e.value as Map)['assignedDriverId'] == uid).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: kSurface,
          title: Text((p['fullName'] ?? 'Driver Details').toString()),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                const Text('VERIFICATION PHOTOS', style: TextStyle(color: kOrange, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(children: [
                  if (p['profileImageUrl'] != null) TextButton(onPressed: () => launchUrl(Uri.parse(p['profileImageUrl'])), child: const Text('Face')),
                  if (p['licenseImageUrl'] != null) TextButton(onPressed: () => launchUrl(Uri.parse(p['licenseImageUrl'])), child: const Text('License')),
                  if (p['vehicleImageUrl'] != null) TextButton(onPressed: () => launchUrl(Uri.parse(p['vehicleImageUrl'])), child: const Text('Vehicle')),
                ]),
                const Divider(color: Colors.white12),
                const Text('VEHICLE & RATE ASSIGNMENT', style: TextStyle(color: kOrange, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: ChoiceChip(label: const Text('Car (K6.70)'), selected: vType == 'car', selectedColor: kOrange, onSelected: (_) => setSt(() => vType = 'car'))),
                  const SizedBox(width: 8),
                  Expanded(child: ChoiceChip(label: const Text('Bike (K5.50)'), selected: vType == 'motorcycle', selectedColor: kOrange, onSelected: (_) => setSt(() => vType = 'motorcycle'))),
                ]),
                const SizedBox(height: 10),
                TextField(controller: modelC, decoration: const InputDecoration(labelText: 'Make & Model (e.g. Toyota Wish)', filled: true, fillColor: kSurface2)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: colorC, decoration: const InputDecoration(labelText: 'Color', filled: true, fillColor: kSurface2))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: plateC, decoration: const InputDecoration(labelText: 'Plate No', filled: true, fillColor: kSurface2))),
                ]),
                const SizedBox(height: 8),
                TextField(controller: phoneC, decoration: const InputDecoration(labelText: 'Phone Number', filled: true, fillColor: kSurface2)),
                const Divider(color: Colors.white12, height: 24),
                Text('ALL-TIME HISTORY (${driverRides.length} trips)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                ...driverRides.map((e) {
                  final r = e.value as Map;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• ${r['pickupText'] ?? ''} → ${r['dropoffText'] ?? ''} (${r['fare'] ?? ''}) - ${r['status'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  );
                }),
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _patch('drivers/$uid/profile', {'isVerified': false, 'pendingApproval': false});
                if (mounted) Navigator.pop(ctx);
                _snack('Driver unverified/suspended', isError: true);
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
                _snack('Saved & Verified driver successfully!');
              },
              child: const Text('SAVE & VERIFY', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ================= LIVE MAP TAB =================
  Widget _mapTab() {
    final List<Marker> markers = [];

    // Add online drivers with profile pictures
    _drivers.forEach((uid, val) {
      if (val is! Map) return;
      final lat = val['latitude'];
      final lng = val['longitude'];
      if (lat is num && lng is num) {
        final profile = (val['profile'] as Map?)?.cast<String, dynamic>() ?? {};
        final photo = (profile['profileImageUrl'] ?? '').toString();
        final name = (profile['fullName'] ?? val['name'] ?? 'Driver').toString();

        markers.add(Marker(
          point: LatLng(lat.toDouble(), lng.toDouble()),
          width: 50,
          height: 50,
          child: GestureDetector(
            onTap: () {
              final dMap = val.cast<String, dynamic>();
              setState(() => _tab = 1);
              Future.microtask(() => _driverDetailDialog(uid, dMap));
            },
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: kOrange, width: 3),
                color: kSurface,
              ),
              clipBehavior: Clip.antiAlias,
              child: photo.isNotEmpty
                  ? Image.network(photo, fit: BoxFit.cover)
                  : const Icon(Icons.directions_car, color: Colors.white, size: 24),
            ),
          ),
        ));
      }
    });

    // Add passengers ONLY when ride is IN_PROGRESS (driver tapped Pickup Passenger)
    _rides.forEach((rideId, rVal) {
      if (rVal is! Map || rVal['status'] != 'IN_PROGRESS') return;
      final dId = rVal['assignedDriverId']?.toString();
      final dObj = dId != null ? _drivers[dId] : null;
      final lat = (dObj is Map && dObj['latitude'] is num) ? dObj['latitude'] : rVal['pickupLat'];
      final lng = (dObj is Map && dObj['longitude'] is num) ? dObj['longitude'] : rVal['pickupLng'];
      if (lat is num && lng is num) {
        final pName = (rVal['passengerName'] ?? 'Passenger').toString();
        markers.add(Marker(
          point: LatLng(lat.toDouble() + 0.00035, lng.toDouble() + 0.00035),
          width: 110,
          height: 54,
          child: GestureDetector(
            onTap: () => setState(() => _tab = 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(6)),
                  child: Text('🧑 $pName', overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
                const Icon(Icons.person_pin_circle, color: kGreen, size: 30),
              ],
            ),
          ),
        ));
      }
    });

    return FlutterMap(
      options: const MapOptions(
        initialCenter: LatLng(-2.6833, 141.3000), // Vanimo / Wutung Region
        initialZoom: 13.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.flising.admin',
        ),
        MarkerLayer(markers: markers),
      ],
    );
  }

  // ================= RIDES TAB =================
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
            subtitle: Text('$status • Passenger: ${r['passengerName'] ?? '—'} • ${_fmt(r['timestamp'])}${pin.isNotEmpty ? " • 📦 PIN: $pin" : ""}'),
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

  // ================= USERS TAB =================
  Widget _usersTab() {
    final list = _passengers.entries.where((e) => e.value is Map).toList();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final uid = list[i].key;
        final u = (list[i].value as Map).cast<String, dynamic>();
        final name = (u['name'] ?? u['displayName'] ?? 'Passenger').toString();
        final email = (u['email'] ?? uid).toString();
        final phone = (u['phoneNumber'] ?? u['phone'] ?? 'No phone').toString();
        final passengerRides = _rides.entries.where((e) => e.value is Map && (e.value as Map)['passengerId'] == uid).toList();

        return Card(
          color: kSurface,
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('$email • $phone\n${passengerRides.length} total rides'),
            trailing: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kOrange),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: kSurface,
                    title: Text(name),
                    content: SizedBox(
                      width: 400,
                      child: SingleChildScrollView(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text('Email: $email', style: const TextStyle(color: Colors.white70)),
                          Text('Phone: $phone', style: const TextStyle(color: Colors.white70)),
                          const Divider(color: Colors.white12),
                          const Text('RIDE HISTORY', style: TextStyle(fontWeight: FontWeight.bold, color: kOrange)),
                          const SizedBox(height: 6),
                          ...passengerRides.map((e) {
                            final r = e.value as Map;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text('• ${r['pickupText'] ?? ''} → ${r['dropoffText'] ?? ''} (${r['fare'] ?? ''}) - ${r['status'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                            );
                          }),
                        ]),
                      ),
                    ),
                    actions: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: kOrange),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('CLOSE', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('HISTORY', style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
        );
      },
    );
  }

  // ================= REVENUE TAB =================
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
