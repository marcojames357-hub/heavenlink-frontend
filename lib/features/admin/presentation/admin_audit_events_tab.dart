import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';
import 'package:intl/intl.dart';

import '../../../core/config/env_config.dart';
import '../../../core/theme/app_theme.dart';
import '../data/admin_dashboard_repository.dart';

class AdminAuditEventsTab extends StatefulWidget {
  const AdminAuditEventsTab({required this.tokenProvider, super.key});

  final String? Function() tokenProvider;

  @override
  State<AdminAuditEventsTab> createState() => _AdminAuditEventsTabState();
}

class _AdminAuditEventsTabState extends State<AdminAuditEventsTab> {
  late final AdminDashboardRepository _repository = AdminDashboardRepository(
    tokenProvider: widget.tokenProvider,
  );
  Future<List<AdminAuditEvent>>? _events;

  @override
  void initState() {
    super.initState();
    if (EnvConfig.backendConfigured) {
      _events = _repository.loadAuditEvents();
    }
  }

  void _reload() {
    setState(() => _events = _repository.loadAuditEvents());
  }

  @override
  Widget build(BuildContext context) {
    final events = _events;
    if (events == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Audit history requires a configured Haven Link backend.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Administrator activity',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Refresh audit history',
                onPressed: _reload,
                icon: const Icon(HavenIcons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<AdminAuditEvent>>(
            future: events,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _reload,
                          icon: const Icon(HavenIcons.refresh),
                          label: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final events = snapshot.data ?? const [];
              if (events.isEmpty) {
                return const Center(child: Text('No administrator activity.'));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                itemCount: events.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) =>
                    _AuditEventCard(event: events[index]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AuditEventCard extends StatelessWidget {
  const _AuditEventCard({required this.event});

  final AdminAuditEvent event;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(HavenIcons.history, color: HavenTheme.forest),
        title: Text(event.action),
        subtitle: Text(
          '${event.entityType} · ${event.entityId}\n'
          '${event.actorName} · ${DateFormat.yMMMd().add_jm().format(event.createdAt.toLocal())}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(event.metadata),
            ),
          ),
        ],
      ),
    );
  }
}
