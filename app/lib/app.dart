import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/app_shell.dart';
import 'state/providers.dart';

class TaskRelayApp extends ConsumerWidget {
  const TaskRelayApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'TaskRelay',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider), // White, Black, or follow the device
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('hi'), Locale('ta'), Locale('es'), Locale('fr'), Locale('de'), Locale('pt'), Locale('ar')],
      home: const _Gate(),
    );
  }
}

/// Decides what to show from the session: loading, "update required", onboarding/sign-in, or the app.
class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return switch (session) {
      SessionLoading() => const _Splash(),
      UpgradeRequired() => const _UpdateRequired(),
      SignedOut() => ref.watch(onboardedProvider) ? const AuthScreen() : const OnboardingScreen(),
      SignedIn() => const AppShell(),
    };
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 72, height: 72, decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(18)), child: Icon(Icons.check, size: 44, color: t.accentInk)),
          const SizedBox(height: 16),
          const Text('TaskRelay', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

/// The server told us this version is too old to keep working.
class _UpdateRequired extends StatelessWidget {
  const _UpdateRequired();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.system_update, size: 56),
              SizedBox(height: 16),
              Text('Please update TaskRelay', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
              SizedBox(height: 8),
              Text('This version is too old to talk to the server. Update the app from the Play Store to continue.', textAlign: TextAlign.center),
            ]),
          ),
        ),
      );
}
