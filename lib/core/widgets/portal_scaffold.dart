import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../theme/app_theme.dart';
import '../theme/haven_icons.dart';

/// Full-height desktop navigation with a content-only header, matching Make.
/// Mobile keeps the existing drawer, tab controls, and actions intact.
class HavenPortalScaffold extends StatelessWidget {
  const HavenPortalScaffold({
    required this.showSidebar,
    required this.sidebar,
    required this.appBar,
    required this.body,
    this.drawer,
    this.floatingActionButton,
    super.key,
  });
  final bool showSidebar;
  final Widget sidebar, body;
  final PreferredSizeWidget appBar;
  final Widget? drawer, floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final content = Scaffold(
      appBar: appBar,
      drawer: drawer,
      body: body,
      floatingActionButton: floatingActionButton,
    );
    if (!showSidebar) return content;
    return Row(
      children: [
        Container(
          width: 250,
          decoration: const BoxDecoration(
            color: HavenTheme.white,
            border: Border(right: BorderSide(color: HavenTheme.border)),
          ),
          child: sidebar,
        ),
        Expanded(child: content),
      ],
    );
  }
}

/// Search navigates only among destinations already authorized by the portal.
class PortalHeaderTitle extends StatelessWidget {
  const PortalHeaderTitle({
    required this.title,
    required this.destinations,
    required this.onDestination,
    super.key,
  });
  final String title;
  final List<String> destinations;
  final ValueChanged<int> onDestination;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 300) {
        return Text(title, maxLines: 1, overflow: TextOverflow.ellipsis);
      }
      return Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Autocomplete<int>(
            displayStringForOption: (i) => destinations[i],
            optionsBuilder: (value) => destinations.indexed
                .where(
                  (e) =>
                      value.text.isNotEmpty &&
                      e.$2.toLowerCase().contains(value.text.toLowerCase()),
                )
                .map((e) => e.$1),
            onSelected: onDestination,
            fieldViewBuilder: (context, controller, focus, submit) => TextField(
              controller: controller,
              focusNode: focus,
              style: Theme.of(context).textTheme.bodySmall,
              decoration: InputDecoration(
                hintText: context.tr('Search workspace…'),
                prefixIcon: const Icon(HavenIcons.search, size: 17),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                fillColor: HavenTheme.veryLightMint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => submit(),
            ),
          ),
        ),
      );
    },
  );
}

class PortalAvatar extends StatelessWidget {
  const PortalAvatar({required this.name, this.onTap, super.key});
  final String name;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2);
    final initials = parts.map((p) => p.characters.first).join().toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Semantics(
        label: name,
        button: onTap != null,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: CircleAvatar(
            radius: 18,
            backgroundColor: HavenTheme.lightMint,
            foregroundColor: HavenTheme.forest,
            child: Text(
              initials.isEmpty ? 'HL' : initials,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }
}
