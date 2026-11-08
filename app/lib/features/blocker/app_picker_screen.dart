import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../platform/platform_bridge.dart';
import '../../shared/widgets.dart';
import '../../state/providers.dart';
import 'blocker_logic.dart';

/// The most apps the phone will block (the native side enforces the same limit).
const maxBlockedApps = 60;

/// Pick the apps to block: the popular distractions that are installed come first, then everything else you can open.
/// Each tap is saved at once.
class AppPickerScreen extends ConsumerStatefulWidget {
  const AppPickerScreen({super.key});

  @override
  ConsumerState<AppPickerScreen> createState() => _AppPickerScreenState();
}

class _AppPickerScreenState extends ConsumerState<AppPickerScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _set(BlockerConfig c, String package, bool on) {
    final next = on
        ? [...c.packages, package]
        : c.packages.where((p) => p != package).toList();
    return ref
        .read(blockerConfigProvider.notifier)
        .save(c.copyWith(packages: next));
  }

  @override
  Widget build(BuildContext context) {
    final apps = ref.watch(installedAppsProvider);
    final config =
        ref.watch(blockerConfigProvider).valueOrNull ?? const BlockerConfig();
    final query = _search.text.trim().toLowerCase();
    return Scaffold(
      appBar: AppBar(title: const Text('Choose apps to block')),
      body: AsyncBodyList<List<InstalledApp>>(
        value: apps,
        onRetry: () => ref.invalidate(installedAppsProvider),
        builder: (all) {
          final matches = [
            for (final a in all)
              if (query.isEmpty || a.label.toLowerCase().contains(query)) a,
          ];
          final suggested = query.isEmpty
              ? [
                  for (final p in suggestedPackages)
                    ...matches.where((a) => a.package == p),
                ]
              : const <InstalledApp>[];
          final rest = [
            for (final a in matches)
              if (!suggested.contains(a)) a,
          ];
          final full = config.packages.length >= maxBlockedApps;

          Widget row(InstalledApp a) {
            final on = config.packages.contains(a.package);
            return CheckboxListTile(
              value: on,
              onChanged: (!on && full)
                  ? null
                  : (v) => _set(config, a.package, v == true),
              title: Text(
                a.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              secondary: _AppIcon(package: a.package),
              controlAffinity: ListTileControlAffinity.trailing,
            );
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    labelText: 'Search apps',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  full
                      ? 'You can block up to $maxBlockedApps apps.'
                      : '${config.packages.length} selected. Settings and Phone are never listed, so they can never be blocked.',
                  style: TextStyle(color: context.tr.muted, fontSize: 12),
                ),
              ),
              if (suggested.isNotEmpty) ...[
                const _Heading('Popular distractions'),
                for (final a in suggested) row(a),
                const _Heading('All apps'),
              ],
              for (final a in rest) row(a),
              if (matches.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No app matches that search.')),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    ),
  );
}

/// The app's own icon, drawn in greys: this app is strictly black and white, and other apps' colours stop at the door.
class _AppIcon extends ConsumerWidget {
  const _AppIcon({required this.package});
  final String package;

  /// Luminance-weighted grey, same alpha.
  static const _grey = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icon = ref.watch(appIconProvider(package)).valueOrNull;
    const size = 36.0;
    if (icon == null || icon.isEmpty) {
      return const SizedBox(
        width: size,
        height: size,
        child: Icon(Icons.apps_outlined),
      );
    }
    return ColorFiltered(
      colorFilter: _grey,
      child: Image.memory(
        icon,
        width: size,
        height: size,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const Icon(Icons.apps_outlined),
      ),
    );
  }
}

/// Loading / error-with-retry / data for a screen whose body is not a plain scrollable list (the picker builds its own).
class AsyncBodyList<T> extends StatelessWidget {
  const AsyncBodyList({
    super.key,
    required this.value,
    required this.builder,
    required this.onRetry,
  });
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) return builder(value.requireValue);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [AsyncBody<T>(value: value, onRetry: onRetry, data: builder)],
    );
  }
}
