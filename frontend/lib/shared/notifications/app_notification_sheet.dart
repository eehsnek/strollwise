import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/colors.dart';
import 'app_notifications.dart';

void showAppNotificationSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (sheetContext) => const _NotificationSheet(),
  );
}

class _NotificationSheet extends ConsumerWidget {
  const _NotificationSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(appNotificationsProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: items.isEmpty ? 0.42 : 0.62,
      minChildSize: 0.38,
      maxChildSize: 0.88,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Material(
            color: Colors.white,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Notifications',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryText,
                          ),
                        ),
                      ),
                      if (items.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            ref
                                .read(appNotificationsProvider.notifier)
                                .markAllRead();
                          },
                          child: const Text('Mark all read'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? const _EmptyNotifications()
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: items.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return _NotificationTile(
                              item: item,
                              onTap: () {
                                ref
                                    .read(appNotificationsProvider.notifier)
                                    .markRead(item.id);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 48,
              color: AppColors.mutedText.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
            const Text(
              'No messages yet',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppColors.primaryText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tag updates, visit saves, and alerts will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.mutedText.withValues(alpha: 0.9),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = switch (item.kind) {
      AppNotificationKind.success => AppColors.accent,
      AppNotificationKind.warning => const Color(0xFFF59E0B),
      AppNotificationKind.error => AppColors.alert,
      AppNotificationKind.info => const Color(0xFF0F766E),
    };

    return Material(
      color: item.read
          ? const Color(0xFFF8FAFC)
          : const Color(0xFFECFDF5),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: item.read
                  ? AppColors.border
                  : accent.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _iconFor(item.kind),
                size: 20,
                color: accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.title != null && item.title!.isNotEmpty)
                      Text(
                        item.title!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: AppColors.primaryText,
                        ),
                      ),
                    Text(
                      item.message,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                        color: Color(0xFF475569),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _timeAgo(item.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.mutedText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (!item.read)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
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

  static String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
