import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../features/account/domain/account_models.dart';
import '../../features/access/domain/access_control.dart';
import '../../features/auth/domain/account_repository.dart';
import '../../features/auth/domain/authentication_repository.dart';
import '../../features/auth/domain/otp_verification_service.dart';
import '../../features/auth/domain/otp_service_providers.dart';
import '../../features/payments/domain/payment_gateway.dart';
import '../../features/payments/domain/unlock_record.dart';
import '../../features/properties/data/property_repository.dart';
import '../../features/properties/domain/property.dart';
import 'fee_settings.dart';
import '../../features/auth/data/authentication_data.dart';
import '../../features/account/data/customer_data_repository.dart';
import '../config/env_config.dart';
import '../data/business_configuration_repository.dart';

/// Application state shared by the customer-facing screens.
///
/// Domain rules (who may see a contact, whether a payment is verified, whether
/// an unlock may be granted twice) live here and in the services it delegates
/// to; screens only render state.
class HavenLinkStore extends ChangeNotifier {
  HavenLinkStore({
    PropertyRepository? repository,
    PaymentService? paymentService,
    AccountRepository? accounts,
    AuthenticationRepository? authentication,
    OtpVerificationService? otpService,
    FeeSettings? feeSettings,
    BusinessConfigurationRepository? businessConfigurationRepository,
  }) : _accounts = accounts ?? LocalAccountRepository(),
       _otpService = otpService ?? resolveOtpService(),
       _businessConfigurationRepository =
           businessConfigurationRepository ?? BusinessConfigurationRepository(),
       _fees = feeSettings ?? FeeSettings() {
    _authentication =
        authentication ?? resolveAuthenticationRepository(accounts: _accounts);
    _paymentService =
        paymentService ??
        resolvePaymentService(tokenProvider: () => _authentication.accessToken);
    _customerData = CustomerDataRepository(
      tokenProvider: () => _authentication.accessToken,
    );
    if (repository == null) {
      _repository = resolvePropertyRepository(
        tokenProvider: () => _authentication.accessToken,
        roleProvider: () => _user?.role.identifier,
      );
    } else {
      _repository = repository;
    }
    _fees.addListener(notifyListeners);
    loadProperties();
    loadBusinessConfiguration();
  }

  late final PropertyRepository _repository;
  final AccountRepository _accounts;
  late final PaymentService _paymentService;
  late final CustomerDataRepository _customerData;
  final OtpVerificationService _otpService;
  final BusinessConfigurationRepository _businessConfigurationRepository;
  final FeeSettings _fees;
  late final AuthenticationRepository _authentication;

  final Set<String> _savedPropertyIds = {};
  final List<Booking> _bookings = [];
  final List<PaymentRecord> _paymentRecords = [];
  final Map<String, UnlockRecord> _unlockRecords = {};
  final List<String> _recentlyViewedIds = [];
  final List<AppNotification> _notifications = [];
  final Map<String, PaymentTransaction> _transactionsByKey = {};

  User? _user;
  List<Property> _allProperties = const [];
  bool _loadingProperties = true;
  String? _loadError;

  // ---------------------------------------------------------------------------
  // Configuration and services
  // ---------------------------------------------------------------------------

  FeeSettings get feeSettings => _fees;
  PaymentService get paymentService => _paymentService;
  OtpVerificationService get otpService => _otpService;
  AccountRepository get accountRepository => _accounts;
  AuthenticationRepository get authenticationRepository => _authentication;

  // ---------------------------------------------------------------------------
  // Listings
  // ---------------------------------------------------------------------------

  /// Every listing, including drafts, paused and rejected ones.
  /// Administrators and owning agents work from this collection.
  List<Property> get allProperties => List.unmodifiable(_allProperties);

  /// Listings customers are allowed to see: approved and published only.
  List<Property> get properties => List.unmodifiable(
    _allProperties.where((property) => property.isPublic).toList(),
  );

