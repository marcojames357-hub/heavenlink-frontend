import 'package:flutter/material.dart';

import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../access/domain/access_control.dart';
import '../../account/presentation/account_screen.dart';
import '../../agent_portal/presentation/accommodation_agent_dashboard_screen.dart';
import '../../agent_portal/presentation/rental_agent_dashboard_screen.dart';
import '../../agent_portal/state/agent_portal_store.dart';
import '../../admin/presentation/admin_dashboard_screen.dart';
import '../../home/presentation/home_screen.dart';
import '../../properties/domain/property.dart';
import '../../properties/presentation/property_detail_screen.dart';
import '../../search/presentation/property_browse_screen.dart';

class HavenLinkShell extends StatefulWidget {
  const HavenLinkShell({required this.store, super.key});

  final HavenLinkStore store;

  @override
  State<HavenLinkShell> createState() => _HavenLinkShellState();
}

class _HavenLinkShellState extends State<HavenLinkShell> {
  int _selectedIndex = 0;

  late final Map<Portal, AgentPortalStore> _portalStores = {
    Portal.rentalAgent: AgentPortalStore(
      portal: Portal.rentalAgent,
      store: widget.store,
    ),
    Portal.stayAgent: AgentPortalStore(
      portal: Portal.stayAgent,
      store: widget.store,
    ),
  };

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void didUpdateWidget(covariant HavenLinkShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStoreChanged);
      widget.store.addListener(_onStoreChanged);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: HavenTheme.forest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.home_rounded,
                size: 21,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 9),
            Text.rich(
              const TextSpan(
                text: 'Haven',
                children: [
                  TextSpan(
                    text: 'Link',
                    style: TextStyle(color: HavenTheme.teal),
                  ),
                ],
              ),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Account',
            onPressed: () => setState(() => _selectedIndex = 3),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: SizedBox.expand(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: _selectedPage(),
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            label: 'Explore',
          ),
          NavigationDestination(
            icon: Icon(Icons.hotel_outlined),
            label: 'Stays',
          ),
          NavigationDestination(
            icon: Icon(Icons.key_outlined),
            label: 'Rentals',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Account',
          ),
        ],
      ),
    );
  }

  Widget _selectedPage() => switch (_selectedIndex) {
    0 => HomeScreen(
      store: widget.store,
      onBrowse: _browse,
      onOpenProperty: _openProperty,
    ),
    1 => PropertyBrowseScreen(
      store: widget.store,
      businessModel: PropertyBusinessModel.bookable,
      onOpenProperty: _openProperty,
    ),
    2 => PropertyBrowseScreen(
      store: widget.store,
      businessModel: PropertyBusinessModel.contactUnlock,
      onOpenProperty: _openProperty,
    ),
    _ => AccountScreen(
      store: widget.store,
      onOpenProperty: _openProperty,
      onOpenPortal: _openPortal,
    ),
  };

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _browse(PropertyBusinessModel model) {
    setState(
      () => _selectedIndex = model == PropertyBusinessModel.bookable ? 1 : 2,
    );
  }

  void _openPortal(Portal portal) {
    if (!AccessControl.canOpenPortal(widget.store.currentUser, portal)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This account cannot open that portal.')),
      );
      return;
    }
    final Widget page = switch (portal) {
      Portal.rentalAgent => RentalAgentDashboardScreen(
        store: widget.store,
        agentStore: _portalStores[portal]!,
      ),
      Portal.stayAgent => StayAgentDashboardScreen(
        store: widget.store,
        agentStore: _portalStores[portal]!,
      ),
      Portal.admin => AdminDashboardScreen(store: widget.store),
      Portal.customer => AccountScreen(
        store: widget.store,
        onOpenProperty: _openProperty,
        onOpenPortal: _openPortal,
      ),
    };
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (context) => page));
  }

  void _openProperty(Property property) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            PropertyDetailScreen(property: property, store: widget.store),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.store.recordViewing(property.id);
    });
  }
}
