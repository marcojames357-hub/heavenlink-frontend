import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/state/haven_link_store.dart';
import '../core/theme/app_theme.dart';
import '../core/config/env_config.dart';
import '../core/widgets/demo_environment_banner.dart';
import '../features/home/presentation/haven_link_shell.dart';

class HavenLinkApp extends StatefulWidget {
  const HavenLinkApp({super.key});

  @override
  State<HavenLinkApp> createState() => _HavenLinkAppState();
}

class _HavenLinkAppState extends State<HavenLinkApp> {
  late final HavenLinkStore _store;
  Locale _locale = const Locale('en');

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
    return ShadTheme(
      data: HavenTheme.shadcn,
      child: MaterialApp(
        title: 'Haven Link',
        debugShowCheckedModeBanner: false,
        theme: HavenTheme.light,
        builder: (context, child) => EnvConfig.demoMode
            ? DemoEnvironmentBanner(child: child ?? const SizedBox.shrink())
            : child ?? const SizedBox.shrink(),
        locale: _locale,
        supportedLocales: const [Locale('en'), Locale('sw')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: HavenLinkShell(
          store: _store,
          locale: _locale,
          onLocaleChanged: (locale) => setState(() => _locale = locale),
        ),
      ),
    );
  }
}
