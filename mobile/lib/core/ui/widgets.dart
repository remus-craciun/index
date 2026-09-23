import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_exception.dart';

void showMessage(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}

/// Messenger of the root MaterialApp, for errors raised outside any screen.
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

String errorText(Object error) {
  if (error is FormatException) return error.message;
  final text = error.toString();
  if (text.contains('SqliteException')) {
    // Code and database schema out of step, e.g. after a hot reload across
    // a schema change: the migration only runs when the app starts.
    if (text.contains('no column') || text.contains('no such column') || text.contains('no such table')) {
      return 'The local database needs an update. Fully close and reopen the app.';
    }
    return 'Could not save on this device ($text)';
  }
  return ApiException.from(error).message;
}

/// Runs [action], showing any failure as a message instead of failing
/// silently.
Future<void> guarded(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) showMessage(context, errorText(e));
  }
}

/// Last-resort handler for errors nothing else caught.
void reportUnhandledError(Object error) {
  rootMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(errorText(error))));
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.color});

  final String title;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: color ?? theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

/// Renders an [AsyncValue] with default loading and error states.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data});

  final AsyncValue<T> value;
  final Widget Function(T data) data;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(errorText(e), textAlign: TextAlign.center)),
      ),
    );
  }
}

/// Single-line capture field that submits on enter and keeps focus for
/// rapid entry.
class QuickAddField extends StatefulWidget {
  const QuickAddField({super.key, required this.hint, required this.onSubmit});

  final String hint;
  final Future<void> Function(String title) onSubmit;

  @override
  State<QuickAddField> createState() => _QuickAddFieldState();
}

class _QuickAddFieldState extends State<QuickAddField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await widget.onSubmit(text);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        textInputAction: TextInputAction.done,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(Icons.add),
          filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          suffixIcon: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _controller.text.trim().isEmpty
                ? const SizedBox.shrink()
                : IconButton(icon: const Icon(Icons.arrow_upward), tooltip: 'Add', onPressed: _submit),
          ),
        ),
      ),
    );
  }
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String label = 'Title',
  String confirm = 'Save',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(title: title, initial: initial, label: label, confirm: confirm),
  );
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({required this.title, required this.initial, required this.label, required this.confirm});

  final String title;
  final String initial;
  final String label;
  final String confirm;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _controller.text.trim();
    Navigator.pop(context, v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.confirm)),
      ],
    );
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Delete',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: destructive ? FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError) : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
