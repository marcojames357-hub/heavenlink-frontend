import 'package:flutter/material.dart';

class LocationPinPicker extends StatelessWidget {
  const LocationPinPicker({
    required this.latitude,
    required this.longitude,
    required this.onChanged,
    super.key,
  });

  final double? latitude;
  final double? longitude;
  final void Function(double latitude, double longitude) onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 120,
    alignment: Alignment.center,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Text(
      'Open Haven Link in Chrome to pin the location on a map.',
    ),
  );
}
