import 'package:flutter/material.dart';

class PropertyMapFrame extends StatelessWidget {
  const PropertyMapFrame({
    required this.locationQuery,
    required this.zoom,
    super.key,
  });

  final String locationQuery;
  final int zoom;

  @override
  Widget build(BuildContext context) => Container(
    height: 240,
    alignment: Alignment.center,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Text('Open Haven Link in Chrome to view the map.'),
  );
}
