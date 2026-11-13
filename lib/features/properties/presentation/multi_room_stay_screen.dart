import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/env_config.dart';
import '../../../core/formatters/currency_formatter.dart';
import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/booking_progress.dart';
import '../../checkout/presentation/checkout_screen.dart';
import '../../reviews/presentation/property_reviews_section.dart';
import '../domain/property.dart';
import 'widgets/property_extras.dart';
import 'widgets/property_photo.dart';

class StayRoomCategory {
  const StayRoomCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.nightlyPriceTzs,
    required this.capacity,
    required this.totalRooms,
    required this.amenities,
    required this.amenityDetails,
    required this.imageUrls,
    this.bedType,
    this.numberOfBeds,
    this.bathroomType,
    this.sizeSqm,
  });

  final String id;
  final String name;
  final String description;
  final int nightlyPriceTzs;
  final int capacity;
  final int totalRooms;
  final List<String> amenities;
  final List<AmenityDetail> amenityDetails;
  final List<String> imageUrls;
  final String? bedType;
  final int? numberOfBeds;
  final String? bathroomType;
  final double? sizeSqm;

  factory StayRoomCategory.fromJson(Map<String, dynamic> json) {
    final urls = (json['imageUrls'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .where((url) => url.trim().isNotEmpty)
        .toList();
    final primary = json['primaryImageUrl'] as String?;
    return StayRoomCategory(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Room',
      description: json['description'] as String? ?? '',
      nightlyPriceTzs: (json['nightlyPriceTzs'] as num?)?.toInt() ?? 0,
      capacity: (json['capacity'] as num?)?.toInt() ?? 1,
      totalRooms: (json['totalRooms'] as num?)?.toInt() ?? 0,
      amenities: (json['amenities'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      amenityDetails: (json['amenityDetails'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AmenityDetail.fromJson)
          .toList(growable: false),
      imageUrls: [
        if (primary != null && primary.trim().isNotEmpty) primary,
        ...urls.where((url) => url != primary),
      ],
      bedType: json['bedType'] as String?,
      numberOfBeds: (json['numberOfBeds'] as num?)?.toInt(),
      bathroomType: json['bathroomType'] as String?,
      sizeSqm: (json['sizeSqm'] as num?)?.toDouble(),
    );
  }
}

class StayAvailability {
  const StayAvailability({
    required this.available,
    required this.availableRooms,
    required this.pricePerNight,
  });

  final bool available;
  final int availableRooms;
  final int pricePerNight;
}

class _StayInfo {
  const _StayInfo({required this.policy, required this.roomTypes});

  final Map<String, dynamic> policy;
  final List<StayRoomCategory> roomTypes;

  factory _StayInfo.fromJson(Map<String, dynamic> json) => _StayInfo(
    policy: json['policy'] as Map<String, dynamic>? ?? const {},
    roomTypes: (json['roomTypes'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(StayRoomCategory.fromJson)
        .where((room) => room.id.isNotEmpty)
        .toList(growable: false),
  );
}

class MultiRoomStayScreen extends StatefulWidget {
  const MultiRoomStayScreen({
    required this.property,
    required this.store,
    this.initialDates,
    this.initialGuestCount = 2,
    super.key,
  });

  final Property property;
  final HavenLinkStore store;
  final DateTimeRange? initialDates;
  final int initialGuestCount;

  @override
  State<MultiRoomStayScreen> createState() => _MultiRoomStayScreenState();
}

class _MultiRoomStayScreenState extends State<MultiRoomStayScreen> {
  late final Future<_StayInfo> _stayInfo = _loadStayInfo();
  DateTimeRange? _dates;
  late int _guestCount;
  String _selectedTab = 'Overview';
  List<StayRoomCategory> _roomTypes = const [];
  Map<String, StayAvailability> _availability = const {};
  bool _checkingAvailability = false;
  String? _availabilityError;

  static const _tabs = [
    'Overview',
    'Rooms',
    'Facilities',
    'Location',
    'Reviews',
  ];

  @override
  void initState() {
    super.initState();
    _dates = widget.initialDates;
    _guestCount = widget.initialGuestCount.clamp(1, 20);
    _stayInfo.then((info) {
      if (!mounted) return;
      _roomTypes = info.roomTypes;
      if (_dates != null) _checkAllAvailability();
      setState(() {});
    });
  }

  Future<_StayInfo> _loadStayInfo() async {
    final response = await http
        .get(
          EnvConfig.endpoint(
            '/api/v1/properties/${Uri.encodeComponent(widget.property.id)}/stay-info',
          ),
        )
        .timeout(const Duration(seconds: 15));
    final decoded = jsonDecode(response.body);
    if (response.statusCode != 200 || decoded is! Map<String, dynamic>) {
      throw StateError('Room categories could not be loaded.');
    }
    return _StayInfo.fromJson(decoded);
  }

  Future<StayAvailability> _checkAvailability(
    StayRoomCategory room,
    DateTimeRange dates,
    int guests,
  ) async {
    final uri = EnvConfig.endpoint('/api/v1/bookings/availability/check')
        .replace(
          queryParameters: {
            'propertyId': widget.property.id,
            'roomTypeId': room.id,
            'checkIn': dates.start.toIso8601String(),
            'checkOut': dates.end.toIso8601String(),
            'guestCount': '$guests',
          },
        );
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    final decoded = jsonDecode(response.body);
    if (response.statusCode != 200 || decoded is! Map<String, dynamic>) {
      final message = decoded is Map<String, dynamic>
          ? decoded['error'] as String?
          : null;
      throw StateError(message ?? 'Room availability could not be checked.');
    }
    return StayAvailability(
      available: decoded['available'] == true,
      availableRooms: (decoded['availableRooms'] as num?)?.toInt() ?? 0,
      pricePerNight:
          (decoded['pricePerNight'] as num?)?.toInt() ?? room.nightlyPriceTzs,
    );
  }

  Future<void> _checkAllAvailability() async {
    final dates = _dates;
    if (dates == null || _roomTypes.isEmpty) return;
    setState(() {
      _checkingAvailability = true;
      _availabilityError = null;
    });
    try {
      final entries = await Future.wait(
        _roomTypes.map((room) async {
          if (_guestCount > room.capacity) {
            return MapEntry(
              room.id,
              const StayAvailability(
                available: false,
                availableRooms: 0,
                pricePerNight: 0,
              ),
            );
          }
          return MapEntry(
            room.id,
            await _checkAvailability(room, dates, _guestCount),
          );
        }),
      );
      if (!mounted) return;
      setState(() {
        _availability = Map.fromEntries(entries);
        _checkingAvailability = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _availabilityError = error.toString();
        _availability = const {};
        _checkingAvailability = false;
      });
    }
  }

  Future<void> _openRoom(StayRoomCategory room) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => StayRoomDetailsScreen(
          property: widget.property,
          room: room,
          store: widget.store,
          initialDates: _dates,
          initialGuestCount: _guestCount,
          availability: _availability[room.id],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final property = widget.property;
    return Scaffold(
      appBar: AppBar(
        title: Text(property.name),
        actions: [
          IconButton(
            tooltip: widget.store.savedPropertyIds.contains(property.id)
                ? 'Remove saved property'
                : 'Save property',
            onPressed: () async {
              try {
                await widget.store.toggleSaved(property.id);
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(error.toString())));
              }
            },
            icon: Icon(
              widget.store.savedPropertyIds.contains(property.id)
                  ? HavenIcons.favorite
                  : HavenIcons.favoriteBorder,
            ),
          ),
        ],
      ),
      body: FutureBuilder<_StayInfo>(
        future: _stayInfo,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Stay details could not be loaded.'),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => setState(() {}),
                      icon: const Icon(HavenIcons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          final info = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const HavenBookingProgress(current: 0),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final primary = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            PropertyGallery(
                              photos: property.allPhotos,
                              badge: _VerifiedBadge(
                                label: property.isVerified
                                    ? 'Verified ${_stayType(property.category)}'
                                    : 'Haven Link stay',
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        property.name,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.headlineMedium,
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        property.generalLocation,
                                        style: const TextStyle(
                                          color: HavenTheme.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  HavenIcons.starRounded,
                                  color: HavenTheme.teal,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${property.rating.toStringAsFixed(1)} (${property.reviewCount})',
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final tab in _tabs)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        label: Text(tab),
                                        selected: _selectedTab == tab,
                                        onSelected: (_) =>
                                            setState(() => _selectedTab = tab),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_selectedTab != 'Rooms') _tabContent(info),
                          ],
                        );
                        if (constraints.maxWidth < 1000) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              primary,
                              if (_selectedTab == 'Rooms')
                                _roomsContent(info.roomTypes),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 6, child: primary),
                            const SizedBox(width: 28),
                            Expanded(
                              flex: 4,
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: _roomsContent(info.roomTypes),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tabContent(_StayInfo info) => switch (_selectedTab) {
    'Rooms' => _roomsContent(info.roomTypes),
    'Facilities' => _facilitiesContent(),
    'Location' => NearbyMap(
      locationQuery:
          widget.property.locationVisibility == LocationVisibility.exact &&
              widget.property.latitude != null &&
              widget.property.longitude != null
          ? '${widget.property.latitude},${widget.property.longitude}'
          : widget.property.generalLocation,
      zoom: 13,
      areaLabel: widget.property.generalLocation,
    ),
    'Reviews' => PropertyReviewsSection(
      propertyId: widget.property.id,
      tokenProvider: () => widget.store.authenticationRepository.accessToken,
      canReport: widget.store.isSignedIn,
    ),
    _ => _overviewContent(info),
  };

  Widget _overviewContent(_StayInfo info) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Overview', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(widget.property.description, style: const TextStyle(height: 1.5)),
      const SizedBox(height: 18),
      _policySummary(info.policy),
      const SizedBox(height: 18),
      Text(
        'Popular facilities',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      _amenityChips(
        widget.property.amenities,
        details: widget.property.amenityDetails,
      ),
      for (final amenity in widget.property.amenityDetails.where(
        (item) => item.description.trim().isNotEmpty,
      ))
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('${amenity.name}: ${amenity.description}'),
        ),
      const SizedBox(height: 18),
      if (MediaQuery.sizeOf(context).width < 1048) ...[
        Text('Rooms & rates', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (info.roomTypes.isEmpty)
          const Text('Room categories are not available yet.')
        else
          for (final room in info.roomTypes.take(3)) _roomCard(room),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => setState(() => _selectedTab = 'Rooms'),
            child: const Text('View all room options'),
          ),
        ),
      ],
    ],
  );

  Widget _roomsContent(List<StayRoomCategory> rooms) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Choose a room category',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 5),
      const Text(
        'Select a category. Haven Link assigns an available room after your reservation is confirmed.',
        style: TextStyle(color: HavenTheme.muted),
      ),
      const SizedBox(height: 12),
      if (_dates == null)
        const _InfoCard(
          text: 'Open a room to choose dates and check availability.',
        ),
      if (_checkingAvailability) const LinearProgressIndicator(),
      if (_availabilityError != null)
        _ErrorCard(
          message: _availabilityError!,
          onRetry: _checkAllAvailability,
        ),
      if (rooms.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Text(
            'Room categories are not available for this property yet.',
          ),
        )
      else
        for (final room in rooms) _roomCard(room),
    ],
  );

  Widget _roomCard(StayRoomCategory room) {
    final checked = _dates != null && !_checkingAvailability;
    final availability = _availability[room.id];
    final exceedsCapacity = _guestCount > room.capacity;
    final isAvailable = checked && availability?.available == true;
    final availabilityLabel = _dates == null
        ? 'Choose dates in room details to check availability'
        : _checkingAvailability
        ? 'Checking dates…'
        : exceedsCapacity
        ? 'Fits up to ${room.capacity} guests'
        : _availabilityError != null
        ? 'Availability could not be checked'
        : isAvailable
        ? '${availability!.availableRooms} available for your dates'
        : 'Unavailable for selected dates';
    final image = room.imageUrls.isEmpty ? '' : room.imageUrls.first;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _dates == null || isAvailable ? () => _openRoom(room) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              final photo = ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: image.isEmpty
                    ? Container(
                        width: 104,
                        height: 96,
                        color: HavenTheme.forest.withValues(alpha: 0.08),
                        child: const Icon(HavenIcons.bedOutlined),
                      )
                    : Image.network(
                        image,
                        width: 104,
                        height: 96,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 104,
                          height: 96,
                          color: HavenTheme.forest.withValues(alpha: 0.08),
                          child: const Icon(HavenIcons.bedOutlined),
                        ),
                      ),
              );
              final details = Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        '${room.capacity} ${room.capacity == 1 ? 'guest' : 'guests'}',
                        if (room.bedType != null && room.bedType!.isNotEmpty)
                          room.bedType!,
                        if (room.amenities.isNotEmpty ||
                            room.amenityDetails.isNotEmpty)
                          {
                            ...room.amenities,
                            ...room.amenityDetails.map((item) => item.name),
                          }.take(2).join(' · '),
                      ].join('  ·  '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: HavenTheme.muted),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      availabilityLabel,
                      style: TextStyle(
                        color: isAvailable
                            ? HavenTheme.forest
                            : HavenTheme.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${formatTzs(room.nightlyPriceTzs)} / night',
                      style: const TextStyle(
                        color: HavenTheme.forest,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
              final button = FilledButton(
                onPressed:
                    (checked && (!isAvailable || exceedsCapacity)) ||
                        _checkingAvailability ||
                        _availabilityError != null
                    ? null
                    : () => _openRoom(room),
                child: Text(_dates == null ? 'View details' : 'Select'),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [photo, const SizedBox(width: 12), details],
                    ),
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerRight, child: button),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  photo,
                  const SizedBox(width: 14),
                  details,
                  const SizedBox(width: 12),
                  button,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _facilitiesContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Facilities', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      _amenityChips(
        widget.property.amenities,
        details: widget.property.amenityDetails,
      ),
      for (final amenity in widget.property.amenityDetails.where(
        (item) => item.description.trim().isNotEmpty,
      ))
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('${amenity.name}: ${amenity.description}'),
        ),
    ],
  );

  Widget _amenityChips(
    List<String> amenities, {
    List<AmenityDetail> details = const [],
  }) {
    final names = <String>{...amenities, ...details.map((item) => item.name)};
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final amenity in names)
          Chip(
            avatar: const Icon(HavenIcons.checkCircleOutline, size: 17),
            label: Text(amenity),
          ),
        if (names.isEmpty) const Text('Facilities have not been listed yet.'),
      ],
    );
  }

  Widget _policySummary(Map<String, dynamic> policy) => Card(
    color: HavenTheme.lightMint,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Wrap(
        spacing: 18,
        runSpacing: 10,
        children: [
          _PolicyFact(
            icon: HavenIcons.login,
            text: 'Check-in ${policy['checkInFrom'] ?? '14:00'}',
          ),
          _PolicyFact(
            icon: HavenIcons.logout,
            text: 'Check-out ${policy['checkOutBy'] ?? '11:00'}',
          ),
          _PolicyFact(
            icon: HavenIcons.eventAvailableOutlined,
            text:
                'Free cancellation up to ${policy['cancellationHours'] ?? 24} hours before check-in',
          ),
        ],
      ),
    ),
  );
}

