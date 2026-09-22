import '../../account/domain/account_models.dart';
import 'agent_models.dart';

/// Data access for agent-owned working data: inquiries, room types,
/// inventory, policies and guest messages.
///
/// Listings themselves are read through `PropertyRepository` so there is one
/// source of truth for moderation state.
abstract interface class AgentRepository {
  List<ListingInquiry> inquiries();
  Future<void> saveInquiry(ListingInquiry inquiry);

  List<RoomType> roomTypes(String listingId);
  Future<void> saveRoomType(RoomType roomType);
  Future<void> deleteRoomType(String roomTypeId);

  CheckInPolicy policy(String listingId);
  Future<void> savePolicy(String listingId, CheckInPolicy policy);

  RoomInventory? inventory(String roomTypeId, DateTime date);
  Future<void> saveInventory(RoomInventory entry);

  List<GuestMessage> messages(String bookingId);
  Future<void> sendMessage(GuestMessage message);

  AgentProfile? profile(String userId);
  Future<void> saveProfile(AgentProfile profile);
}

/// In-memory implementation used until the backend is connected.
class LocalAgentRepository implements AgentRepository {
  LocalAgentRepository({AgentProfile? seedProfile})
    : _profiles = {
        if (seedProfile != null) seedProfile.userId: seedProfile,
      };

  final Map<String, List<ListingInquiry>> _inquiriesByListing = {};
  final Map<String, RoomType> _roomTypes = {};
  final Map<String, CheckInPolicy> _policies = {};
  final Map<String, RoomInventory> _inventory = {};
  final Map<String, List<GuestMessage>> _messages = {};
  final Map<String, AgentProfile> _profiles;

  @override
  List<ListingInquiry> inquiries() => _inquiriesByListing.values
      .expand((items) => items)
      .toList(growable: false)
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<void> saveInquiry(ListingInquiry inquiry) async {
    final list = _inquiriesByListing.putIfAbsent(inquiry.listingId, () => []);
    final index = list.indexWhere((item) => item.id == inquiry.id);
    if (index == -1) {
      list.insert(0, inquiry);
    } else {
      list[index] = inquiry;
    }
  }

  @override
  List<RoomType> roomTypes(String listingId) =>
      _roomTypes.values.where((item) => item.listingId == listingId).toList();

  @override
  Future<void> saveRoomType(RoomType roomType) async {
    _roomTypes[roomType.id] = roomType;
  }

  @override
  Future<void> deleteRoomType(String roomTypeId) async {
    _roomTypes.remove(roomTypeId);
  }

  @override
  CheckInPolicy policy(String listingId) =>
      _policies[listingId] ?? const CheckInPolicy();

  @override
  Future<void> savePolicy(String listingId, CheckInPolicy value) async {
    _policies[listingId] = value;
  }

  @override
  RoomInventory? inventory(String roomTypeId, DateTime date) =>
      _inventory['$roomTypeId|${date.toIso8601String()}'];

  @override
  Future<void> saveInventory(RoomInventory entry) async {
    _inventory['${entry.roomTypeId}|${entry.date.toIso8601String()}'] = entry;
  }

  @override
  List<GuestMessage> messages(String bookingId) =>
      List.of(_messages[bookingId] ?? const []);

  @override
  Future<void> sendMessage(GuestMessage message) async {
    _messages.putIfAbsent(message.bookingId, () => []).add(message);
  }

  AgentProfile? profile(String userId) => _profiles[userId];

  @override
  Future<void> saveProfile(AgentProfile profile) async {
    _profiles[profile.userId] = profile;
  }
}
