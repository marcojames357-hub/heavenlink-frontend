import 'package:flutter/widgets.dart';

import '../../../core/state/haven_link_store.dart';
import '../../access/domain/access_control.dart';
import '../../account/domain/account_models.dart';
import '../../agent_portal/domain/agent_models.dart';
import '../../agent_portal/domain/agent_repository.dart';
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
    required HavenLinkStore store,
    AgentRepository? repository,
  }) : _store = store,
       _repository = repository ?? LocalAgentRepository();

  final Portal portal;
  final HavenLinkStore _store;
  final AgentRepository _repository;

  String _error = '';
  bool _busy = false;

  String get error => _error;
  bool get busy => _busy;

  User? get agent => _store.currentUser;
  HavenLinkStore get customerStore => _store;

  bool get isRentalPortal => portal == Portal.rentalAgent;

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
        : user.role.canManageAccommodations ||
              user.capabilities.contains(AgentCapability.accommodationBooking);
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
            property.businessModel == model,
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
    final owned = myListings.map((item) => item.id).toSet();
    return _store.bookings
        .where((item) => owned.contains(item.property.id))
        .toList();
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

  List<ListingInquiry> get inquiries {
    final owned = myListings.map((item) => item.id).toSet();
    return _repository
        .inquiries()
        .where((item) => owned.contains(item.listingId))
        .toList();
  }

  // __APPEND__
}
