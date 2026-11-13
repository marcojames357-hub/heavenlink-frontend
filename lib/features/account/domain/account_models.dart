/// Platform roles.
///
/// The [identifier] strings are the contract values used by backend APIs and
/// must never be inferred from frontend input — the server issues the role on
/// the session token and every portal re-checks it.
enum AccountRole {
  customer('CUSTOMER'),
  rentalAgent('RENTAL_AGENT'),
  stayAgent('STAY_AGENT'),
  admin('ADMIN');

  const AccountRole(this.identifier);

  /// Stable wire identifier, e.g. `RENTAL_AGENT`.
  final String identifier;

  static AccountRole? fromIdentifier(String value) {
    for (final role in values) {
      if (role.identifier == value.toUpperCase()) return role;
    }
    return null;
  }

  bool get isAgent =>
      this == AccountRole.rentalAgent || this == AccountRole.stayAgent;

  bool get canManageRentals =>
      this == AccountRole.rentalAgent || this == AccountRole.admin;

  bool get canManageAccommodations =>
      this == AccountRole.stayAgent || this == AccountRole.admin;

  bool get isAdmin => this == AccountRole.admin;
}

/// Phone-number verification state for an account.
///
/// A number only moves to [verified] after the verification service confirms
/// the code. Document uploads are deliberately not part of this flow.
enum AccountVerification { unverified, pending, verified }

/// The services an agent account is allowed to operate.
enum AgentCapability { rentalProperty, accommodationBooking }

/// Management workspaces an agent can be granted. The server stores and
/// enforces these; the client only mirrors what the session reports.
enum AgentWorkspace {
  rental('RENTAL', 'Long-Term Rentals'),
  apartment('APARTMENT', 'Apartments / Short-Term Stays'),
  hotel('HOTEL', 'Hotels, Lodges & Motels');

  const AgentWorkspace(this.identifier, this.title);

  final String identifier;
  final String title;

  static AgentWorkspace? fromIdentifier(String value) {
    for (final item in values) {
      if (item.identifier == value.toUpperCase()) return item;
    }
    return null;
  }
}

class User {
  const User({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.role,
    required this.verification,
    this.accountEnabled = true,
    this.isPreviewSession = false,
    this.capabilities = const {},
    this.workspaces = const {},
  });

  final String id;
  final String fullName;
  final String email;

  /// Active workspaces reported by the server.
  final Set<AgentWorkspace> workspaces;

  /// Always stored in E.164 form, e.g. `+255754123456`.
  final String phone;
  final AccountRole role;
  final AccountVerification verification;

  /// Administrators can disable an account without deleting its history.
  final bool accountEnabled;

  /// True for local development sessions created without a backend.
  final bool isPreviewSession;

  /// Extra services granted on top of [role], for agents allowed to run both
  /// portals.
  final Set<AgentCapability> capabilities;

  bool get phoneVerified => verification == AccountVerification.verified;

  /// Publishing listings is a restricted action that requires a verified phone
  /// number and an enabled account.
  bool get canPublish => accountEnabled && phoneVerified;

  bool get isAdmin => role.isAdmin;

  bool hasCapability(AgentCapability capability) =>
      capabilities.contains(capability) || role.isAdmin;

  User copyWith({
    String? fullName,
    String? email,
    String? phone,
    AccountRole? role,
    AccountVerification? verification,
    bool? accountEnabled,
    bool? isPreviewSession,
    Set<AgentCapability>? capabilities,
    Set<AgentWorkspace>? workspaces,
  }) {
    return User(
      id: id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      verification: verification ?? this.verification,
      accountEnabled: accountEnabled ?? this.accountEnabled,
      isPreviewSession: isPreviewSession ?? this.isPreviewSession,
      capabilities: capabilities ?? this.capabilities,
      workspaces: workspaces ?? this.workspaces,
    );
  }
}

/// Service-provider profile for a rental or accommodation agent.
class AgentProfile {
  const AgentProfile({
    required this.userId,
    required this.displayName,
    required this.role,
    this.agencyName = '',
    this.bio = '',
    this.phone = '',
    this.email = '',
    this.photoUrl = '',
    this.videoUrl = '',
    this.capabilities = const {},
    this.serviceAreas = const [],
  });

  final String userId;
  final String displayName;
  final AccountRole role;
  final String agencyName;
  final String bio;
  final String phone;
  final String email;
  final String photoUrl;
  final String videoUrl;
  final Set<AgentCapability> capabilities;
  final List<String> serviceAreas;

  AgentProfile copyWith({
    String? displayName,
    String? agencyName,
    String? bio,
    String? phone,
    String? email,
    String? photoUrl,
    String? videoUrl,
    Set<AgentCapability>? capabilities,
    List<String>? serviceAreas,
  }) {
    return AgentProfile(
      userId: userId,
      displayName: displayName ?? this.displayName,
      role: role,
      agencyName: agencyName ?? this.agencyName,
      bio: bio ?? this.bio,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      capabilities: capabilities ?? this.capabilities,
      serviceAreas: serviceAreas ?? this.serviceAreas,
    );
  }
}

class Location {
  const Location({required this.city, required this.neighborhood});

  final String city;
  final String neighborhood;

  String get displayName => '$neighborhood, $city';
}

class Amenity {
  const Amenity({required this.id, required this.label});

  final String id;
  final String label;
}

class Review {
  const Review({
    required this.id,
    required this.propertyId,
    required this.authorName,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  final String id;
  final String propertyId;
  final String authorName;
  final double rating;
  final String comment;
  final DateTime createdAt;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    this.isRead = false,
    this.audience,
  });

  final String id;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;

  /// Portal the notification belongs to, e.g. `RENTAL_AGENT`.
  final String? audience;
}

class ConversationMessage {
  const ConversationMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.sentAt,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String body;
  final DateTime sentAt;
}
