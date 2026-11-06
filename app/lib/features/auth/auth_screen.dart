import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api_exception.dart';
import '../../shared/widgets.dart';
import '../../state/providers.dart';

/// Sign in or create an account.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _register = false;
  bool _show = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).authenticate(email: _email.text.trim(), password: _password.text, register: _register);
      // The session changed: the app gate swaps this screen for the app.
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.kind == ApiErrorKind.unauthorized ? 'Wrong email or password.' : friendlyError(e);
      });
    }
  }

  Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Container(width: 40, height: 40, decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(10)), child: Icon(Icons.check, color: t.accentInk)),
                    const SizedBox(width: 12),
                    Text('TaskRelay', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  ]),
                  const SizedBox(height: 6),
                  Text('Finish what you plan, one day at a time.', style: TextStyle(color: t.muted)),
                  const SizedBox(height: 28),
                  Text(_register ? 'Create your account' : 'Sign in', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  if (_error != null) ErrorBanner(message: _error!),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) => (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) ? 'Enter a valid email address' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: !_show,
                    autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: _register ? 'Password (8+ characters)' : 'Password',
                      suffixIcon: IconButton(tooltip: _show ? 'Hide password' : 'Show password', icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: () => setState(() => _show = !_show)),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : (_register && v.length < 8 ? 'Use at least 8 characters' : null),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: _busy ? null : _submit, child: _busy ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: t.accentInk)) : Text(_register ? 'Create account' : 'Sign in')),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() {
                      _register = !_register;
                      _error = null;
                    }),
                    child: Text(_register ? 'I already have an account' : 'New here? Create an account'),
                  ),
                  const SizedBox(height: 16),
                  Wrap(alignment: WrapAlignment.center, children: [
                    TextButton(onPressed: () => _open(Config.privacyUrl), child: const Text('Privacy policy')),
                    TextButton(onPressed: () => _open(Config.accountDeletionUrl), child: const Text('Delete your account')),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
