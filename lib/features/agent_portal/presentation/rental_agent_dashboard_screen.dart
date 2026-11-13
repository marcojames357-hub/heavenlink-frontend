import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/formatters/currency_formatter.dart';
import '../../../core/config/env_config.dart';
import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/portal_sidebar.dart';
import '../../../core/widgets/portal_scaffold.dart';
import '../../account/domain/account_models.dart';
import '../../account/data/customer_data_repository.dart';
import '../../account/presentation/rental_messages_screen.dart';
import '../../properties/domain/property.dart';
import '../../properties/presentation/widgets/property_card.dart';
import '../../financial_management/presentation/financial_management_screen.dart';
import 'agent_dashboard_overview.dart';
import '../../notifications/presentation/notification_center_screen.dart';
import 'listing_editor_dialog.dart';
import '../state/agent_portal_store.dart';

/// Dashboard for rental property agents.
///
/// Shows their listings and unlock activity, and lets them
/// create/edit/remove properties.
class RentalAgentDashboardScreen extends StatefulWidget {
  const RentalAgentDashboardScreen({
    required this.store,
    required this.agentStore,
    super.key,
  });

  final HavenLinkStore store;
  final AgentPortalStore agentStore;

  @override
  State<RentalAgentDashboardScreen> createState() =>
      _RentalAgentDashboardScreenState();
}

