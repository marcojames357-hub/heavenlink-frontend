import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class DemoEnvironmentBanner extends StatelessWidget {
  const DemoEnvironmentBanner({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Material(
        color: HavenTheme.darkTeal,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            child: Text(
              'LOCAL DEMO \u00b7 Use demo logins \u00b7 SMS and payments disabled',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                color: HavenTheme.white,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
      Expanded(child: child),
    ],
  );
}
