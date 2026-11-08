import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../platform/platform_bridge.dart';
import '../../shared/widgets.dart';
import '../../state/providers.dart';
import 'blocker_screen.dart';

/// Profile's doorway to "Block distracting apps": a one-line summary and a button.
class BlockerCard extends ConsumerWidget {
  const BlockerCard({super.key});

  static String modeName(BlockMode m) => switch (m) {
    BlockMode.untilDone => 'until my tasks are done',
    BlockMode.freeTime => 'while a task is running',
    BlockMode.setTimes => 'only at set times',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tr;
    final config = ref.watch(blockerConfigProvider).valueOrNull;
    final status = ref.watch(blockerStatusProvider).valueOrNull;
    final on = config?.enabled == true;
    final needsAccess = on && status != null && !status.serviceEnabled;
    return SurfaceCard(
      semanticLabel: 'Block distracting apps',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Block distracting apps'),
          Text(
            on
                ? 'On: ${plural(config!.packages.length, 'app')}, ${modeName(config.mode)}.'
                : 'Keep distracting apps closed until your tasks are done, or open them only at times you choose.',
            style: TextStyle(color: t.muted),
          ),
          if (needsAccess)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: IconText(
                Icons.warning_amber_outlined,
                'Needs Accessibility access to start',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BlockerScreen()),
            ),
            icon: const Icon(Icons.block, size: 18),
            label: Text(on ? 'Manage' : 'Set up'),
          ),
        ],
      ),
    );
  }
}
