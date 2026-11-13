import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';
import 'package:http/http.dart' as http;

import '../../../../core/config/env_config.dart';
import '../../../../core/formatters/currency_formatter.dart';
import '../../../../core/theme/app_theme.dart';
import 'property_map.dart';
import 'property_photo.dart';

/// Main photo, thumbnail strip and a full-screen zoomable viewer.
class PropertyGallery extends StatefulWidget {
  const PropertyGallery({
    required this.photos,
    this.badge,
    this.labels = const {},
    this.height = 300,
    this.mosaic = false,
    super.key,
  });

  final List<String> photos;
  final Widget? badge;
  final Map<String, String> labels;
  final double height;
  final bool mosaic;

  @override
  State<PropertyGallery> createState() => _PropertyGalleryState();
}

class _PropertyGalleryState extends State<PropertyGallery> {
  var _selected = 0;

  List<String> get _photos {
    final seen = <String>{};
    return widget.photos
        .where((url) => url.trim().isNotEmpty && seen.add(url))
        .toList(growable: false);
  }

  void _openViewer(List<String> photos, {int? initialIndex}) {
    showDialog<void>(
      context: context,
      builder: (context) =>
          _PhotoViewer(photos: photos, initialIndex: initialIndex ?? _selected),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    final index = _selected < photos.length ? _selected : 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final mosaic =
            widget.mosaic && photos.length >= 3 && constraints.maxWidth >= 600;
        Widget tile(int photoIndex) => Semantics(
          button: true,
          label: 'Open photo ${photoIndex + 1}',
          child: InkWell(
            onTap: () => _openViewer(photos, initialIndex: photoIndex),
            child: PropertyPhoto(
              imageUrl: photos[photoIndex],
              height: mosaic ? 420 : widget.height,
            ),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  if (mosaic)
                    SizedBox(
                      height: 420,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: tile(0)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: tile(1)),
                                const SizedBox(height: 8),
                                Expanded(child: tile(2)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: photos.isEmpty ? null : () => _openViewer(photos),
                      child: Semantics(
                        button: true,
                        label: 'Open photo viewer',
                        child: PropertyPhoto(
                          imageUrl: photos.isEmpty ? '' : photos[index],
                          height: widget.height,
                        ),
                      ),
                    ),
                  if (widget.badge != null)
                    Positioned(top: 14, left: 14, child: widget.badge!),
                  if (photos.isNotEmpty && widget.labels[photos[index]] != null)
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          widget.labels[photos[index]]!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  if (photos.length > 1)
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${index + 1} / ${photos.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (photos.length > 1 && !mosaic) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => GestureDetector(
                    onTap: () => setState(() => _selected = i),
                    child: Semantics(
                      button: true,
                      label: 'Show photo ${i + 1}',
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: i == index
                                ? HavenTheme.forest
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 84,
                            child: PropertyPhoto(
                              imageUrl: photos[i],
                              height: 64,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.photos, required this.initialIndex});

  final List<String> photos;
  final int initialIndex;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late var _page = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final target = _page + delta;
    if (target < 0 || target >= widget.photos.length) return;
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.photos.length,
            onPageChanged: (value) => setState(() => _page = value),
            itemBuilder: (context, i) => InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Image.network(
                  widget.photos[i],
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    HavenIcons.brokenImageOutlined,
                    color: Colors.white54,
                    size: 56,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: IconButton.filledTonal(
              tooltip: 'Close photo viewer',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(HavenIcons.close),
            ),
          ),
          if (widget.photos.length > 1) ...[
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton.filledTonal(
                  tooltip: 'Previous photo',
                  onPressed: _page > 0 ? () => _go(-1) : null,
                  icon: const Icon(HavenIcons.chevronLeft),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton.filledTonal(
                  tooltip: 'Next photo',
                  onPressed: _page < widget.photos.length - 1
                      ? () => _go(1)
                      : null,
                  icon: const Icon(HavenIcons.chevronRight),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: Center(
                child: Text(
                  '${_page + 1} / ${widget.photos.length}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Map plus quick searches for essential services around the listing area.
/// Searches use the public area label, never private coordinates.
class NearbyMap extends StatefulWidget {
  const NearbyMap({
    required this.locationQuery,
    required this.zoom,
    required this.areaLabel,
    super.key,
  });

  final String locationQuery;
  final int zoom;
  final String areaLabel;

  @override
  State<NearbyMap> createState() => _NearbyMapState();
}

class _NearbyMapState extends State<NearbyMap> {
  static const _services = <(String, String, IconData)>[
    ('Hospitals', 'hospitals', HavenIcons.localHospitalOutlined),
    ('Pharmacies', 'pharmacies', HavenIcons.medicationOutlined),
    ('Schools', 'schools', HavenIcons.schoolOutlined),
    ('Universities', 'universities', HavenIcons.accountBalanceOutlined),
    ('Supermarkets', 'supermarkets', HavenIcons.localGroceryStoreOutlined),
    ('Transport', 'bus stops', HavenIcons.directionsBusOutlined),
    ('Banks & ATMs', 'banks and ATMs', HavenIcons.atmOutlined),
  ];

  String? _query;

  @override
  Widget build(BuildContext context) {
    final nearby = _query;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PropertyMapFrame(
          locationQuery: nearby == null
              ? widget.locationQuery
              : '$nearby near ${widget.areaLabel}',
          zoom: nearby == null ? widget.zoom : 14,
        ),
        const SizedBox(height: 12),
        Text(
          'Find nearby services',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              avatar: const Icon(HavenIcons.homeOutlined, size: 18),
              label: const Text('Property'),
              selected: nearby == null,
              onSelected: (_) => setState(() => _query = null),
            ),
            for (final (label, query, icon) in _services)
              ChoiceChip(
                avatar: Icon(icon, size: 18),
                label: Text(label),
                selected: nearby == query,
                onSelected: (_) => setState(() => _query = query),
              ),
          ],
        ),
      ],
    );
  }
}

/// Check-in policy and room types for bookable stays, read from the public
/// stay-information endpoint.
class StayInfoSection extends StatefulWidget {
  const StayInfoSection({required this.propertyId, super.key});

  final String propertyId;

  @override
  State<StayInfoSection> createState() => _StayInfoSectionState();
}

class _StayInfoSectionState extends State<StayInfoSection> {
  late Future<Map<String, dynamic>> _info = _load();

  Future<Map<String, dynamic>> _load() async {
    if (!EnvConfig.backendConfigured) {
      throw StateError('Backend is not configured.');
    }
    final response = await http
        .get(
          EnvConfig.endpoint(
            '/api/v1/properties/${Uri.encodeComponent(widget.propertyId)}/stay-info',
          ),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('Stay information request failed.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Unexpected stay information response.');
    }
    return decoded;
  }

  String _hours(Object? value) => (value as num?) == null
      ? 'Free cancellation window not set'
      : 'Free cancellation up to $value hours before check-in';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _info,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Row(
            children: [
              const Expanded(
                child: Text('Stay information is unavailable right now.'),
              ),
              IconButton(
                tooltip: 'Retry loading stay information',
                onPressed: () => setState(() => _info = _load()),
                icon: const Icon(HavenIcons.refresh),
              ),
            ],
          );
        }
        final data = snapshot.data!;
        final policy = (data['policy'] as Map<String, dynamic>?) ?? const {};
        final rooms = (data['roomTypes'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
        final notes = (policy['notes'] as String? ?? '').trim();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                _InfoFact(
                  icon: HavenIcons.login,
                  label: 'Check-in from ${policy['checkInFrom'] ?? '14:00'}',
                ),
                _InfoFact(
                  icon: HavenIcons.logout,
                  label: 'Check-out by ${policy['checkOutBy'] ?? '11:00'}',
                ),
                _InfoFact(
                  icon: HavenIcons.eventBusyOutlined,
                  label: _hours(policy['cancellationHours']),
                ),
                _InfoFact(
                  icon: HavenIcons.schedule,
                  label: policy['allowLateCheckout'] == true
                      ? 'Late check-out may be arranged'
                      : 'Late check-out not offered',
                ),
              ],
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(notes, style: const TextStyle(height: 1.5)),
            ],
            const SizedBox(height: 16),
            Text('Rooms', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (rooms.isEmpty)
              const Text('Room options will be listed by the host soon.')
            else
              for (final room in rooms)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: _RoomCategoryPhoto(room: room),
                    title: Text(room['name'] as String? ?? 'Room'),
                    subtitle: Text(
                      [
                        'Sleeps ${room['capacity'] ?? 1}',
                        if ((room['bedType'] as String? ?? '').isNotEmpty)
                          room['bedType'] as String,
                        if ((room['bathroomType'] as String? ?? '').isNotEmpty)
                          room['bathroomType'] as String,
                        if ((room['description'] as String? ?? '').isNotEmpty)
                          room['description'] as String,
                      ].join(' · '),
                    ),
                    trailing: Text(
                      '${formatTzs((room['nightlyPriceTzs'] as num?) ?? 0)}\n/ night',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _RoomCategoryPhoto extends StatelessWidget {
  const _RoomCategoryPhoto({required this.room});

  final Map<String, dynamic> room;

  @override
  Widget build(BuildContext context) {
    final urls = (room['imageUrls'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    final url =
        room['primaryImageUrl'] as String? ??
        (urls.isEmpty ? null : urls.first);
    if (url == null || url.isEmpty) {
      return const CircleAvatar(child: Icon(HavenIcons.bedOutlined));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const SizedBox(width: 64, child: Icon(HavenIcons.bedOutlined)),
      ),
    );
  }
}

class _InfoFact extends StatelessWidget {
  const _InfoFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: HavenTheme.forest),
      const SizedBox(width: 7),
      Text(label),
    ],
  );
}
