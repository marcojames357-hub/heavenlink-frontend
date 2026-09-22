import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class PropertyPhoto extends StatelessWidget {
  const PropertyPhoto({
    required this.imageUrl,
    required this.height,
    super.key,
  });

  final String imageUrl;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      imageUrl,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        height: height,
        color: HavenTheme.forest.withValues(alpha: 0.08),
        alignment: Alignment.center,
        child: const Icon(
          Icons.home_work_outlined,
          size: 42,
          color: HavenTheme.forest,
        ),
      ),
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : Container(
              height: height,
              color: HavenTheme.forest.withValues(alpha: 0.06),
              alignment: Alignment.center,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
    );
  }
}
