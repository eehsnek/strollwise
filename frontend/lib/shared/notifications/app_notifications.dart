import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/colors.dart';

/// Root [ScaffoldMessenger] — attach in [MaterialApp.router] so toasts work
/// across tab navigation (Explore, Add Tag, Profile, etc.).
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

enum AppNotificationKind { info, success, warning, error }

class AppNotification {
  const AppNotification({
    required this.id,
    required this.message,
    required this.createdAt,
    this.title,
    this.kind = AppNotificationKind.info,
    this.read = false,
  });

  final String id;
  final String? title;
  final String message;
  final DateTime createdAt;
  final AppNotificationKind kind;
  final bool read;

  AppNotification markRead() => AppNotification(
        id: id,
        title: title,
        message: message,
        createdAt: createdAt,
        kind: kind,
        read: true,
      );
}

class AppNotificationsNotifier extends StateNotifier<List<AppNotification>> {
  AppNotificationsNotifier() : super(const []);

  static const _maxItems = 40;
  static final _rng = math.Random();

  void push({
    required String message,
    String? title,
    AppNotificationKind kind = AppNotificationKind.info,
    bool showToast = true,
  }) {
    final item = AppNotification(
      id: '${DateTime.now().microsecondsSinceEpoch}_${_rng.nextInt(1 << 32)}',
      title: title,
      message: message,
      createdAt: DateTime.now(),
      kind: kind,
    );
    state = [item, ...state].take(_maxItems).toList();
    if (showToast) {
      AppNotificationToast.show(item);
    }
  }

  void markRead(String id) {
    state = [
      for (final n in state)
        if (n.id == id) n.markRead() else n,
    ];
  }

  void markAllRead() {
    state = [for (final n in state) n.markRead()];
  }

  void clearAll() {
    state = const [];
  }
}

final appNotificationsProvider =
    StateNotifierProvider<AppNotificationsNotifier, List<AppNotification>>(
  (ref) => AppNotificationsNotifier(),
);

final unreadNotificationCountProvider = Provider<int>((ref) {
  return ref
      .watch(appNotificationsProvider)
      .where((n) => !n.read)
      .length;
});

/// Push an inbox item and optionally show a floating toast.
void pushAppNotification(
  WidgetRef ref, {
  required String message,
  String? title,
  AppNotificationKind kind = AppNotificationKind.info,
  bool showToast = true,
}) {
  ref.read(appNotificationsProvider.notifier).push(
        message: message,
        title: title,
        kind: kind,
        showToast: showToast,
      );
}

class AppNotificationToast {
  static void show(AppNotification notification) {
    final messenger = rootScaffoldMessengerKey.currentState;
    if (messenger == null) return;

    final color = switch (notification.kind) {
      AppNotificationKind.success => AppColors.accent,
      AppNotificationKind.warning => const Color(0xFFF59E0B),
      AppNotificationKind.error => AppColors.alert,
      AppNotificationKind.info => const Color(0xFF0F766E),
    };

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
          duration: const Duration(seconds: 4),
          backgroundColor: const Color(0xFF0F172A),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_iconFor(notification.kind), color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (notification.title != null &&
                        notification.title!.trim().isNotEmpty) ...[
                      Text(
                        notification.title!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      notification.message,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Color(0xFFE2E8F0),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }

  static IconData _iconFor(AppNotificationKind kind) {
    return switch (kind) {
      AppNotificationKind.success => Icons.check_circle_outline_rounded,
      AppNotificationKind.warning => Icons.info_outline_rounded,
      AppNotificationKind.error => Icons.error_outline_rounded,
      AppNotificationKind.info => Icons.notifications_active_outlined,
    };
  }
}
