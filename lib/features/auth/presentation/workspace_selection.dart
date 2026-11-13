import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../account/domain/account_models.dart';

class WorkspaceOption {
  const WorkspaceOption({
    required this.workspace,
    required this.icon,
    required this.examples,
    required this.summary,
    required this.capabilities,
  });

  final AgentWorkspace workspace;
  final IconData icon;
  final String examples;
  final String summary;
  final List<String> capabilities;
}

const List<WorkspaceOption> workspaceOptions = [
  WorkspaceOption(
    workspace: AgentWorkspace.rental,
    icon: HavenIcons.homeWorkOutlined,
    examples: 'Houses, long-term apartments, rooms',
    summary:
        'Advertise long-term rentals. Customers pay to unlock the exact location and your contact.',
    capabilities: [
      'Rental listings and maps',
      'Tenants and monthly rent',
      'Utilities and maintenance',
    ],
  ),
  WorkspaceOption(
    workspace: AgentWorkspace.apartment,
    icon: HavenIcons.apartmentOutlined,
    examples: 'Furnished apartments, entire-unit stays',
    summary:
        'Host whole-unit short stays with online booking, like a modern host dashboard.',
    capabilities: [
      'Photos, amenities and pricing',
      'Availability calendar',
      'Reservations and earnings',
    ],
  ),
  WorkspaceOption(
    workspace: AgentWorkspace.hotel,
    icon: HavenIcons.hotelOutlined,
    examples: 'Hotels, lodges, motels',
    summary:
        'Run room categories and physical rooms with online and walk-in reservations.',
    capabilities: [
      'Room categories and room IDs',
      'Shared availability',
      'Walk-ins and finances',
    ],
  ),
];

/// Asks "Which type of properties will you manage?" and returns the chosen
/// workspaces, or null if the dialog was closed.
Future<Set<AgentWorkspace>?> showWorkspaceSelection(
  BuildContext context, {
  Set<AgentWorkspace> initialSelection = const {},
}) {
  return showDialog<Set<AgentWorkspace>>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _WorkspaceSelectionDialog(initialSelection: initialSelection),
  );
}

class _WorkspaceSelectionDialog extends StatefulWidget {
  const _WorkspaceSelectionDialog({required this.initialSelection});
  final Set<AgentWorkspace> initialSelection;

  @override
  State<_WorkspaceSelectionDialog> createState() =>
      _WorkspaceSelectionDialogState();
}

class _WorkspaceSelectionDialogState extends State<_WorkspaceSelectionDialog> {
  late final Set<AgentWorkspace> _selected = {...widget.initialSelection};

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr('Which type of properties will you manage?'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                context.tr(
                  'Pick one or more. Each type opens its own workspace.',
                ),
                style: const TextStyle(color: HavenTheme.muted),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final option in workspaceOptions)
                      _WorkspaceCard(
                        option: option,
                        selected: _selected.contains(option.workspace),
                        onTap: () => setState(() {
                          if (!_selected.remove(option.workspace)) {
                            _selected.add(option.workspace);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop({..._selected}),
                child: Text(context.tr('Continue')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final WorkspaceOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? HavenTheme.lightMint : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? HavenTheme.teal : HavenTheme.mint,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(option.icon, color: HavenTheme.teal, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr(option.workspace.title),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr(option.examples),
                      style: const TextStyle(
                        color: HavenTheme.teal,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.tr(option.summary),
                      style: const TextStyle(height: 1.4, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final item in option.capabilities)
                          Chip(
                            label: Text(
                              context.tr(item),
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? HavenIcons.checkCircle : HavenIcons.circleOutlined,
                color: selected ? HavenTheme.teal : HavenTheme.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
