import 'dart:async';

import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../core/config/env_config.dart';
import '../../../core/data/api_client.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.category,
    required this.priority,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        message: json['message'] as String? ?? '',
        category: json['category'] as String? ?? 'general',
        priority: json['priority'] as String? ?? 'normal',
        isRead: json['isRead'] as bool? ?? false,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
      );

  final String id;
  final String title;
  final String message;
  final String category;
  final String priority;
  final bool isRead;
  final DateTime createdAt;

  AppNotification asRead() => AppNotification(
    id: id,
    title: title,
    message: message,
    category: category,
    priority: priority,
    isRead: true,
    createdAt: createdAt,
  );
}

class NotificationRepository {
  NotificationRepository({required String? Function() tokenProvider})
    : _api = ApiClient(tokenProvider: tokenProvider);

  final ApiClient _api;

  Future<List<AppNotification>> load({
    String? group,
    bool unreadOnly = false,
  }) async {
    final query = <String, String>{
      'limit': '60',
      'group': ?group,
      if (unreadOnly) 'unread': 'true',
    };
    final result = await _api.get(
      '/api/v1/notifications?${Uri(queryParameters: query).query}',
    );
    return (result['notifications'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AppNotification.fromJson)
        .toList();
  }

  Future<int> unreadCount() async {
    final result = await _api.get('/api/v1/notifications/unread-count');
    return (result['unread'] as num?)?.toInt() ?? 0;
  }

  Future<void> markRead([List<String>? ids]) async {
    await _api.put('/api/v1/notifications/read', {'ids': ?ids});
  }

  Future<Map<String, dynamic>> preferences() async {
    final result = await _api.get('/api/v1/notifications/preferences');
    return (result['preferences'] as Map<String, dynamic>?) ?? const {};
  }

  Future<void> savePreferences({
    required bool sms,
    required List<String> muted,
  }) async {
    await _api.put('/api/v1/notifications/preferences', {
      'sms': sms,
      'mutedCategories': muted,
    });
  }

  Future<List<Map<String, dynamic>>> rentalStatements() async {
    final result = await _api.get('/api/v1/notifications/rental-statements');
    return (result['statements'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }
}

/// App-bar bell with an unread badge that opens the notification center.
class NotificationBellButton extends StatefulWidget {
  const NotificationBellButton({required this.tokenProvider, super.key});

  final String? Function() tokenProvider;

  @override
  State<NotificationBellButton> createState() => _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<NotificationBellButton> {
  late final NotificationRepository _repository = NotificationRepository(
    tokenProvider: widget.tokenProvider,
  );
  Timer? _timer;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    if (!EnvConfig.backendConfigured) return;
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final count = await _repository.unreadCount();
      if (mounted && count != _unread) setState(() => _unread = count);
    } on StateError {
      // A failed poll must not interrupt the agent.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!EnvConfig.backendConfigured) return const SizedBox.shrink();
    return IconButton(
      tooltip: context.tr('Notifications'),
      icon: Badge(
        isLabelVisible: _unread > 0,
        label: Text(_unread > 99 ? '99+' : '$_unread'),
        child: const Icon(HavenIcons.notificationsNone),
      ),
      onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => NotificationCenterScreen(repository: _repository),
          ),
        );
        _refresh();
      },
    );
  }
}

const _filters = <(String?, String, IconData)>[
  (null, 'All', HavenIcons.notificationsNone),
  ('bookings', 'Bookings', HavenIcons.luggageOutlined),
  ('payments', 'Payments', HavenIcons.paymentsOutlined),
  ('messages', 'Messages', HavenIcons.chatBubbleOutline),
  ('reviews', 'Reviews', HavenIcons.reviewsOutlined),
  ('rent', 'Rent', HavenIcons.homeWorkOutlined),
  ('admin', 'Admin', HavenIcons.adminPanelSettingsOutlined),
];

IconData _iconFor(String category) => switch (category) {
  'booking' || 'checkin' || 'checkout' => HavenIcons.luggageOutlined,
  'payment' || 'finance' => HavenIcons.paymentsOutlined,
  'message' => HavenIcons.chatBubbleOutline,
  'review' || 'report' => HavenIcons.reviewsOutlined,
  'rent' => HavenIcons.homeWorkOutlined,
  'admin' => HavenIcons.adminPanelSettingsOutlined,
  _ => HavenIcons.notificationsNone,
};

