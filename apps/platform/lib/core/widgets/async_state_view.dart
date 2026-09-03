import 'package:flutter/material.dart';

import '../errors/api_failure.dart';
import '../theme/platform_theme.dart';

/// Standard loading / empty / error(+retry) wrapper used by every module
/// screen, per the "all screens need loading, empty, error, retry" rule.
class AsyncStateView<T> extends StatelessWidget {
  const AsyncStateView({
    super.key,
    required this.future,
    required this.builder,
    this.isEmpty,
    this.emptyMessage = 'Nothing to show yet.',
  });

  final Future<T> Function() future;
  final Widget Function(BuildContext context, T data) builder;
  final bool Function(T data)? isEmpty;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return _RetryableFuture<T>(
      future: future,
      builder: (context, data) {
        if (isEmpty != null && isEmpty!(data)) {
          return EmptyStateView(message: emptyMessage);
        }
        return builder(context, data);
      },
    );
  }
}

class _RetryableFuture<T> extends StatefulWidget {
  const _RetryableFuture({required this.future, required this.builder});

  final Future<T> Function() future;
  final Widget Function(BuildContext context, T data) builder;

  @override
  State<_RetryableFuture<T>> createState() => _RetryableFutureState<T>();
}

class _RetryableFutureState<T> extends State<_RetryableFuture<T>> {
  late Future<T> _pending;

  @override
  void initState() {
    super.initState();
    _pending = widget.future();
  }

  void _retry() {
    setState(() => _pending = widget.future());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _pending,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError) {
          return ErrorStateView(error: snapshot.error, onRetry: _retry);
        }
        return widget.builder(context, snapshot.data as T);
      },
    );
  }
}

class ErrorStateView extends StatelessWidget {
  const ErrorStateView({super.key, required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  String get _message {
    final err = error;
    if (err is ApiFailure) return err.friendlyMessage;
    return 'Something went wrong loading this screen.';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: PlatformColors.danger,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              _message,
              textAlign: TextAlign.center,
              style: PlatformTypography.secondary,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: PlatformColors.muted, size: 40),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: PlatformTypography.secondary,
            ),
          ],
        ),
      ),
    );
  }
}
