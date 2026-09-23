import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/ui/app_logo.dart';
import '../../../core/ui/widgets.dart';

/// Login, or registration of the single account when the server has none.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // After logout or on cold start the account state may be unknown.
    if (ref.read(sessionControllerProvider).value?.hasUser == null) {
      Future.microtask(_refresh);
    }
  }

  Future<void> _refresh() async {
    try {
      await ref.read(sessionControllerProvider.notifier).refreshHasUser();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit(bool register) async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .authenticate(email: _email.text, password: _password.text, register: register);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionControllerProvider).value;
    final hasUser = session?.hasUser;
    final register = hasUser == false;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: hasUser == null && _error == null
                  ? const Center(child: CircularProgressIndicator())
                  : Form(
                      key: _form,
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Center(child: AppLogo()),
                            const SizedBox(height: 16),
                            Text(register ? 'Create your account' : 'Welcome back',
                                style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                            const SizedBox(height: 8),
                            Text(
                              register
                                  ? 'This server has no account yet. The account you create now will be the only one. '
                                      'Registration closes after that.'
                                  : 'Sign in to ${session?.serverUrl ?? 'your server'}.',
                              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),
                            TextFormField(
                              controller: _email,
                              enabled: !_busy,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              autofillHints: const [AutofillHints.email],
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                              validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _password,
                              enabled: !_busy,
                              obscureText: _obscure,
                              autofillHints: [register ? AutofillHints.newPassword : AutofillHints.password],
                              textInputAction: register ? TextInputAction.next : TextInputAction.done,
                              onFieldSubmitted: register ? null : (_) => _submit(false),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.key_outlined),
                                helperText: register ? 'At least 8 characters' : null,
                                suffixIcon: IconButton(
                                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Enter your password';
                                if (register && v.length < 8) return 'Use at least 8 characters';
                                return null;
                              },
                            ),
                            if (register) ...[
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _confirm,
                                enabled: !_busy,
                                obscureText: _obscure,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(true),
                                decoration: const InputDecoration(
                                    labelText: 'Confirm password', prefixIcon: Icon(Icons.key_outlined)),
                                validator: (v) => v != _password.text ? 'Passwords do not match' : null,
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Text(_error!, style: TextStyle(color: theme.colorScheme.error), textAlign: TextAlign.center),
                            ],
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: _busy || hasUser == null ? null : () => _submit(register),
                              child: _busy
                                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Text(register ? 'Create account' : 'Sign in'),
                            ),
                            if (hasUser == null) TextButton(onPressed: _refresh, child: const Text('Retry')),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _busy ? null : () => ref.read(sessionControllerProvider.notifier).changeServer(),
                              child: const Text('Use a different server'),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