  List<Booking> get bookings => List.unmodifiable(_bookings);
  List<PaymentRecord> get paymentRecords => List.unmodifiable(_paymentRecords);
  List<UnlockRecord> get unlockRecords =>
      List.unmodifiable(_unlockRecords.values);
  List<UnlockedProperty> get unlockedProperties => _unlockRecords.values
      .where((record) => record.isActive)
      .map((record) {
        final property = propertyById(record.listingId);
        return property == null
            ? null
            : UnlockedProperty(
                property: property,
                unlockedAt: record.createdAt,
              );
      })
      .whereType<UnlockedProperty>()
      .toList(growable: false);
  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  int get unreadNotificationCount =>
      _notifications.where((item) => !item.isRead).length;

  List<Property> get recentlyViewed => _recentlyViewedIds
      .map(propertyById)
      .whereType<Property>()
      .toList(growable: false);

  Set<String> get savedPropertyIds => Set.unmodifiable(_savedPropertyIds);
  bool get isLoadingProperties => _loadingProperties;
  String? get loadError => _loadError;

  Future<void> loadProperties() async {
    _loadingProperties = true;
    _loadError = null;
    notifyListeners();
    try {
      _allProperties = await _repository.getProperties();
    } catch (_) {
      _loadError =
          'Properties could not be loaded. Check your connection and retry.';
    } finally {
      _loadingProperties = false;
      notifyListeners();
    }
  }

  Future<void> loadBusinessConfiguration() async {
    if (!EnvConfig.backendConfigured) return;
    try {
      final config = await _businessConfigurationRepository.load();
      _fees.updateUnlockFee(config.unlockFeeTzs);
      _fees.updateBookingFeeRate(config.bookingFeeRate);
    } catch (_) {
      // Static defaults remain visible while the service is unavailable.
    }
  }

  Future<void> _loadCustomerRecords() async {
    if (_authentication.accessToken == null) return;
    try {
      final unlockRows = await _customerData.loadUnlocks();
      _savedPropertyIds
        ..clear()
        ..addAll(await _repository.getSavedPropertyIds());
      _unlockRecords
        ..clear()
        ..addEntries(
          unlockRows.map((row) {
            final listingId = row['listingId'] as String;
            final record = UnlockRecord(
              id: row['id'] as String,
              customerId: row['customerId'] as String,
              listingId: listingId,
              paymentTransactionId: row['paymentTransactionId'] as String,
              status: UnlockStatus.values.firstWhere(
                (value) => value.name == row['status'],
                orElse: () => UnlockStatus.failed,
              ),
              createdAt:
                  DateTime.tryParse(row['createdAt'] as String? ?? '') ??
                  DateTime.now(),
              confirmedAt: DateTime.tryParse(
                row['confirmedAt'] as String? ?? '',
              ),
              amountTzs: (row['amountTzs'] as num?)?.toInt(),
            );
            return MapEntry(listingId, record);
          }),
        );

      final bookingRows = await _customerData.loadBookings();
      _bookings
        ..clear()
        ..addAll(
          bookingRows.map((row) {
            final propertyId = row['propertyId'] as String;
            final property = propertyById(propertyId);
            if (property == null) return null;
            final status = row['status'] == 'confirmed'
                ? BookingStatus.active
                : BookingStatus.values.firstWhere(
                    (value) => value.name == row['status'],
                    orElse: () => BookingStatus.pending,
                  );
            return Booking(
              id: row['id'] as String,
              property: property,
              checkIn: DateTime.parse(row['checkIn'] as String),
              checkOut: DateTime.parse(row['checkOut'] as String),
              guestName: row['guestName'] as String? ?? '',
              subtotalTzs: (row['subtotalTzs'] as num).toInt(),
              feeTzs: (row['feeTzs'] as num).toInt(),
              totalTzs: (row['totalTzs'] as num).toInt(),
              createdAt:
                  DateTime.tryParse(row['createdAt'] as String? ?? '') ??
                  DateTime.now(),
              status: status,
              paymentTransactionId: row['paymentTransactionId'] as String?,
              roomTypeName:
                  (row['roomType'] as Map<String, dynamic>?)?['name']
                      as String?,
              assignedRoomNumber:
                  (row['assignedRoom'] as Map<String, dynamic>?)?['roomNumber']
                      as String?,
              guestCount: (row['guestCount'] as num?)?.toInt() ?? 1,
            );
          }).whereType<Booking>(),
        );
      notifyListeners();
    } catch (_) {
      // Keep the signed-in experience usable if an optional history query fails.
    }
  }

