import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String inboxPreview(String? content) {
  if (content == null || content.isEmpty) return 'Start a conversation';
  var text = content;
  var forwarded = false;
  if (text.startsWith('Forwarded\n')) {
    forwarded = true;
    text = text.substring('Forwarded\n'.length);
  }
  if (text.startsWith('↩ ') && text.contains('\n')) {
    text = text.substring(text.indexOf('\n') + 1);
  }
  if (text.startsWith('[IMAGE]:')) text = 'Photo';
  if (text.startsWith('[ALBUM]:')) text = 'Photos';
  return '${forwarded ? 'Forwarded · ' : ''}${text.replaceAll('\n', ' ')}';
}

String inboxTime(String? value) {
  final date = DateTime.tryParse(value ?? '')?.toLocal();
  if (date == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (!date.isBefore(today)) return DateFormat.Hm().format(date);
  if (!date.isBefore(today.subtract(const Duration(days: 1)))) {
    return 'Yesterday';
  }
  return DateFormat.MMMd().format(date);
}

class InboxAvatar extends StatelessWidget {
  const InboxAvatar({super.key, required this.name, this.url});
  final String name;
  final String? url;
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 26,
    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
    child: ClipOval(
      child: url != null && url!.isNotEmpty
          ? Image.network(
              url!,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              cacheWidth: (52 * MediaQuery.devicePixelRatioOf(context))
                  .round()
                  .clamp(52, 256),
              errorBuilder: (_, _, _) => _fallback(context),
            )
          : _fallback(context),
    ),
  );
  Widget _fallback(BuildContext context) => Text(
    name.isEmpty ? '?' : name.characters.first.toUpperCase(),
    style: TextStyle(
      color: Theme.of(context).colorScheme.onPrimaryContainer,
      fontWeight: FontWeight.w700,
    ),
  );
}

class ActivityInboxTile extends StatelessWidget {
  const ActivityInboxTile({super.key, required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      key: const ValueKey('pinned-activity'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: colors.primaryContainer,
        child: Icon(
          Icons.notifications_none_rounded,
          color: colors.onPrimaryContainer,
          size: 28,
        ),
      ),
      title: const Text(
        'Activity',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: const Text('Connection activity'),
      trailing: Icon(
        Icons.push_pin_outlined,
        color: colors.onSurfaceVariant,
        size: 20,
      ),
      onTap: onTap,
    );
  }
}

class DirectInboxTile extends StatelessWidget {
  const DirectInboxTile({
    super.key,
    required this.conversation,
    required this.onTap,
    required this.onReview,
  });
  final Map<String, dynamic> conversation;
  final VoidCallback onTap;
  final VoidCallback onReview;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final first = conversation['first_name']?.toString().trim() ?? '';
    final name = first.isNotEmpty
        ? first
        : conversation['username']?.toString() ?? 'Member';
    final unread = (conversation['unread_count'] as num?)?.toInt() ?? 0;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
      leading: InboxAvatar(
        name: name,
        url: conversation['avatar_url']?.toString(),
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      subtitle: Text(
        inboxPreview(conversation['last_message']?.toString()),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: unread > 0 ? colors.onSurface : colors.onSurfaceVariant,
          fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                inboxTime(
                  (conversation['last_message_at'] ??
                          conversation['created_at'])
                      ?.toString(),
                ),
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
              if (unread > 0) ...[
                const SizedBox(height: 4),
                Semantics(
                  label: '$unread unread messages',
                  excludeSemantics: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.onPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          IconButton(
            tooltip: 'Rate $name',
            onPressed: onReview,
            icon: const Icon(Icons.star_outline_rounded),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
