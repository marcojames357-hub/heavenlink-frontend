import 'package:flutter/material.dart';

import '../core/state/haven_link_store.dart';
import '../core/theme/app_theme.dart';
import '../features/home/presentation/haven_link_shell.dart';

class HavenLinkApp extends StatefulWidget {
  const HavenLinkApp({super.key});

  @override
  State<HavenLinkApp> createState() => _HavenLinkAppState();
}

class _HavenLinkAppState extends State<HavenLinkApp> {
  late final HavenLinkStore _store;

  @override
  void initState() {
    super.initState();
    _store = HavenLinkStore();
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Haven Link',
      debugShowCheckedModeBanner: false,
      theme: HavenTheme.light,
      home: HavenLinkShell(store: _store),
    );
  }
}
