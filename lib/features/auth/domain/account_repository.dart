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
    : _accounts = List.of(seed ?? const []);

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
