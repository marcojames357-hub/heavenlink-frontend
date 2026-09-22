import '../../account/domain/account_models.dart';

/// Data access for platform accounts.
///
/// Shared by the authentication flow and the admin portal so an account
/// suspended by an administrator is the same record the sign-in flow reads.
abstract interface class AccountRepository {
  /// Every registered account, for administration screens only.
  List<User> listAccounts();

  Future<User?> findByEmail(String email);

  Future<User?> findById(String id);

  /// Persists a new account. Emails are unique.
  Future<User> create(User user);

  Future<void> update(User user);
}

/// Local account store used until the backend is connected.
///
/// Development only: it keeps accounts in memory, so nothing here survives a
/// restart and no password material is stored.
class LocalAccountRepository implements AccountRepository {
  LocalAccountRepository({List<User>? seed})
    : _accounts = List.of(seed ?? kSeedAccounts);

  /// The demo agent accounts that own the seeded listings.
  static const String rentalAgentId = 'agent-rental-1';
  static const String stayAgentId = 'agent-stay-1';
  static const String unverifiedAgentId = 'agent-rental-2';

  static const List<User> kSeedAccounts = [
    User(
      id: 'customer-1',
      fullName: 'Aisha Mohamed',
      email: 'aisha@example.com',
      phone: '+255754111222',
      role: AccountRole.customer,
      verification: AccountVerification.verified,
      isPreviewSession: true,
    ),
    User(
      id: rentalAgentId,
      fullName: 'Juma Kweka',
      email: 'rentals@havenlink.co.tz',
      phone: '+255713000222',
      role: AccountRole.rentalAgent,
      verification: AccountVerification.verified,
      capabilities: {AgentCapability.rentalProperty},
      isPreviewSession: true,
    ),
    User(
      id: stayAgentId,
      fullName: 'Neema Mushi',
      email: 'stays@havenlink.co.tz',
      phone: '+255754333444',
      role: AccountRole.stayAgent,
      verification: AccountVerification.verified,
      capabilities: {AgentCapability.accommodationBooking},
      isPreviewSession: true,
    ),
    User(
      id: unverifiedAgentId,
      fullName: 'Said Juma',
      email: 'newagent@havenlink.co.tz',
      phone: '+255764555666',
      role: AccountRole.rentalAgent,
      verification: AccountVerification.unverified,
      capabilities: {AgentCapability.rentalProperty},
      isPreviewSession: true,
    ),
    User(
      id: 'admin-1',
      fullName: 'Haven Link Admin',
      email: 'admin@havenlink.co.tz',
      phone: '+255700000001',
      role: AccountRole.admin,
      verification: AccountVerification.verified,
      isPreviewSession: true,
    ),
    User(
      id: 'agent-disabled-1',
      fullName: 'Fraudulent Agent',
      email: 'suspended@havenlink.co.tz',
      phone: '+255700000002',
      role: AccountRole.rentalAgent,
      verification: AccountVerification.verified,
      capabilities: {AgentCapability.rentalProperty},
      accountEnabled: false,
      isPreviewSession: true,
    ),
  ];

  final List<User> _accounts;

  @override
  List<User> listAccounts() => List.unmodifiable(_accounts);

  @override
  Future<User?> findByEmail(String email) async {
    final needle = email.trim().toLowerCase();
    for (final account in _accounts) {
      if (account.email.toLowerCase() == needle) return account;
    }
    return null;
  }

  @override
  Future<User?> findById(String id) async {
    for (final account in _accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  @override
  Future<User> create(User user) async {
    final existing = await findByEmail(user.email);
    if (existing != null) {
      throw StateError('An account with this email already exists.');
    }
    _accounts.add(user);
    return user;
  }

  @override
  Future<void> update(User user) async {
    final index = _accounts.indexWhere((account) => account.id == user.id);
    if (index == -1) {
      _accounts.add(user);
    } else {
      _accounts[index] = user;
    }
  }
}