class StayRoomDetailsScreen extends StatefulWidget {
  const StayRoomDetailsScreen({
    required this.property,
    required this.room,
    required this.store,
    this.initialDates,
    this.initialGuestCount = 2,
    this.availability,
    super.key,
  });

  final Property property;
  final StayRoomCategory room;
  final HavenLinkStore store;
  final DateTimeRange? initialDates;
  final int initialGuestCount;
  final StayAvailability? availability;

  @override
  State<StayRoomDetailsScreen> createState() => _StayRoomDetailsScreenState();
}

class _StayRoomDetailsScreenState extends State<StayRoomDetailsScreen> {
  late DateTimeRange? _dates = widget.initialDates;
  late int _guestCount = widget.initialGuestCount.clamp(
    1,
    widget.room.capacity,
  );
  bool _submitting = false;
  String? _error;

  Future<void> _book() async {
    var dates = _dates;
    if (dates == null) {
      final today = DateUtils.dateOnly(DateTime.now());
      dates = await showDateRangePicker(
        context: context,
        firstDate: today,
        lastDate: today.add(const Duration(days: 730)),
        initialDateRange: DateTimeRange(
          start: today.add(const Duration(days: 1)),
          end: today.add(const Duration(days: 2)),
        ),
      );
      if (dates == null) return;
      setState(() => _dates = dates);
    }
    if (_guestCount > widget.room.capacity) {
      setState(
        () => _error =
            'This room category fits up to ${widget.room.capacity} guests.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final availability = await _checkRoomAvailability(
        propertyId: widget.property.id,
        room: widget.room,
        dates: dates,
        guests: _guestCount,
      );
      if (!availability.available) {
        setState(() {
          _error = 'This room category is no longer available for these dates.';
          _submitting = false;
        });
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => CheckoutScreen(
            property: widget.property,
            store: widget.store,
            initialRoomTypeId: widget.room.id,
            initialDates: dates,
            initialGuestCount: _guestCount,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _selectDates() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final selected = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 730)),
      initialDateRange:
          _dates ??
          DateTimeRange(
            start: today.add(const Duration(days: 1)),
            end: today.add(const Duration(days: 2)),
          ),
    );
    if (selected != null) setState(() => _dates = selected);
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    return Scaffold(
      appBar: AppBar(title: Text(room.name)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: HavenCheckoutLayout(
            progress: 1,
            children: [
              if (room.imageUrls.isNotEmpty)
                SizedBox(
                  height: 260,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: room.imageUrls.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) => ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        room.imageUrls[index],
                        width: 300,
                        height: 260,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 300,
                          color: HavenTheme.lightMint,
                          child: const Icon(HavenIcons.bedOutlined, size: 40),
                        ),
                      ),
                    ),
                  ),
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: PropertyPhoto(
                    imageUrl: widget.property.imageUrl,
                    height: 260,
                  ),
                ),
              const SizedBox(height: 18),
              Text(
                room.name,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 5),
              Text(
                widget.property.name,
                style: const TextStyle(color: HavenTheme.muted),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 8,
                children: [
                  _PolicyFact(
                    icon: HavenIcons.personOutline,
                    text: '${room.capacity} guests',
                  ),
                  _PolicyFact(
                    icon: HavenIcons.bedOutlined,
                    text: [
                      if (room.numberOfBeds != null)
                        '${room.numberOfBeds} ${room.bedType ?? 'beds'}'
                      else
                        room.bedType ?? 'Bed details not listed',
                    ].join(),
                  ),
                  if (room.bathroomType != null)
                    _PolicyFact(
                      icon: HavenIcons.bathtubOutlined,
                      text: room.bathroomType!,
                    ),
                  if (room.sizeSqm != null)
                    _PolicyFact(
                      icon: HavenIcons.squareFoot,
                      text: '${room.sizeSqm!.toStringAsFixed(0)} m²',
                    ),
                ],
              ),
              const SizedBox(height: 18),
              if (room.description.isNotEmpty) ...[
                Text(room.description, style: const TextStyle(height: 1.5)),
                const SizedBox(height: 18),
              ],
              Text(
                'Room amenities',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              _AmenityWrap(
                amenities: room.amenities,
                details: room.amenityDetails,
              ),
              const SizedBox(height: 20),
              KeyedSubtree(
                key: const Key('checkout-summary'),
                child: _StaySearchControls(
                  dates: _dates,
                  guestCount: _guestCount,
                  maxGuests: room.capacity,
                  onDates: _selectDates,
                  onGuests: (value) => setState(() => _guestCount = value),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: formatTzs(room.nightlyPriceTzs),
                        style: const TextStyle(
                          color: HavenTheme.forest,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                        children: const [
                          TextSpan(
                            text: ' / night',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.normal,
                              color: HavenTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _book,
                    icon: _submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(HavenIcons.arrowForward),
                    label: Text(
                      _submitting ? 'Checking availability' : 'Book This Room',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<StayAvailability> _checkRoomAvailability({
  required String propertyId,
  required StayRoomCategory room,
  required DateTimeRange dates,
  required int guests,
}) async {
  final uri = EnvConfig.endpoint('/api/v1/bookings/availability/check').replace(
    queryParameters: {
      'propertyId': propertyId,
      'roomTypeId': room.id,
      'checkIn': dates.start.toIso8601String(),
      'checkOut': dates.end.toIso8601String(),
      'guestCount': '$guests',
    },
  );
  final response = await http.get(uri).timeout(const Duration(seconds: 15));
  final decoded = jsonDecode(response.body);
  if (response.statusCode != 200 || decoded is! Map<String, dynamic>) {
    final message = decoded is Map<String, dynamic>
        ? decoded['error'] as String?
        : null;
    throw StateError(message ?? 'Room availability could not be checked.');
  }
  return StayAvailability(
    available: decoded['available'] == true,
    availableRooms: (decoded['availableRooms'] as num?)?.toInt() ?? 0,
    pricePerNight:
        (decoded['pricePerNight'] as num?)?.toInt() ?? room.nightlyPriceTzs,
  );
}

class _StaySearchControls extends StatelessWidget {
  const _StaySearchControls({
    required this.dates,
    required this.guestCount,
    required this.onDates,
    required this.onGuests,
    this.maxGuests = 20,
  });

  final DateTimeRange? dates;
  final int guestCount;
  final int maxGuests;
  final VoidCallback onDates;
  final ValueChanged<int> onGuests;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 8,
    children: [
      OutlinedButton.icon(
        onPressed: onDates,
        icon: const Icon(HavenIcons.calendarMonthOutlined),
        label: Text(
          dates == null
              ? 'Choose dates'
              : '${_date(dates!.start)} – ${_date(dates!.end)}',
        ),
      ),
      DropdownButton<int>(
        value: guestCount.clamp(1, maxGuests),
        underline: const SizedBox.shrink(),
        onChanged: (value) {
          if (value != null) onGuests(value);
        },
        items: List.generate(
          maxGuests,
          (index) => DropdownMenuItem(
            value: index + 1,
            child: Text('${index + 1} ${index == 0 ? 'Guest' : 'Guests'}'),
          ),
        ),
      ),
    ],
  );
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(HavenIcons.verified, color: HavenTheme.forest, size: 16),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    ),
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Card(
    color: HavenTheme.lightMint,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(HavenIcons.infoOutline, color: HavenTheme.forest),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(HavenIcons.errorOutline, color: Colors.red),
      title: Text(message),
      trailing: IconButton(
        tooltip: 'Retry availability check',
        onPressed: onRetry,
        icon: const Icon(HavenIcons.refresh),
      ),
    ),
  );
}

class _PolicyFact extends StatelessWidget {
  const _PolicyFact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: HavenTheme.forest),
      const SizedBox(width: 5),
      Text(text),
    ],
  );
}

class _AmenityWrap extends StatelessWidget {
  const _AmenityWrap({required this.amenities, this.details = const []});

  final List<String> amenities;
  final List<AmenityDetail> details;

  @override
  Widget build(BuildContext context) {
    final names = <String>{...amenities, ...details.map((item) => item.name)};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final amenity in names)
              Chip(
                avatar: const Icon(HavenIcons.check, size: 16),
                label: Text(amenity),
              ),
            if (names.isEmpty)
              const Text('Room amenities have not been listed.'),
          ],
        ),
        for (final amenity in details.where(
          (item) => item.description.trim().isNotEmpty,
        ))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${amenity.name}: ${amenity.description}'),
          ),
      ],
    );
  }
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')} ${_month(value.month)} ${value.year}';

String _month(int value) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][value - 1];

String _stayType(PropertyCategory category) => switch (category) {
  PropertyCategory.hotel => 'Hotel',
  PropertyCategory.motel => 'Motel',
  PropertyCategory.lodge => 'Lodge',
  _ => 'Stay',
};