  Future<void> updateBusinessConfiguration({
    int? unlockFeeTzs,
    double? bookingFeeRate,
  }) async {
    final nextUnlockFee = unlockFeeTzs ?? _fees.unlockFeeTzs;
    final nextBookingFeeRate = bookingFeeRate ?? _fees.bookingFeeRate;
    if (EnvConfig.backendConfigured) {
      final token = _authentication.accessToken;
      if (token == null) throw StateError('Sign in as an administrator first.');
      await _businessConfigurationRepository.save(
        accessToken: token,
        unlockFeeTzs: nextUnlockFee,
        bookingFeeRate: nextBookingFeeRate,
      );
    }
    _fees.updateUnlockFee(nextUnlockFee);
    _fees.updateBookingFeeRate(nextBookingFeeRate);
  }

  Property? propertyById(String id) {
    for (final property in _allProperties) {
      if (property.id == id) return property;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Listing administration (agent portals and admin portal)
  // ---------------------------------------------------------------------------

  /// Creates or replaces a listing and refreshes local state.
  Future<Property> saveListing(
    Property property, {
    bool confirmInventoryModelChange = false,
    bool saveAsDraft = false,
  }) async {
    final saved = await _repository.save(
      property,
      confirmInventoryModelChange: confirmInventoryModelChange,
      saveAsDraft: saveAsDraft,
    );
    await loadProperties();
    return saved;
  }

  Future<List<String>> uploadListingPhotos(
    List<({String name, List<int> bytes})> files,
  ) => _repository.uploadPhotos(files);

  Future<void> setListingStatus(String id, ListingStatus status) async {
    await _repository.updateStatus(id, status);
    await loadProperties();
  }

  Future<void> deleteListing(String id) async {
    await _repository.delete(id);
    await loadProperties();
  }

  Future<List<Map<String, dynamic>>> loadBookingMessages(
    String bookingId,
  ) async {
    if (!EnvConfig.backendConfigured) {
      throw StateError(
        'Guest messaging requires a configured Haven Link backend.',
      );
    }
    return _customerData.loadBookingMessages(bookingId);
  }

  Future<void> sendBookingMessage({
    required String bookingId,
    required String body,
  }) async {
    if (!EnvConfig.backendConfigured) {
      throw StateError(
        'Guest messaging requires a configured Haven Link backend.',
      );
    }
    await _customerData.sendBookingMessage(bookingId: bookingId, body: body);
  }

  Future<void> reportListing(String id) async {
    await _repository.incrementReportCount(id);
    await loadProperties();
  }

  /// Looks up a listing customers are allowed to open.
  Property? publicPropertyById(String id) {
    final property = propertyById(id);
    return property != null && property.isPublic ? property : null;
  }

  Future<void> toggleSaved(String propertyId) async {
    final save = !_savedPropertyIds.contains(propertyId);
    await _repository.setSavedProperty(propertyId, save);
    if (save) {
      _savedPropertyIds.add(propertyId);
    } else {
      _savedPropertyIds.remove(propertyId);
    }
    notifyListeners();
  }

  void recordViewing(String propertyId) {
    _recentlyViewedIds.remove(propertyId);
    _recentlyViewedIds.insert(0, propertyId);
    if (_recentlyViewedIds.length > 12) _recentlyViewedIds.removeLast();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Session
  // ---------------------------------------------------------------------------

  String? get customerName => _user?.fullName;
  String? get customerEmail => _user?.email;
  User? get currentUser => _user;
  bool get isSignedIn => _user != null;

  Future<User> signIn({required String email, required String password}) async {
    final user = await _authentication.signIn(email: email, password: password);
    _user = user;
    await loadProperties();
    await _loadCustomerRecords();
    notifyListeners();
    return user;
  }

  /// Completes registration.
  ///
  /// Callers must have already passed `OtpVerificationService.verify` for the
  /// phone number; this method never marks a number as verified on its own.
  Future<User> register({
    required String fullName,
    required String email,
    required String phoneE164,
    required String password,
    required String challengeId,
    required String sessionId,
    required AccountRole role,
    Set<AgentCapability> capabilities = const {},
    Set<AgentWorkspace> workspaces = const {},
  }) async {
    final user = await _authentication.register(
      fullName: fullName,
      email: email,
      phoneE164: phoneE164,
      password: password,
      challengeId: challengeId,
      sessionId: sessionId,
      role: role,
      capabilities: capabilities,
      workspaces: workspaces,
    );
    _user = user;
    await loadProperties();
    await _loadCustomerRecords();
    notifyListeners();
    return user;
  }

  /// Development-only session for exploring the app without a backend.
  void startPreviewSession({String? email}) {
    _user = User(
      id: 'preview-customer',
      fullName: 'Haven Link customer',
      email: email ?? '',
      phone: '',
      role: AccountRole.customer,
      verification: AccountVerification.unverified,
      isPreviewSession: true,
    );
    notifyListeners();
  }

  /// Switches the session to an already-loaded account, for example after an
  /// administrator opens a portal or a demo role sign-in.
  void setCurrentUser(User user) {
    _user = user;
    notifyListeners();
  }

  void signOut() {
    _user = null;
    notifyListeners();
  }

  /// Persists an edited profile back to the account store.
  Future<void> updateProfile(User user) async {
    await _accounts.update(user);
    if (_user?.id == user.id) _user = user;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Notifications
  // ---------------------------------------------------------------------------

  void pushNotification({
    required String title,
    required String message,
    String? audience,
  }) {
    _notifications.insert(
      0,
      AppNotification(
        id: 'n-${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        message: message,
        createdAt: DateTime.now(),
        audience: audience,
      ),
    );
    notifyListeners();
  }

  void markNotificationsRead() {
    var changed = false;
    for (var i = 0; i < _notifications.length; i++) {
      if (_notifications[i].isRead) continue;
      final item = _notifications[i];
      _notifications[i] = AppNotification(
        id: item.id,
        title: item.title,
        message: item.message,
        createdAt: item.createdAt,
        isRead: true,
        audience: item.audience,
      );
      changed = true;
    }
    if (changed) notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Rental contact unlock
  // ---------------------------------------------------------------------------

  bool isUnlocked(String propertyId) =>
      _unlockRecords[propertyId]?.isActive ?? false;

  UnlockRecord? unlockRecordFor(String propertyId) =>
      _unlockRecords[propertyId];

  Future<void> recordUnlock(Property property) async {
    if (!kDebugMode) {
      throw StateError(
        'Preview unlock recording is unavailable in release builds.',
      );
    }
    _user ??= User(
      id: 'preview-customer',
      fullName: 'Haven Link customer',
      email: '',
      phone: '',
      role: AccountRole.customer,
      verification: AccountVerification.unverified,
      isPreviewSession: true,
    );
    final now = DateTime.now();
    _unlockRecords.putIfAbsent(
      property.id,
      () => UnlockRecord(
        id: 'preview-unlock-${now.microsecondsSinceEpoch}',
        customerId: _user!.id,
        listingId: property.id,
        paymentTransactionId: 'preview-payment-${now.microsecondsSinceEpoch}',
        status: UnlockStatus.active,
        createdAt: now,
        confirmedAt: now,
        amountTzs: _fees.unlockFeeTzs,
      ),
    );
    notifyListeners();
  }

  /// Early-stage access: asks the server to open a rental's exact location and
  /// contact without a fee. The server refuses once payments are configured,
  /// in which case callers fall back to the paid checkout.
  Future<void> openRentalDetails(Property property) async {
    if (property.businessModel != PropertyBusinessModel.contactUnlock) {
      throw StateError('Only rentals can be opened this way.');
    }
    _requireCustomer();
    if (isUnlocked(property.id)) return;
    await _customerData.openRentalDetails(property.id);
    await _loadCustomerRecords();
    notifyListeners();
  }

  /// Charges the contact-unlock fee and, only on a server-confirmed payment,
  /// releases the protected contact for exactly this listing.
  ///
  /// Guarantees:
  /// * access is never granted from a client-side success flag;
  /// * a second call for the same listing returns the stored record without
  ///   creating another transaction or another unlock row;
  /// * the transaction must be bound to this customer, this listing and the
  ///   rental-unlock purpose.
  Future<UnlockRecord> purchaseUnlock({
    required Property property,
    required PaymentMethod method,
  }) async {
    if (property.businessModel != PropertyBusinessModel.contactUnlock) {
      throw StateError(
        'Bookable stays use the booking flow, not contact unlock.',
      );
    }
    final customer = _requireCustomer();

    final existing = _unlockRecords[property.id];
    if (existing != null && existing.isActive) return existing;

    final verified = await _runVerifiedPayment(
      idempotencyKey: 'unlock:${customer.id}:${property.id}',
      purpose: PaymentPurpose.rentalContactUnlock,
      amountTzs: _fees.unlockFeeTzs,
      method: method,
      customerId: customer.id,
      listingId: property.id,
    );

    final now = DateTime.now();
    final record = UnlockRecord(
      id: 'unlock-${now.microsecondsSinceEpoch}',
      customerId: customer.id,
      listingId: property.id,
      paymentTransactionId: verified.id,
      status: UnlockStatus.active,
      createdAt: now,
      confirmedAt: now,
      amountTzs: verified.amountTzs,
    );

    // Unique on (customerId, listingId): a replayed callback cannot add a row.
    _unlockRecords.putIfAbsent(property.id, () => record);
    _appendPayment(property, verified, method.label);

    pushNotification(
      title: 'Contact unlocked',
      message: 'You can now view the owner contact for ${property.name}.',
      audience: 'CUSTOMER',
    );
    return _unlockRecords[property.id]!;
  }

  /// Protected contact release point. Returns `null` unless this customer
  /// holds an active unlock for this exact listing.
  Future<OwnerContact?> contactFor(String propertyId) async {
    final record = _unlockRecords[propertyId];
    if (record == null || !record.isActive) return null;

    final allowed = AccessControl.canViewProtectedContact(
      user: _user,
      listingId: propertyId,
      hasActiveUnlock: true,
    );
    if (!allowed || record.customerId != _user?.id) return null;

    return _repository.getAuthorizedContact(propertyId);
  }

  // ---------------------------------------------------------------------------
  // Accommodation booking (kept separate from unlock payments)
  // ---------------------------------------------------------------------------

  Future<Booking> purchaseBooking({
    required Property property,
    required DateTime checkIn,
    required DateTime checkOut,
    required String guestName,
    required PaymentMethod method,
    String? roomTypeId,
    String? roomTypeName,
    int? nightlyPriceTzs,
    int guestCount = 1,
  }) async {
    if (property.businessModel != PropertyBusinessModel.bookable) {
      throw StateError(
        'Contact-unlock rentals cannot be booked like accommodation.',
      );
    }
    final customer = _requireCustomer();
    final nights = DateUtils.dateOnly(
      checkOut,
    ).difference(DateUtils.dateOnly(checkIn)).inDays;
    if (nights < 1) {
      throw StateError('Check-out must be after check-in.');
    }

    final subtotal = (nightlyPriceTzs ?? property.priceTzs) * nights;
    final fee = _fees.bookingFeeFor(subtotal);
    final total = subtotal + fee;

    final key =
        'booking:${customer.id}:${property.id}:'
        '${checkIn.toIso8601String()}:${checkOut.toIso8601String()}:'
        '${roomTypeId ?? 'default'}:${DateTime.now().microsecondsSinceEpoch}';
    String? serverBookingId;
    String? serverRoomNumber;
    var serverSubtotal = subtotal;
    var serverFee = fee;
    var serverTotal = total;
    if (EnvConfig.backendConfigured) {
      final result = await _customerData.createBooking(
        propertyId: property.id,
        idempotencyKey: key,
        checkIn: checkIn,
        checkOut: checkOut,
        guestName: guestName,
        roomTypeId: roomTypeId,
        guestCount: guestCount,
      );
      final record = result['booking'] as Map<String, dynamic>;
      serverBookingId = record['id'] as String;
      serverRoomNumber = record['assignedRoomNumber'] as String?;
      serverSubtotal = (record['subtotalTzs'] as num).toInt();
      serverFee = (record['feeTzs'] as num).toInt();
      serverTotal = (record['totalTzs'] as num).toInt();
    }

    late final PaymentTransaction verified;
    try {
      verified = await _runVerifiedPayment(
        idempotencyKey: key,
        purpose: PaymentPurpose.accommodationBooking,
        amountTzs: serverTotal,
        method: method,
        customerId: customer.id,
        bookingId: serverBookingId,
      );
    } catch (_) {
      if (serverBookingId != null) {
        await _customerData.cancelBooking(serverBookingId).catchError((_) {});
      }
      rethrow;
    }

    for (final booking in _bookings) {
      if (booking.paymentTransactionId == verified.id) return booking;
    }

    final now = DateTime.now();
    final booking = Booking(
      id:
          serverBookingId ??
          'HL-${now.microsecondsSinceEpoch.toString().substring(7)}',
      property: property,
      checkIn: checkIn,
      checkOut: checkOut,
      guestName: guestName,
      subtotalTzs: serverSubtotal,
      feeTzs: serverFee,
      totalTzs: serverTotal,
      createdAt: now,
      paymentTransactionId: verified.id,
      roomTypeName: roomTypeName,
      assignedRoomNumber: serverRoomNumber,
      guestCount: guestCount,
    );
    _bookings.insert(0, booking);
    _appendPayment(property, verified, method.label);
    pushNotification(
      title: 'Booking confirmed',
      message: '${property.name} is reserved from ${now.day}/${now.month}.',
      audience: 'CUSTOMER',
    );
    notifyListeners();
    return booking;
  }

  Future<void> cancelCustomerBooking(Booking booking) async {
    _requireCustomer();
    if (!EnvConfig.backendConfigured) {
      throw StateError(
        'A live booking service is required to cancel a booking.',
      );
    }
    await _customerData.cancelBooking(booking.id);
    final index = _bookings.indexWhere((item) => item.id == booking.id);
    if (index >= 0) {
      _bookings[index] = _bookings[index].copyWith(
        status: BookingStatus.cancelled,
      );
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Shared payment plumbing
  // ---------------------------------------------------------------------------

  /// Creates (or reuses) a transaction, then reads its status back from the
  /// payment service. Only a verified, correctly scoped transaction is
  /// returned, so a client-side claim can never release protected data.
  Future<PaymentTransaction> _runVerifiedPayment({
    required String idempotencyKey,
    required PaymentPurpose purpose,
    required int amountTzs,
    required PaymentMethod method,
    required String customerId,
    String? listingId,
    String? bookingId,
  }) async {
    var transaction = _transactionsByKey[idempotencyKey];
    final reusable =
        transaction != null &&
        transaction.status != PaymentTransactionStatus.failed &&
        transaction.status != PaymentTransactionStatus.cancelled &&
        transaction.status != PaymentTransactionStatus.expired;
    if (!reusable) {
      transaction = await _paymentService.createTransaction(
        purpose: purpose,
        amountTzs: amountTzs,
        methodId: method.id,
        customerId: customerId,
        idempotencyKey: idempotencyKey,
        listingId: listingId,
        bookingId: bookingId,
      );
      _transactionsByKey[idempotencyKey] = transaction;
    }

    final verified = await _paymentService.fetchStatus(transaction.id);
    _transactionsByKey[idempotencyKey] = verified;

    final correctlyScoped =
        verified.purpose == purpose &&
        verified.customerId == customerId &&
        verified.amountTzs == amountTzs &&
        (listingId == null || verified.listingId == listingId) &&
        (bookingId == null || verified.bookingId == bookingId);
    if (!verified.isVerified || !correctlyScoped) {
      throw const PaymentNotVerifiedException();
    }
    return verified;
  }

  User _requireCustomer() {
    final user = _user;
    if (user == null) {
      throw StateError('Sign in to continue with payment.');
    }
    if (!user.accountEnabled) {
      throw StateError('This account is suspended.');
    }
    return user;
  }

  void _appendPayment(
    Property property,
    PaymentTransaction transaction,
    String methodLabel,
  ) {
    _paymentRecords.insert(
      0,
      PaymentRecord(
        reference: transaction.reference,
        property: property,
        amountTzs: transaction.amountTzs,
        purpose: transaction.purpose.label,
        method: methodLabel,
        createdAt: transaction.verifiedAt ?? transaction.createdAt,
        status: transaction.status,
        paymentTransactionId: transaction.id,
      ),
    );
  }
}
