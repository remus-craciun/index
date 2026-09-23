import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/server_url.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/ui/app_logo.dart';
import '../../../core/ui/widgets.dart';

/// First screen: asks for the server address and verifies it.
class ServerSetupScreen extends ConsumerStatefulWidget {
  const ServerSetupScreen({super.key});

  @override
  ConsumerState<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends ConsumerState<ServerSetupScreen> {
  late final _controller = TextEditingController(
    text: ref.read(sessionControllerProvider.notifier).localDataServer() ?? '',
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final session = ref.read(sessionControllerProvider.notifier);
    String url;
    try {
      url = normalizeServerUrl(_controller.text);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    final previous = session.localDataServer();
    if (previous != null && previous != url) {
      final ok = await confirm(
        context,
        title: 'Switch server?',
        message: 'This device holds data from $previous. Connecting to a different server removes it '
            'from this device, including changes that were not synced yet.',
        action: 'Switch',
      );
      if (!ok) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.connect(url);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AppLogo()),
                  const SizedBox(height: 16),
                  Text('Welcome to Index', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'Connect to your server to get started. Enter its address below.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _controller,
                    enabled: !_busy,
                    autofocus: _controller.text.isEmpty,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _connect(),
                    decoration: InputDecoration(
                      labelText: 'Server address',
                      hintText: '192.168.1.10:8080 or index.example.com',
                      prefixIcon: const Icon(Icons.link),
                      errorText: _error,
                      errorMaxLines: 3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'IP addresses use http://, domains use https://. Type the scheme to override.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _connect,
                    child: _busy
                        ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Connect'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
