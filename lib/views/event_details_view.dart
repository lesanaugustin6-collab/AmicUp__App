import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../viewmodels/events_view_model.dart';
import 'create_event_view.dart';
import '../widgets/share_event_sheet.dart';

enum _HostEventAction { edit, delete }

class EventDetailsView extends StatefulWidget {
  const EventDetailsView({super.key, required this.eventId});

  final String eventId;

  @override
  State<EventDetailsView> createState() => _EventDetailsViewState();
}

class _EventDetailsViewState extends State<EventDetailsView> {
  late Future<AppEvent?> _eventFuture;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _eventFuture = context.read<EventsViewModel>().fetchEvent(widget.eventId);
  }

  Future<void> _refresh() async {
    setState(() {
      _eventFuture = context.read<EventsViewModel>().fetchEvent(widget.eventId);
    });
    await _eventFuture;
  }

  Future<void> _editEvent(AppEvent event) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: context.read<EventsViewModel>(),
          child: CreateEventView(eventToEdit: event),
        ),
      ),
    );
    if (saved == true && mounted) await _refresh();
  }

  Future<void> _deleteEvent(AppEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete event?'),
        content: Text(
          '"${event.title}" and its attendee list will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final deleted = await context.read<EventsViewModel>().deleteEvent(event.id);
    if (!mounted) return;
    if (deleted) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.read<EventsViewModel>().errorMessage ??
                'Unable to delete event.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.of(context).canvas,
      body: FutureBuilder<AppEvent?>(
        future: _eventFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: CircularProgressIndicator(
                color: AppTheme.of(context).violetStrong,
              ),
            );
          }
          final event = snapshot.data;
          if (event == null) {
            return Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Event unavailable'),
              ),
            );
          }
          return _EventDetailsContent(
            event: event,
            expanded: _expanded,
            onExpand: () => setState(() => _expanded = !_expanded),
            onRefresh: _refresh,
            onEdit: () => _editEvent(event),
            onDelete: () => _deleteEvent(event),
          );
        },
      ),
    );
  }
}

class _EventDetailsContent extends StatelessWidget {
  const _EventDetailsContent({
    required this.event,
    required this.expanded,
    required this.onExpand,
    required this.onRefresh,
    required this.onEdit,
    required this.onDelete,
  });

  final AppEvent event;
  final bool expanded;
  final VoidCallback onExpand;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<EventsViewModel>();
    final isHost =
        event.hostId == Supabase.instance.client.auth.currentUser?.id;
    final timeFormat = DateFormat('h:mm a');
    final timeRange =
        '${timeFormat.format(event.startTime)}${event.endTime == null ? '' : ' - ${timeFormat.format(event.endTime!)}'}';
    final coverHeight = MediaQuery.sizeOf(context).width * 9 / 16;

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: coverHeight,
              pinned: true,
              backgroundColor: AppTheme.darkSurface,
              foregroundColor: Colors.white,
              leading: IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
              actions: [
                IconButton(
                  tooltip: 'Share event',
                  icon: const Icon(Icons.send_outlined),
                  onPressed: () => showShareEventSheet(
                    context,
                    eventId: event.id,
                    title: event.title,
                    startsAt: event.startTime,
                    location: event.locationName,
                  ),
                ),
                if (isHost)
                  PopupMenuButton<_HostEventAction>(
                    tooltip: 'Manage event',
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (action) {
                      if (action == _HostEventAction.edit) {
                        onEdit();
                      } else {
                        onDelete();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _HostEventAction.edit,
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit event'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _HostEventAction.delete,
                        child: ListTile(
                          leading: Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.red,
                          ),
                          title: Text('Delete event'),
                        ),
                      ),
                    ],
                  ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: event.coverImageUrl == null
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppTheme.of(context).coverStart,
                                    AppTheme.of(context).coverEnd,
                                  ],
                                ),
                              ),
                              child: Icon(
                                Icons.celebration_rounded,
                                color: Colors.white70,
                                size: 82,
                              ),
                            )
                          : Image.network(
                              event.coverImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => DecoratedBox(
                                decoration: BoxDecoration(
                                  color: AppTheme.of(context).violet,
                                ),
                              ),
                            ),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xAA1C102E)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 118),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        _Pill(text: event.category),
                        _Pill(text: '${event.attendeeCount} going', pale: true),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      event.title,
                      style: TextStyle(
                        fontSize: 29,
                        height: 1.12,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.of(context).ink,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _InfoRow(
                      icon: Icons.calendar_month_outlined,
                      title: DateFormat('EEEE, MMMM d').format(event.startTime),
                      detail: timeRange,
                    ),
                    const SizedBox(height: 17),
                    _InfoRow(
                      icon: Icons.location_on_outlined,
                      title: event.locationName,
                      detail: 'Location details shared by the host',
                    ),
                    const SizedBox(height: 25),
                    const Text(
                      'About this event',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      event.description.isEmpty
                          ? 'The host has not added a description yet.'
                          : event.description,
                      maxLines: expanded ? null : 4,
                      overflow: expanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: AppTheme.of(context).muted,
                      ),
                    ),
                    if (event.description.length > 150)
                      TextButton(
                        onPressed: onExpand,
                        child: Text(expanded ? 'Show less' : 'Read more'),
                      ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.of(context).surface,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(color: Color(0x0D0E071F), blurRadius: 12),
                        ],
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppTheme.of(context).surfaceMuted,
                            child: Icon(
                              Icons.person_rounded,
                              color: AppTheme.of(context).violetStrong,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isHost
                                      ? 'Hosted by you'
                                      : 'Hosted by an AmicUp member',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'Event host',
                                  style: TextStyle(
                                    color: AppTheme.of(context).muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.verified_rounded,
                            color: AppTheme.of(context).violetStrong,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 18,
          child: SafeArea(
            top: false,
            child: FilledButton.icon(
              onPressed: () async {
                final success = await viewModel.toggleAttendance(event.id);
                if (success && context.mounted) await onRefresh();
              },
              style: FilledButton.styleFrom(
                backgroundColor: event.isGoing
                    ? AppTheme.of(context).surfaceMuted
                    : AppTheme.of(context).violet,
                foregroundColor: event.isGoing
                    ? AppTheme.of(context).violetStrong
                    : AppTheme.of(context).onAccent,
                padding: const EdgeInsets.symmetric(vertical: 17),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              icon: Icon(
                event.isGoing
                    ? Icons.check_circle_rounded
                    : Icons.add_circle_outline_rounded,
              ),
              label: Text(
                event.isGoing ? 'Leave event' : 'Join',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.of(context).surfaceMuted,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(icon, color: AppTheme.of(context).violetStrong),
      ),
      const SizedBox(width: 13),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(detail, style: TextStyle(color: AppTheme.of(context).muted)),
          ],
        ),
      ),
    ],
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.pale = false});
  final String text;
  final bool pale;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: pale
          ? AppTheme.of(context).surfaceMuted
          : AppTheme.of(context).violet,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: pale ? AppTheme.of(context).ink : AppTheme.of(context).onAccent,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