class _RentalAgentDashboardScreenState
    extends State<RentalAgentDashboardScreen> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onDataChanged);
    widget.agentStore.addListener(_onDataChanged);
    _loadUnlockActivity();
  }

  @override
  void didUpdateWidget(covariant RentalAgentDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store
        ..removeListener(_onDataChanged)
        ..addListener(_onDataChanged);
    }
    if (oldWidget.agentStore != widget.agentStore) {
      oldWidget.agentStore
        ..removeListener(_onDataChanged)
        ..addListener(_onDataChanged);
      _loadUnlockActivity();
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onDataChanged);
    widget.agentStore.removeListener(_onDataChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.agentStore.isAuthorized) {
      return _UnauthorizedView();
    }

    return DefaultTabController(
      length: 6,
      child: Builder(
        builder: (context) {
          final tabs = DefaultTabController.of(context);
          final showSidebar = MediaQuery.sizeOf(context).width >= 980;
          final labels = [
            context.tr('Dashboard'),
            context.tr('My Listings'),
            context.tr('Unlock Activity'),
            context.tr('Messages'),
            context.tr('Profile'),
            context.tr('Financial Management'),
          ];
          const icons = [
            LucideIcons.layoutDashboard,
            LucideIcons.building2,
            LucideIcons.history,
            LucideIcons.notebookPen,
            LucideIcons.userRound,
            LucideIcons.wallet,
          ];

          return AnimatedBuilder(
            animation: tabs,
            builder: (context, _) => HavenPortalScaffold(
              showSidebar: showSidebar,
              sidebar: _buildSidebar(context, tabs, labels, icons, false),
              appBar: AppBar(
                automaticallyImplyLeading: !showSidebar,
                title: showSidebar
                    ? PortalHeaderTitle(
                        title: labels[tabs.index],
                        destinations: labels,
                        onDestination: tabs.animateTo,
                      )
                    : Text(context.tr('Rental Agent Portal')),
                actions: [
                  PortalAvatar(name: widget.store.currentUser?.fullName ?? ''),
                  NotificationBellButton(
                    tokenProvider: () =>
                        widget.store.authenticationRepository.accessToken,
                  ),
                  IconButton(
                    tooltip: context.tr('Sign out'),
                    onPressed: () {
                      widget.store.signOut();
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(LucideIcons.logOut),
                  ),
                ],
                bottom: showSidebar
                    ? null
                    : TabBar(
                        isScrollable: true,
                        tabs: [
                          for (var index = 0; index < labels.length; index++)
                            Tab(text: labels[index]),
                        ],
                      ),
              ),
              drawer: showSidebar
                  ? null
                  : Drawer(
                      child: _buildSidebar(context, tabs, labels, icons, true),
                    ),
              body: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        if (widget.agentStore.publishBlockedReason != null)
                          _PublishBlockedBanner(
                            reason: widget.agentStore.publishBlockedReason!,
                          ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              Builder(
                                builder: (tabContext) => AgentDashboardOverview(
                                  agentStore: widget.agentStore,
                                  isRental: true,
                                  onAddProperty: () =>
                                      _showAddPropertyDialog(context),
                                  onOpenTab: (index) => DefaultTabController.of(
                                    tabContext,
                                  ).animateTo(index),
                                ),
                              ),
                              _ListingsTab(
                                store: widget.store,
                                agentStore: widget.agentStore,
                              ),
                              _UnlockActivityTab(agentStore: widget.agentStore),
                              RentalMessagesScreen(
                                repository: CustomerDataRepository(
                                  tokenProvider: () => widget
                                      .store
                                      .authenticationRepository
                                      .accessToken,
                                ),
                                currentUserId:
                                    widget.store.currentUser?.id ?? '',
                                isAgent: true,
                              ),
                              _ProfileTab(agentStore: widget.agentStore),
                              FinancialManagementScreen(
                                businessModel:
                                    PropertyBusinessModel.contactUnlock,
                                properties: widget.agentStore.myListings,
                                tokenProvider: () => widget
                                    .store
                                    .authenticationRepository
                                    .accessToken,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              floatingActionButton: tabs.index == 1
                  ? FloatingActionButton.extended(
                      onPressed: () => _showAddPropertyDialog(context),
                      icon: const Icon(LucideIcons.plus),
                      label: Text(context.tr('Add Property')),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSidebar(
    BuildContext context,
    TabController tabs,
    List<String> labels,
    List<IconData> icons,
    bool closeOnSelect,
  ) {
    return Material(
      color: HavenTheme.white,
      child: SafeArea(
        child: ListView(
          key: const Key('portal-sidebar'),
          padding: const EdgeInsets.all(20),
          children: [
            PortalSidebarHeading(workspace: context.tr('Rental Agent Portal')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FilledButton.icon(
                onPressed: () {
                  if (closeOnSelect) Navigator.of(context).pop();
                  _showAddPropertyDialog(context);
                },
                icon: const Icon(LucideIcons.plus, size: 18),
                label: Text(context.tr('Add Property')),
              ),
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < labels.length; index++)
              PortalSidebarItem(
                icon: icons[index],
                label: labels[index],
                selected: tabs.index == index,
                onTap: () {
                  tabs.animateTo(index);
                  if (closeOnSelect) Navigator.of(context).pop();
                },
              ),
            TextButton.icon(
              onPressed: () {
                if (closeOnSelect) Navigator.of(context).pop();
                Navigator.of(this.context).pop();
              },
              icon: const Icon(HavenIcons.chevronLeft, size: 16),
              label: Text(context.tr('Back to marketplace')),
            ),
          ],
        ),
      ),
    );
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  void _loadUnlockActivity() {
    widget.agentStore.loadUnlockActivity().catchError((Object error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });
  }

  void _showAddPropertyDialog(BuildContext context) {
    if (!widget.agentStore.canPublish) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.agentStore.publishBlockedReason ?? 'Cannot publish listings',
          ),
        ),
      );
      return;
    }
    showListingEditorDialog(
      context: context,
      store: widget.store,
      businessModel: PropertyBusinessModel.contactUnlock,
    );
  }
}

class _UnauthorizedView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Rental Agent Portal'))),
      body: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  HavenIcons.lockOutlined,
                  size: 48,
                  color: HavenTheme.muted,
                ),
                const SizedBox(height: 16),
                Text(
                  context.tr('Access Restricted'),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr(
                    'You do not have permission to access the rental agent portal.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PublishBlockedBanner extends StatelessWidget {
  const _PublishBlockedBanner({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.orange.shade100,
      child: Row(
        children: [
          const Icon(HavenIcons.warning, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Publishing restricted: $reason',
              style: const TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListingsTab extends StatelessWidget {
  const _ListingsTab({required this.store, required this.agentStore});

  final HavenLinkStore store;
  final AgentPortalStore agentStore;

  @override
  Widget build(BuildContext context) {
    final listings = agentStore.myListings;

    if (listings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              HavenIcons.homeWorkOutlined,
              size: 48,
              color: HavenTheme.muted,
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('No listings yet'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              context.tr(
                'Create your first rental property listing to get started.',
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: listings.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final property = listings[index];
        return _ListingCard(
          property: property,
          store: store,
          agentStore: agentStore,
        );
      },
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({
    required this.property,
    required this.store,
    required this.agentStore,
  });

  final Property property;
  final HavenLinkStore store;
  final AgentPortalStore agentStore;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PropertyCard(property: property, store: store, onTap: () {}),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _StatusChip(status: property.listingStatus),
                const Spacer(),
                IconButton(
                  icon: const Icon(HavenIcons.edit),
                  onPressed: () => showListingEditorDialog(
                    context: context,
                    store: store,
                    businessModel: PropertyBusinessModel.contactUnlock,
                    initial: property,
                  ),
                  tooltip: context.tr('Edit listing'),
                ),
                IconButton(
                  icon: const Icon(HavenIcons.delete),
                  onPressed: () => _showDeleteDialog(context, property),
                  tooltip: context.tr('Delete listing'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, Property property) {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Listing'),
        content: Text('Are you sure you want to delete "${property.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              navigator.pop();
              store.deleteListing(property.id).catchError((error) {
                messenger.showSnackBar(
                  SnackBar(content: Text(error.toString())),
                );
              });
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ListingStatus status;

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;

    switch (status) {
      case ListingStatus.published:
        color = Colors.green;
        icon = HavenIcons.checkCircle;
        break;
      case ListingStatus.pendingReview:
        color = Colors.orange;
        icon = HavenIcons.pending;
        break;
      case ListingStatus.paused:
        color = Colors.grey;
        icon = HavenIcons.pauseCircle;
        break;
      case ListingStatus.rejected:
        color = Colors.red;
        icon = HavenIcons.cancel;
        break;
      default:
        color = Colors.blue;
        icon = HavenIcons.drafts;
    }

    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(status.label),
      backgroundColor: color.withValues(alpha: 0.1),
    );
  }
}

class _UnlockActivityTab extends StatelessWidget {
  const _UnlockActivityTab({required this.agentStore});

  final AgentPortalStore agentStore;

  @override
  Widget build(BuildContext context) {
    final activity = agentStore.unlockActivity;

    if (activity.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(HavenIcons.keyOutlined, size: 48, color: HavenTheme.muted),
            const SizedBox(height: 16),
            Text(
              'No unlock activity yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'When customers unlock your listings, activity will appear here.',
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: activity.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = activity[index];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(HavenIcons.lockOpen)),
            title: Text(item.listingName),
            subtitle: Text('Unlocked ${_date(item.record.createdAt)}'),
            trailing: Text(formatTzs(item.record.amountTzs ?? 0)),
          ),
        );
      },
    );
  }
}

class _ProfileTab extends StatefulWidget {
  const _ProfileTab({required this.agentStore});

  final AgentPortalStore agentStore;

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _agencyNameController;
  late final TextEditingController _bioController;
  late final TextEditingController _photoUrlController;
  late final TextEditingController _videoUrlController;
  bool _savingProfile = false;

  @override
  void initState() {
    super.initState();
    final agent = widget.agentStore.agent;
    _displayNameController = TextEditingController(text: agent?.fullName ?? '');
    _agencyNameController = TextEditingController(text: '');
    _bioController = TextEditingController(text: '');
    _photoUrlController = TextEditingController(text: '');
    _videoUrlController = TextEditingController(text: '');
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await widget.agentStore.loadProfile();
      if (!mounted) return;
      setState(() {
        _displayNameController.text = profile.displayName;
        _agencyNameController.text = profile.agencyName;
        _bioController.text = profile.bio;
        _photoUrlController.text = profile.photoUrl;
        _videoUrlController.text = profile.videoUrl;
      });
    } catch (error) {
      if (!mounted || !EnvConfig.backendConfigured) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _agencyNameController.dispose();
    _bioController.dispose();
    _photoUrlController.dispose();
    _videoUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agent = widget.agentStore.agent;
    if (agent == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final photoUrl = _photoUrlController.text.trim();
    final videoUrl = _videoUrlController.text.trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (photoUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: Image.network(
                        photoUrl,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            CircleAvatar(
                              radius: 40,
                              child: Text(agent.fullName[0].toUpperCase()),
                            ),
                      ),
                    )
                  else
                    CircleAvatar(
                      radius: 40,
                      child: Text(agent.fullName[0].toUpperCase()),
                    ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayNameController.text.isEmpty
                              ? agent.fullName
                              : _displayNameController.text,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(agent.email),
                        const SizedBox(height: 6),
                        Text(agent.phone),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              TextField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _agencyNameController,
                decoration: const InputDecoration(
                  labelText: 'Agency name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bioController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Bio / profile details',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _photoUrlController,
                decoration: const InputDecoration(
                  labelText: 'Photo upload URL',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _videoUrlController,
                decoration: const InputDecoration(
                  labelText: 'Video upload URL',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              if (photoUrl.isNotEmpty) ...[
                const Text(
                  'Photo preview',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    photoUrl,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 180,
                      color: Colors.grey.shade200,
                      child: const Center(child: Text('Invalid photo URL')),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (videoUrl.isNotEmpty) ...[
                const Text(
                  'Video preview',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey.shade100,
                  ),
                  child: Row(
                    children: [
                      const Icon(HavenIcons.videocam, color: Colors.deepPurple),
                      const SizedBox(width: 12),
                      Expanded(child: Text(videoUrl)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              _ProfileRow(label: 'Role', value: agent.role.identifier),
              _ProfileRow(
                label: 'Verification',
                value: agent.verification.name,
              ),
              _ProfileRow(
                label: 'Account Status',
                value: agent.accountEnabled ? 'Active' : 'Suspended',
              ),
              if (agent.capabilities.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Capabilities:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: agent.capabilities
                      .map((cap) => Chip(label: Text(cap.name)))
                      .toList(),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _savingProfile ? null : _saveProfile,
                  icon: _savingProfile
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(HavenIcons.saveAlt),
                  label: Text(
                    _savingProfile ? 'Saving profile' : 'Save profile details',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    final agent = widget.agentStore.agent;
    if (agent == null) return;
    setState(() => _savingProfile = true);
    try {
      await widget.agentStore.saveProfile(
        AgentProfile(
          userId: agent.id,
          displayName: _displayNameController.text.trim(),
          agencyName: _agencyNameController.text.trim(),
          bio: _bioController.text.trim(),
          phone: agent.phone,
          email: agent.email,
          photoUrl: _photoUrlController.text.trim(),
          videoUrl: _videoUrlController.text.trim(),
          role: agent.role,
          capabilities: agent.capabilities,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            EnvConfig.backendConfigured
                ? 'Agent profile saved.'
                : 'Profile saved for this preview session.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

String _date(DateTime value) => '${value.day}/${value.month}/${value.year}';
