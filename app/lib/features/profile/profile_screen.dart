import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api_exception.dart';
import '../../shared/widgets.dart';
import '../../state/providers.dart';
import 'ai_access_card.dart';
import 'settings_cards.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(meProvider);
          ref.invalidate(settingsProvider);
          ref.invalidate(labelsProvider);
          ref.invalidate(activityProvider);
          ref.invalidate(syncStatusProvider);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (me != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(me.email, style: TextStyle(color: context.tr.muted))),
            const _AppearanceCard(),
            const AiAccessCard(),
            const RemindersCard(),
            const LabelsCard(),
            const AlarmHealthCard(),
            const _AccountCard(),
            const _AboutCard(),
          ],
        ),
      ),
    );
  }
}

/// White, Black, or follow the device. Saved on this phone only.
class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return SurfaceCard(
      semanticLabel: 'Appearance',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Appearance'),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('White')),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Black')),
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('Device')),
            ],
            selected: {mode},
            onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
          ),
        ),
        const SizedBox(height: 6),
        Text('Saved on this phone.', style: TextStyle(color: context.tr.muted, fontSize: 12)),
      ]),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard();

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final cur = TextEditingController(), next = TextEditingController(), again = TextEditingController();
    String? error;
    var busy = false;
    final done = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Change password'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('⚠  $error', style: const TextStyle(fontWeight: FontWeight.w700))),
              TextField(controller: cur, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
              const SizedBox(height: 8),
              TextField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: 'New password (8+ characters)')),
              const SizedBox(height: 8),
              TextField(controller: again, obscureText: true, decoration: const InputDecoration(labelText: 'Repeat new password')),
            ]),
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (next.text.length < 8) return setState(() => error = 'The new password must be at least 8 characters.');
                      if (next.text != again.text) return setState(() => error = 'The new passwords don’t match.');
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await ref.read(apiProvider).changePassword(cur.text, next.text);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } on ApiException catch (e) {
                        setState(() {
                          busy = false;
                          error = friendlyError(e);
                        });
                      }
                    },
              child: Text(busy ? 'Saving…' : 'Change'),
            ),
          ],
        ),
      ),
    );
    cur.dispose();
    next.dispose();
    again.dispose();
    if (done == true && context.mounted) showMessage(context, 'Password changed. Other devices were signed out.');
  }

  Future<void> _copyData(BuildContext context, WidgetRef ref) async {
    try {
      final bytes = await ref.read(apiProvider).exportData();
      await Clipboard.setData(ClipboardData(text: utf8.decode(bytes)));
      if (context.mounted) showMessage(context, 'Your data (JSON) was copied: ${(bytes.length / 1024).ceil()} KB. You can also download it from the website.');
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e));
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final pw = TextEditingController();
    String? error;
    var busy = false;
    final done = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Delete your account?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('This permanently deletes your account, tasks, history and settings. It cannot be undone. Enter your password to confirm.'),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('⚠  $error', style: const TextStyle(fontWeight: FontWeight.w700))),
            const SizedBox(height: 12),
            TextField(controller: pw, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
          ]),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await ref.read(apiProvider).deleteAccount(pw.text);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } on ApiException catch (e) {
                        setState(() {
                          busy = false;
                          error = friendlyError(e);
                        });
                      }
                    },
              child: Text(busy ? 'Deleting…' : 'Delete everything'),
            ),
          ],
        ),
      ),
    );
    pw.dispose();
    if (done == true) await ref.read(sessionProvider.notifier).expire();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SurfaceCard(
      semanticLabel: 'Account',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Account'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: () => _changePassword(context, ref), icon: const Icon(Icons.lock_outline, size: 18), label: const Text('Change password')),
          OutlinedButton.icon(onPressed: () => _copyData(context, ref), icon: const Icon(Icons.download_outlined, size: 18), label: const Text('Copy my data')),
          OutlinedButton.icon(
            onPressed: () async {
              final c = await askChoice(context, title: 'Sign out?', message: 'Your alarms on this phone are removed until you sign in again.', choices: [(id: 'yes', label: 'Sign out', destructive: false)]);
              if (c != null) await ref.read(sessionProvider.notifier).signOut();
            },
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign out'),
          ),
        ]),
        const SizedBox(height: 16),
        Text('Danger zone', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(side: BorderSide(color: Theme.of(context).colorScheme.onSurface, width: 2)),
            onPressed: () async {
              final c = await askChoice(context, title: 'Delete ALL your tasks?', message: 'Every task and its history is removed. Your account and settings stay. This cannot be undone.', choices: [(id: 'yes', label: 'Delete all tasks', destructive: true)]);
              if (c == null) return;
              try {
                await ref.read(taskActionsProvider).deleteAllTasks();
                if (context.mounted) showMessage(context, 'All tasks deleted.');
              } on ApiException catch (e) {
                if (context.mounted) showMessage(context, friendlyError(e));
              }
            },
            child: const Text('Delete all my tasks'),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(side: BorderSide(color: Theme.of(context).colorScheme.onSurface, width: 2)),
            onPressed: () => _deleteAccount(context, ref),
            child: const Text('Delete my account'),
          ),
        ]),
      ]),
    );
  }
}

class _AboutCard extends ConsumerWidget {
  const _AboutCard();

  Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && context.mounted) showMessage(context, 'Could not open the link: $url');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider);
    return SurfaceCard(
      semanticLabel: 'About',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('About'),
        Text('TaskRelay $version', style: TextStyle(color: context.tr.muted)),
        Wrap(children: [
          TextButton(onPressed: () => _open(context, Config.privacyUrl), child: const Text('Privacy policy')),
          TextButton(onPressed: () => _open(context, Config.accountDeletionUrl), child: const Text('How deletion works')),
        ]),
      ]),
    );
  }
}
