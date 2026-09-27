import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/amicup_motion.dart';
import '../widgets/animated_tab_selector.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../viewmodels/events_view_model.dart';
import 'create_event_view.dart';
import 'event_details_view.dart';

class EventsView extends StatelessWidget {
  const EventsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const _EventsFeed();
  }
}

class _EventsFeed extends StatefulWidget {
  const _EventsFeed();

  @override
  State<_EventsFeed> createState() => _EventsFeedState();
}

class _EventsFeedState extends State<_EventsFeed> with WidgetsBindingObserver {
  static const _categories = [
    'All',
    'Party',
    'Sports',
    'Networking',
    'Hangout',
  ];
  String _category = 'All';
  bool _showMyEvents = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<EventsViewModel>().fetchUpcomingEvents();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(
        context.read<EventsViewModel>().fetchUpcomingEvents(
          category: _category,
        ),
      );
    }
  }

  Future<void> _openCreateEvent(
    BuildContext context, {
    AppEvent? eventToEdit,
  }) async {
    final eventsVm = context.read<EventsViewModel>();
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: eventsVm,
          child: CreateEventView(eventToEdit: eventToEdit),
        ),
      ),
    );
    if (!context.mounted || saved != true) return;
    await context.read<EventsViewModel>().fetchUpcomingEvents(
      category: _category,
    );
  }

  Future<void> _confirmDelete(BuildContext context, AppEvent event) async {
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
    if (confirmed != true || !context.mounted) return;
    final deleted = await context.read<EventsViewModel>().deleteEvent(event.id);
    if (!context.mounted) return;
    if (!deleted) {
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
    final model = context.watch<EventsViewModel>();
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final displayedEvents = _showMyEvents
        ? model.events.where((event) => event.hostId == currentUserId).toList()
        : model.events;
    return Scaffold(
      backgroundColor: AppTheme.of(context).canvas,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.of(context).violet,
          onRefresh: () => model.fetchUpcomingEvents(category: _category),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Events',
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.of(context).ink,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Good company. Great plans.',
                              style: TextStyle(
                                color: AppTheme.of(context).muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Create event',
                        onPressed: () => _openCreateEvent(context),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: AnimatedTabSelector(
                    labels: const ['Explore', 'My events'],
                    icons: const [
                      Icons.explore_outlined,
                      Icons.event_note_outlined,
                    ],
                    selectedIndex: _showMyEvents ? 1 : 0,
                    onSelected: (index) =>
                        setState(() => _showMyEvents = index == 1),
                  ),
                ),
              ),
              if (!_showMyEvents)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 46,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      itemCount: _categories.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final category = _categories[index];
                        return ChoiceChip(
                          label: Text(category),
                          selected: category == _category,
                          selectedColor: AppTheme.of(context).violet,
                          labelStyle: TextStyle(
                            color: category == _category
                                ? AppTheme.of(context).onAccent
                                : AppTheme.of(context).ink,
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) {
                            setState(() => _category = category);
                            model.fetchUpcomingEvents(category: category);
                          },
                        );
                      },
                    ),
                  ),
                ),
              if (model.isLoading)
                SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.of(context).violetStrong,
                    ),
                  ),
                )
              else if (displayedEvents.isEmpty)
                SliverFillRemaining(
                  child: _EmptyEvents(
                    title: _showMyEvents
                        ? 'No events hosted yet'
                        : 'No upcoming events',
                    subtitle: _showMyEvents
                        ? 'Create an event to start bringing people together.'
                        : 'Start the plan and bring people together.',
                    onCreate: () => _openCreateEvent(context),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  sliver: SliverList.separated(
                    itemCount: displayedEvents.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => AnimatedSwitcher(
                      duration: AmicUpMotion.duration(
                        context,
                        AmicUpMotion.fast,
                      ),
                      switchInCurve: AmicUpMotion.curve,
                      child: _EventCard(
                        key: ValueKey(displayedEvents[index].id),
                        event: displayedEvents[index],
                        isManaging: _showMyEvents,
                        onEdit: () => _openCreateEvent(
                          context,
                          eventToEdit: displayedEvents[index],
                        ),
                        onDelete: () =>
                            _confirmDelete(context, displayedEvents[index]),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    super.key,
    required this.event,
    required this.isManaging,
    required this.onEdit,
    required this.onDelete,
  });
  final AppEvent event;
  final bool isManaging;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final model = context.read<EventsViewModel>();
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EventDetailsView(eventId: event.id)),
      ),
      child: Ink(
        decoration: BoxDecoration(
          color: AppTheme.of(context).surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppTheme.of(context).line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 21 / 9,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
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
                          size: 58,
                          color: Colors.white70,
                        ),
                      )
                    : Image.network(
                        event.coverImageUrl!,
                        fit: BoxFit.cover,
                        cacheWidth:
                            (MediaQuery.sizeOf(context).width *
                                    MediaQuery.devicePixelRatioOf(context))
                                .round()
                                .clamp(360, 1440),
                        errorBuilder: (_, _, _) => DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppTheme.of(context).surfaceMuted,
                          ),
                          child: Icon(Icons.image_not_supported_outlined),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.of(context).ink,
                          ),
                        ),
                      ),
                      if (isManaging) ...[
                        IconButton(
                          tooltip: 'Edit event',
                          onPressed: onEdit,
                          icon: Icon(
                            Icons.edit_outlined,
                            color: AppTheme.of(context).violetStrong,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Delete event',
                          onPressed: onDelete,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: Color(0xFFD33A4C),
                          ),
                        ),
                      ] else
                        _CategoryTag(category: event.category),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${DateFormat('EEE, MMM d • h:mm a').format(event.startTime)}${event.endTime == null ? '' : ' - ${DateFormat('h:mm a').format(event.endTime!)}'}',
                    style: TextStyle(color: AppTheme.of(context).muted),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 18,
                        color: AppTheme.of(context).muted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event.locationName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppTheme.of(context).muted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.of(context).surfaceMuted,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${event.attendeeCount} Going',
                          style: TextStyle(
                            color: AppTheme.of(context).violetStrong,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!isManaging) ...[
                        const Spacer(),
                        FilledButton(
                          onPressed: () => model.toggleAttendance(event.id),
                          style: FilledButton.styleFrom(
                            backgroundColor: event.isGoing
                                ? AppTheme.of(context).surfaceMuted
                                : AppTheme.of(context).violet,
                            foregroundColor: event.isGoing
                                ? AppTheme.of(context).violetStrong
                                : AppTheme.of(context).onAccent,
                          ),
                          child: Text(event.isGoing ? 'Going' : 'Join'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTag extends StatelessWidget {
  const _CategoryTag({required this.category});
  final String category;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: AppTheme.of(context).surfaceMuted,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(
      category,
      style: TextStyle(
        fontSize: 12,
        color: AppTheme.of(context).violetStrong,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _EmptyEvents extends StatelessWidget {
  const _EmptyEvents({
    required this.title,
    required this.subtitle,
    required this.onCreate,
  });
  final String title;
  final String subtitle;
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.event_available_rounded,
            size: 58,
            color: AppTheme.of(context).muted,
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.of(context).muted),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create Event'),
          ),
        ],
      ),
    ),
  );
}