/// Grouped alert inbox with read state and delivery preferences.
class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({required this.repository, super.key});

  final NotificationRepository repository;

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  String? _group;
  bool _unreadOnly = false;
  bool _loading = true;
  String? _error;
  List<AppNotification> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.repository.load(
        group: _group,
        unreadOnly: _unreadOnly,
      );
      if (mounted) setState(() => _items = items);
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAll() async {
    try {
      await widget.repository.markRead();
      await _load();
    } on StateError catch (error) {
      _toast(error.message);
    }
  }

  Future<void> _open(AppNotification item) async {
    if (item.isRead) return;
    try {
      await widget.repository.markRead([item.id]);
      if (!mounted) return;
      setState(() {
        _items = [
          for (final entry in _items)
            entry.id == item.id ? entry.asRead() : entry,
        ];
      });
    } on StateError catch (error) {
      _toast(error.message);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Notifications')),
        actions: [
          IconButton(
            tooltip: context.tr('Mark all as read'),
            onPressed: _markAll,
            icon: const Icon(HavenIcons.doneAll),
          ),
          IconButton(
            tooltip: context.tr('Notification settings'),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => _PreferencesSheet(repository: widget.repository),
            ),
            icon: const Icon(HavenIcons.tune),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final filter in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(filter.$3, size: 16),
                      label: Text(context.tr(filter.$2)),
                      selected: _group == filter.$1,
                      onSelected: (_) {
                        setState(() => _group = filter.$1);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            dense: true,
            title: Text(context.tr('Unread only')),
            value: _unreadOnly,
            onChanged: (value) {
              setState(() => _unreadOnly = value);
              _load();
            },
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            TextButton(onPressed: _load, child: Text(context.tr('Retry'))),
          ],
        ),
      );
    }
    if (!_loading && _items.isEmpty) {
      return Center(
        child: Text(
          context.tr("You're all caught up."),
          style: const TextStyle(color: HavenTheme.muted),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = _items[index];
          return ListTile(
            tileColor: item.isRead ? null : HavenTheme.lightMint,
            leading: CircleAvatar(
              backgroundColor: HavenTheme.mint,
              child: Icon(_iconFor(item.category), color: HavenTheme.forest),
            ),
            title: Text(
              item.title,
              style: TextStyle(
                fontWeight: item.isRead ? FontWeight.w500 : FontWeight.w700,
              ),
            ),
            subtitle: Text('${item.message}\n${_when(item.createdAt)}'),
            isThreeLine: true,
            trailing: item.priority == 'high'
                ? const Icon(HavenIcons.priorityHigh, color: Colors.redAccent)
                : (item.isRead
                      ? null
                      : const Icon(
                          HavenIcons.circle,
                          size: 10,
                          color: HavenTheme.teal,
                        )),
            onTap: () => _open(item),
          );
        },
      ),
    );
  }

  String _when(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }
}

const _mutable = <(String, String)>[
  ('booking', 'Bookings'),
  ('checkin', 'Check-in reminders'),
  ('checkout', 'Checkout reminders'),
  ('payment', 'Payments'),
  ('finance', 'Finance'),
  ('message', 'Messages'),
  ('review', 'Reviews'),
  ('report', 'Problem reports'),
  ('rent', 'Rent reminders'),
];

class _PreferencesSheet extends StatefulWidget {
  const _PreferencesSheet({required this.repository});

  final NotificationRepository repository;

  @override
  State<_PreferencesSheet> createState() => _PreferencesSheetState();
}

class _PreferencesSheetState extends State<_PreferencesSheet> {
  bool _loaded = false;
  bool _sms = true;
  final Set<String> _muted = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.repository
        .preferences()
        .then((prefs) {
          if (!mounted) return;
          setState(() {
            _sms = prefs['sms'] as bool? ?? true;
            _muted
              ..clear()
              ..addAll(
                (prefs['mutedCategories'] as List<dynamic>? ?? const [])
                    .whereType<String>(),
              );
            _loaded = true;
          });
        })
        .catchError((Object error) {
          if (mounted) {
            setState(
              () => _error = error.toString().replaceFirst('Bad state: ', ''),
            );
          }
        });
  }

  Future<void> _save() async {
    try {
      await widget.repository.savePreferences(
        sms: _sms,
        muted: _muted.toList(),
      );
      if (mounted) Navigator.pop(context);
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr('Notification settings'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            if (!_loaded && _error == null) const LinearProgressIndicator(),
            if (_loaded) ...[
              SwitchListTile(
                title: Text(context.tr('SMS alerts')),
                subtitle: Text(
                  context.tr(
                    'In-app alerts are always on. Email is not available yet.',
                  ),
                ),
                value: _sms,
                onChanged: (value) => setState(() => _sms = value),
              ),
              const Divider(),
              Text(context.tr('Alert types')),
              for (final entry in _mutable)
                CheckboxListTile(
                  dense: true,
                  title: Text(context.tr(entry.$2)),
                  value: !_muted.contains(entry.$1),
                  onChanged: (on) => setState(() {
                    if (on == true) {
                      _muted.remove(entry.$1);
                    } else {
                      _muted.add(entry.$1);
                    }
                  }),
                ),
              const SizedBox(height: 8),
              FilledButton(onPressed: _save, child: Text(context.tr('Save'))),
            ],
          ],
        ),
      ),
    );
  }
}
