import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/env_config.dart';
import '../../../core/state/haven_link_store.dart';

class AdminRoomInventoryScreen extends StatefulWidget {
  const AdminRoomInventoryScreen({required this.store, super.key});

  final HavenLinkStore store;

  @override
  State<AdminRoomInventoryScreen> createState() =>
      _AdminRoomInventoryScreenState();
}

class _AdminRoomInventoryScreenState extends State<AdminRoomInventoryScreen> {
  late Future<List<Map<String, dynamic>>> _inventory = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final token = widget.store.authenticationRepository.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError(
        'Sign in as an administrator to inspect room inventory.',
      );
    }
    final response = await http
        .get(
          EnvConfig.endpoint('/api/v1/admin/room-inventory'),
          headers: {'authorization': '******'},
        )
        .timeout(const Duration(seconds: 20));
    final decoded = jsonDecode(response.body);
    if (response.statusCode != 200 ||
        decoded is! Map<String, dynamic> ||
        decoded['inventory'] is! List<dynamic>) {
      final message = decoded is Map<String, dynamic>
          ? decoded['error'] as String?
          : null;
      throw StateError(message ?? 'Admin room inventory request failed.');
    }
    return (decoded['inventory'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _inventory,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(snapshot.error.toString()),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => setState(() => _inventory = _load()),
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      }
      final entries = snapshot.data ?? const [];
      if (entries.isEmpty) {
        return const Center(
          child: Text('No hotel, motel, or lodge inventory.'),
        );
      }
      return RefreshIndicator(
        onRefresh: () async => setState(() => _inventory = _load()),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Room and reservation oversight. Guest names and contact details are not shown here.',
            ),
            const SizedBox(height: 12),
            for (final entry in entries) _PropertyInventoryCard(entry: entry),
          ],
        ),
      );
    },
  );
}

class _PropertyInventoryCard extends StatelessWidget {
  const _PropertyInventoryCard({required this.entry});

  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final property = entry['property'] as Map<String, dynamic>? ?? const {};
    final rooms = (entry['rooms'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final bookings = (entry['bookings'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    return Card(
      child: ExpansionTile(
        title: Text(property['name'] as String? ?? 'Accommodation'),
        subtitle: Text(
          '${property['category'] ?? 'stay'} · ${property['listingStatus'] ?? 'unknown'} · '
          '${entry['assignedRooms'] ?? 0}/${entry['totalRooms'] ?? 0} rooms assigned',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Wrap(
            spacing: 8,
            children: [
              Chip(label: Text('Rooms: ${entry['totalRooms'] ?? 0}')),
              Chip(
                label: Text(
                  'Out of service: ${entry['outOfServiceRooms'] ?? 0}',
                ),
              ),
              Chip(label: Text('Active bookings: ${bookings.length}')),
            ],
          ),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Physical rooms',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          for (final room in rooms)
            ListTile(
              dense: true,
              title: Text(
                'Room ${room['roomNumber']} · ${room['category'] ?? 'Unassigned'}',
              ),
              subtitle: Text(
                '${room['floor'] ?? 'Floor not set'} · ${room['status'] ?? 'active'}',
              ),
            ),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Reservations',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          for (final booking in bookings)
            ListTile(
              dense: true,
              title: Text(
                '${booking['category'] ?? 'Room category pending'} · '
                '${booking['assignedRoom'] == null ? 'Room assignment pending' : 'Room ${booking['assignedRoom']}'}',
              ),
              subtitle: Text(
                '${booking['checkIn']} – ${booking['checkOut']} · ${booking['status']}',
              ),
            ),
        ],
      ),
    );
  }
}
