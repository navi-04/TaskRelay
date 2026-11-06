import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';

/// Set once the user has seen (or skipped) the welcome pages.
final onboardedProvider = StateProvider<bool>((ref) => ref.watch(prefsProvider).getBool('onboarded') ?? false);

const _pages = [
  (icon: Icons.check_circle_outline, title: 'Plan the day, finish the day', body: 'Add what you want to get done, set how much you can take on, and tick things off. Your list lives on your account, so the web and your phone always agree.'),
  (icon: Icons.star_outline, title: 'Top 3 and streaks', body: 'Star the three tasks that matter most each day. Finish a day on time to build a streak, and watch your habits get stronger.'),
  (icon: Icons.alarm, title: 'Alarms that ring', body: 'Give a task a time and your phone rings, even locked and offline. Ask Claude to plan your week from Profile and it can edit your tasks for you.'),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(prefsProvider).setBool('onboarded', true);
    ref.read(onboardedProvider.notifier).state = true;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final last = _page == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _finish, child: const Text('Skip'))),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) {
                final p = _pages[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(width: 112, height: 112, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)), child: Icon(p.icon, size: 56)),
                    const SizedBox(height: 32),
                    Text(p.title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    Text(p.body, textAlign: TextAlign.center, style: TextStyle(color: t.muted, fontSize: 16, height: 1.4)),
                  ]),
                );
              },
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < _pages.length; i++)
              AnimatedContainer(duration: const Duration(milliseconds: 150), margin: const EdgeInsets.all(4), width: i == _page ? 22 : 8, height: 8, decoration: BoxDecoration(color: i == _page ? t.accent : t.track, borderRadius: BorderRadius.circular(99))),
          ]),
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: last ? _finish : () => _controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                child: Text(last ? 'Get started' : 'Next'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
