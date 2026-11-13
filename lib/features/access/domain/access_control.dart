import '../../account/domain/account_models.dart';
import '../../properties/domain/property.dart';

/// The separate dashboards Haven Link exposes.
enum Portal {
  rentalAgent('Rental Property Agent', 'RENTAL_AGENT'),
  apartmentAgent('Apartment Stays Agent', 'APARTMENT_AGENT'),
  stayAgent('Hotel, Lodge & Motel Agent', 'STAY_AGENT'),
  admin('Administrator', 'ADMIN');

  const Portal(this.title, this.identifier);

  final String title;
  final String identifier;
}

/// Central role-based access control for every Haven Link portal.
///
/// The rules below are the *frontend* half of authorization: they decide what
/// a session may see or attempt. The backend must repeat every check — the
/// client is never a security boundary, and portal access must never be
/// granted because a user edited a value, a route name or a URL.
class AccessControl {
  const AccessControl._();

  /// Whether [user] may open [portal].
  ///
  /// A disabled account can open nothing. Administrators may enter both agent
  /// portals; an agent only ever enters the portal matching their own role
  /// unless the server granted the matching capability.
  static bool canOpenPortal(User? user, Portal portal) {
    if (user == null || !user.accountEnabled) return false;

    return switch (portal) {
      Portal.rentalAgent =>
        user.role == AccountRole.rentalAgent ||
            user.role == AccountRole.admin ||
            user.capabilities.contains(AgentCapability.rentalProperty),
      Portal.apartmentAgent => _hasStayWorkspace(
        user,
        AgentWorkspace.apartment,
      ),
      Portal.stayAgent => _hasStayWorkspace(user, AgentWorkspace.hotel),
      Portal.admin => user.role == AccountRole.admin,
    };
  }

  /// Legacy sessions without workspace data fall back to the hotel portal
  /// (the former combined stay portal); the backend still enforces the real
  /// workspace on every request.
  static bool _hasStayWorkspace(User user, AgentWorkspace workspace) {
    if (user.role == AccountRole.admin) return true;
    if (user.workspaces.isNotEmpty) return user.workspaces.contains(workspace);
    // Legacy sessions only ever had the combined stay portal, now Hotel.
    return workspace == AgentWorkspace.hotel &&
        (user.role == AccountRole.stayAgent ||
            user.capabilities.contains(AgentCapability.accommodationBooking));
  }

  /// Workspace a listing belongs to, or null for rentals.
  static Portal? portalForCategory(PropertyCategory category) {
    if (category.isApartmentStay) return Portal.apartmentAgent;
    if (category.isHotelStay) return Portal.stayAgent;
    return null;
  }

  /// Role that [portal] belongs to, used for navigation and audit labels.
  static AccountRole roleFor(Portal portal) => switch (portal) {
    Portal.rentalAgent => AccountRole.rentalAgent,
    Portal.apartmentAgent => AccountRole.stayAgent,
    Portal.stayAgent => AccountRole.stayAgent,
    Portal.admin => AccountRole.admin,
  };

  /// Portals the current session may enter, in display order.
  static List<Portal> allowedPortals(User? user) =>
      Portal.values.where((portal) => canOpenPortal(user, portal)).toList();

  /// Restricted action: publishing or editing live listings.
  ///
  /// Requires an enabled account, a verified phone number and the matching
  /// agent capability. Unverified agents may prepare drafts but cannot publish.
  static bool canPublishListings(
    User? user, {
    required PropertyBusinessModel model,
  }) {
    if (user == null || !user.canPublish) return false;
    return switch (model) {
      PropertyBusinessModel.contactUnlock =>
        user.role.canManageRentals ||
            user.capabilities.contains(AgentCapability.rentalProperty),
      PropertyBusinessModel.bookable =>
        user.role.canManageAccommodations ||
            user.capabilities.contains(AgentCapability.accommodationBooking),
    };
  }

  /// Publishing for a specific stay category, honouring workspaces.
  static bool canPublishCategory(User? user, PropertyCategory category) {
    final portal = portalForCategory(category);
    if (portal == null) {
      return canPublishListings(
        user,
        model: PropertyBusinessModel.contactUnlock,
      );
    }
    return user != null && user.canPublish && canOpenPortal(user, portal);
  }

  /// Restricted action: managing a specific listing the user does not own.
  static bool canManageListing(User? user, Property property) {
    if (user == null || !user.accountEnabled) return false;
    if (user.role == AccountRole.admin) return true;
    if (property.agentId.isEmpty || property.agentId != user.id) return false;
    if (!user.phoneVerified) return false;
    return property.businessModel == PropertyBusinessModel.contactUnlock
        ? user.role.canManageRentals ||
              user.capabilities.contains(AgentCapability.rentalProperty)
        : user.role.canManageAccommodations ||
              user.capabilities.contains(AgentCapability.accommodationBooking);
  }

  /// Restricted actions: moderation, fee changes, account suspension.
  static bool canModerateListings(User? user) =>
      user != null && user.accountEnabled && user.role == AccountRole.admin;

  static bool canManageAccounts(User? user) => canModerateListings(user);

  static bool canConfigureFees(User? user) => canModerateListings(user);

  static bool canViewTransactions(User? user) => canModerateListings(user);

  static bool canViewAuditLog(User? user) => canModerateListings(user);

  /// Restricted action: viewing a protected owner/agent contact.
  ///
  /// This mirrors the server rule — contact details are released only for an
  /// active unlock record belonging to the requesting customer and that exact
  /// listing.
  static bool canViewProtectedContact({
    required User? user,
    required String listingId,
    required bool hasActiveUnlock,
  }) {
    if (user == null || !user.accountEnabled) return false;
    if (listingId.isEmpty) return false;
    return hasActiveUnlock;
  }
}
