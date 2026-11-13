import 'package:flutter/widgets.dart';

import '../../../core/config/env_config.dart';
import '../../../core/state/haven_link_store.dart';
import '../../access/domain/access_control.dart';
import '../../account/domain/account_models.dart';
import '../../agent_portal/domain/agent_models.dart';
import '../../agent_portal/domain/agent_repository.dart';
import '../../agent_portal/data/http_agent_repository.dart';
import '../../properties/domain/property.dart';

/// State for one agent portal.
///
/// A portal instance is bound to a single [Portal] and a single signed-in
/// agent. Every mutating action re-checks [AccessControl], so opening the URL
/// of another portal or replaying an action from the UI never bypasses the
/// role check.
class AgentPortalStore extends ChangeNotifier {
  AgentPortalStore({
    required this.portal,
    required this._store,
    AgentRepository? repository,
  }) : _repository =
           repository ??
           (EnvConfig.backendConfigured
               ? HttpAgentRepository(
                   tokenProvider: () =>
                       _store.authenticationRepository.accessToken,
                 )
               : LocalAgentRepository());

  final Portal portal;
  final HavenLinkStore _store;
  final AgentRepository _repository;

  final String _error = '';
  final bool _busy = false;
  List<Booking> _agentBookings = const [];
  List<UnlockActivity> _agentUnlockActivity = const [];
  bool _bookingsLoaded = false;
  bool _unlocksLoaded = false;

  String get error => _error;
  bool get busy => _busy;

  User? get agent => _store.currentUser;
  HavenLinkStore get customerStore => _store;

  bool get isRentalPortal => portal == Portal.rentalAgent;
  bool get isApartmentPortal => portal == Portal.apartmentAgent;

  bool _belongsToPortal(Property property) => switch (portal) {
    Portal.apartmentAgent => property.category.isApartmentStay,
    Portal.stayAgent => !property.category.isApartmentStay,
    _ => true,
  };

  PropertyBusinessModel get model => isRentalPortal
      ? PropertyBusinessModel.contactUnlock
      : PropertyBusinessModel.bookable;

  bool get isAuthorized => AccessControl.canOpenPortal(agent, portal);

  /// True when the signed-in agent may publish listings for this portal.
  bool get canPublish {
    final user = agent;
    if (user == null || !user.canPublish) return false;
    return isRentalPortal
        ? user.role.canManageRentals ||
              user.capabilities.contains(AgentCapability.rentalProperty)
        : AccessControl.canOpenPortal(user, portal);
  }

  /// Human-readable reason publishing is blocked, or `null`.
  String? get publishBlockedReason {
    final user = agent;
    if (user == null) return 'Sign in to manage listings.';
    if (!user.accountEnabled) return 'This account is suspended.';
    if (!user.phoneVerified) {
      return 'Verify your phone number before publishing listings.';
    }
    if (!canPublish) return 'This account has no permission for this portal.';
    return null;
  }

  // ---------------------------------------------------------------------------
  // Listings owned by this agent
  // ---------------------------------------------------------------------------

  List<Property> get myListings => _store.allProperties
      .where(
        (property) =>
            property.agentId == (agent?.id ?? '') &&
            property.businessModel == model &&
            _belongsToPortal(property),
      )
      .toList();

  List<Property> get publishedListings => myListings
      .where((property) => property.listingStatus == ListingStatus.published)
      .toList();

  List<Property> get pendingListings => myListings
      .where(
        (property) => property.listingStatus == ListingStatus.pendingReview,
      )
      .toList();

  /// Contact-unlock activity on this agent's rental listings.
  List<UnlockActivity> get unlockActivity {
    if (EnvConfig.backendConfigured && _unlocksLoaded) {
      return List.unmodifiable(_agentUnlockActivity);
    }
    final owned = myListings.map((item) => item.id).toSet();
    return _store.unlockRecords
        .where((record) => owned.contains(record.listingId))
        .map(
          (record) => UnlockActivity(
            record: record,
            listingName:
                _store.propertyById(record.listingId)?.name ?? record.listingId,
          ),
        )
        .toList();
  }

  /// Bookings for this agent's accommodations.
  List<Booking> get bookingsForMyListings {
    if (EnvConfig.backendConfigured && _bookingsLoaded) {
      return List.unmodifiable(_agentBookings);
    }
    final owned = myListings.map((item) => item.id).toSet();
    return _store.bookings
        .where((item) => owned.contains(item.property.id))
        .toList();
  }

  Future<void> loadBookings() async {
    if (EnvConfig.backendConfigured) {
      _agentBookings = await _repository.loadBookings();
    } else {
      final owned = myListings.map((item) => item.id).toSet();
      _agentBookings = _store.bookings
          .where((booking) => owned.contains(booking.property.id))
          .toList(growable: false);
    }
    _bookingsLoaded = true;
    notifyListeners();
  }

  Future<void> loadUnlockActivity() async {
    if (EnvConfig.backendConfigured) {
      _agentUnlockActivity = await _repository.loadUnlockActivity();
      _unlocksLoaded = true;
      notifyListeners();
    }
  }

  Future<void> updateBookingStatus({
    required String bookingId,
    required BookingStatus status,
  }) async {
    final index = _agentBookings.indexWhere(
      (booking) => booking.id == bookingId,
    );
    if (index == -1) {
      throw StateError('This booking is no longer available.');
    }
    final serverStatus = switch (status) {
      BookingStatus.active => 'confirmed',
      BookingStatus.pending => 'pending',
      BookingStatus.completed => 'completed',
      BookingStatus.cancelled => 'cancelled',
    };
    if (EnvConfig.backendConfigured) {
      await _repository.updateBookingStatus(bookingId, serverStatus);
    }
    _agentBookings[index] = _agentBookings[index].copyWith(status: status);
    notifyListeners();
  }

  List<PaymentRecord> get paymentRecords {
    final owned = myListings.map((item) => item.id).toSet();
    return _store.paymentRecords
        .where((item) => owned.contains(item.property.id))
        .toList();
  }

  List<AppNotification> get notifications => _store.notifications
      .where((item) => item.audience == portal.identifier)
      .toList();

  Future<List<RoomType>> loadRoomTypes(String listingId) async {
    final values = await _repository.loadRoomTypes(listingId);
    notifyListeners();
    return values;
  }

  Future<RoomType> saveRoomType(RoomType roomType) async {
    final saved = await _repository.saveRoomType(roomType);
    notifyListeners();
    return saved;
  }

  Future<void> deleteRoomType(String roomTypeId) async {
    await _repository.deleteRoomType(roomTypeId);
    notifyListeners();
  }

  Future<List<RoomInventory>> loadInventory(String roomTypeId) async {
    final values = await _repository.loadInventory(roomTypeId);
    notifyListeners();
    return values;
  }

  Future<void> saveInventory(RoomInventory inventory) async {
    await _repository.saveInventory(inventory);
    notifyListeners();
  }

  List<PhysicalRoom> physicalRooms(String listingId) =>
      _repository.physicalRooms(listingId);

  Future<List<PhysicalRoom>> loadPhysicalRooms(String listingId) =>
      _repository.loadPhysicalRooms(listingId);

  Future<List<RoomCalendarEntry>> loadRoomCalendar(
    String listingId,
    DateTime start,
    DateTime end,
  ) => _repository.loadRoomCalendar(listingId, start, end);

  Future<void> addPhysicalRooms(String listingId, List<String> roomNumbers) =>
      _repository.addPhysicalRooms(listingId, roomNumbers);

  Future<void> renamePhysicalRoom(
    String listingId,
    String roomId,
    String roomNumber,
  ) => _repository.renamePhysicalRoom(listingId, roomId, roomNumber);

  Future<void> generatePhysicalRooms(
    String listingId,
    List<RoomFloorConfiguration> floors,
  ) async {
    await _repository.generatePhysicalRooms(listingId, floors);
    notifyListeners();
  }

  Future<void> assignRooms({
    required String listingId,
    required List<String> roomIds,
    required String roomTypeId,
  }) async {
    await _repository.assignRooms(
      listingId: listingId,
      roomIds: roomIds,
      roomTypeId: roomTypeId,
    );
    notifyListeners();
  }

  Future<void> blockRoomDates({
    required String listingId,
    required String roomId,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    await _repository.blockRoomDates(
      listingId: listingId,
      roomId: roomId,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
    );
    notifyListeners();
  }

  Future<void> removeRoomBlock({
    required String listingId,
    required String roomId,
    required String blockId,
  }) async {
    await _repository.removeRoomBlock(
      listingId: listingId,
      roomId: roomId,
      blockId: blockId,
    );
    notifyListeners();
  }

  Future<List<WalkInReservation>> loadWalkIns(String listingId) =>
      _repository.loadWalkIns(listingId);

  Future<void> createWalkIn(String listingId, Map<String, Object?> values) =>
      _repository.createWalkIn(listingId, values);

  Future<void> updateWalkIn(
    String listingId,
    String reservationId,
    String action,
    Map<String, Object?> values,
  ) => _repository.updateWalkIn(listingId, reservationId, action, values);

  Future<CheckInPolicy> loadPolicy(String listingId) =>
      _repository.loadPolicy(listingId);

  Future<void> savePolicy(String listingId, CheckInPolicy policy) async {
    await _repository.savePolicy(listingId, policy);
    notifyListeners();
  }

  Future<List<GuestMessage>> loadMessages(String bookingId) =>
      _repository.loadMessages(bookingId);

  Future<void> sendAgentMessage(GuestMessage message) async {
    await _repository.sendMessage(message);
    notifyListeners();
  }

  Future<AgentProfile> loadProfile() async {
    final user = agent;
    if (user == null) {
      throw StateError('Sign in to load your agent profile.');
    }
    return _repository.loadProfile(user.id, user.role);
  }

  Future<void> saveProfile(AgentProfile profile) async {
    if (!isAuthorized || profile.userId != agent?.id) {
      throw StateError('You cannot update this agent profile.');
    }
    await _repository.saveProfile(profile);
    notifyListeners();
  }
}
