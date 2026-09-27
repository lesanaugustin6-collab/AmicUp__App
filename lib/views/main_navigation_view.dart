import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../widgets/amicup_logo_mark.dart';
import '../theme/app_theme.dart';
import '../theme/amicup_motion.dart';
import 'discover_view.dart';
import 'events_view.dart';
import 'messages_hub_view.dart';
import 'profile_view.dart';

class MainNavigationView extends StatefulWidget {
  const MainNavigationView({super.key, this.initialIndex = 2});

  final int initialIndex;

  @override
  State<MainNavigationView> createState() => _MainNavigationViewState();
}

class _MainNavigationViewState extends State<MainNavigationView>
    with WidgetsBindingObserver {
  late int _currentIndex;
  final List<int> _tabHistory = [0];
  final Set<int> _visitedTabs = {};
  RealtimeChannel? _messagesChannel;
  bool _restartingMessagesChannel = false;

  final List<Widget> _screens = const [
    _MapAvailabilityView(),
    EventsView(),
    DiscoverView(),
    MessagesHubView(),
    ProfileView(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentIndex = widget.initialIndex.clamp(0, _screens.length - 1);
    _tabHistory[0] = _currentIndex;
    _visitedTabs.add(_currentIndex);
    unawaited(NotificationService().initNotifications());
    _subscribeToIncomingMessages();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final messagesChannel = _messagesChannel;
    if (messagesChannel != null) {
      unawaited(Supabase.instance.client.removeChannel(messagesChannel));
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshSession());
      unawaited(_restartMessagesSubscription());
    }
  }

  Future<void> _refreshSession() async {
    if (Supabase.instance.client.auth.currentSession == null) return;
    try {
      await Supabase.instance.client.auth.refreshSession();
    } catch (error) {
      // Offline resume should not block the UI; Supabase can retry later.
      debugPrint('Session refresh on resume failed: $error');
    }
  }

  Future<void> _restartMessagesSubscription() async {
    if (_restartingMessagesChannel) return;
    _restartingMessagesChannel = true;
    final previous = _messagesChannel;
    _messagesChannel = null;
    try {
      if (previous != null) {
        try {
          await Supabase.instance.client
              .removeChannel(previous)
              .timeout(const Duration(seconds: 3));
        } catch (error) {
          debugPrint('Previous message channel cleanup skipped: $error');
        }
      }
      if (mounted &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _subscribeToIncomingMessages();
      }
    } finally {
      _restartingMessagesChannel = false;
    }
  }

  void _subscribeToIncomingMessages() {
    final currentUserId = SupabaseService().currentUserId;
    if (currentUserId == null) return;

    final channel = Supabase.instance.client
        .channel('public:messages:incoming:$currentUserId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            unawaited(_handleIncomingMessage(payload));
          },
        )
        .subscribe();

    _messagesChannel = channel;
  }

  Future<void> _handleIncomingMessage(PostgresChangePayload payload) async {
    final currentUserId = SupabaseService().currentUserId;
    final senderId = payload.newRecord['sender_id']?.toString();
    final messageContent =
        payload.newRecord['content']?.toString().trim() ?? '';

    if (currentUserId == null ||
        senderId == null ||
        senderId == currentUserId) {
      return;
    }

    if (messageContent.isEmpty) return;

    var title = 'New Message';
    final senderProfile = await SupabaseService().getProfile(senderId);
    final firstName = senderProfile?['first_name']?.toString().trim();
    if (firstName != null && firstName.isNotEmpty) {
      title = firstName;
    }

    await NotificationService().showNotification(
      title: title,
      body: messageContent,
      payload: {
        'type': 'direct',
        'match_id': payload.newRecord['match_id'],
        'message_id': payload.newRecord['id'],
        'sender_id': senderId,
        'sender_name': title,
      },
    );
  }

  void _syncNavigationTheme({required bool isDiscoverTab}) {
    SystemChrome.setSystemUIOverlayStyle(
      isDiscoverTab || Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    );
  }

  void _onTabSelected(int index) {
    if (!mounted || _currentIndex == index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex = index;
      _visitedTabs.add(index);
      if (_tabHistory.isEmpty || _tabHistory.last != index) {
        _tabHistory.add(index);
      }
    });
  }

  Future<void> _handleBackNavigation() async {
    if (!mounted) return;

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    if (_tabHistory.length > 1) {
      setState(() {
        _tabHistory.removeLast();
        _currentIndex = _tabHistory.last;
        _visitedTabs.add(_currentIndex);
      });
      return;
    }

    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDiscoverTab = _currentIndex == 2;
    _syncNavigationTheme(isDiscoverTab: isDiscoverTab);

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_handleBackNavigation());
      },
      child: Scaffold(
        extendBody: true,
        body: AmicUpTabStack(
          index: _currentIndex,
          children: [
            for (var i = 0; i < _screens.length; i++)
              _visitedTabs.contains(i) ? _screens[i] : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: AmicUpNavigationBar(
          currentIndex: _currentIndex,
          isDark: _currentIndex == 2,
          onTap: _onTabSelected,
        ),
      ),
    );
  }
}

class AmicUpNavigationBar extends StatelessWidget {
  const AmicUpNavigationBar({
    super.key,
    required this.currentIndex,
    required this.isDark,
    required this.onTap,
  });

  final int currentIndex;
  final bool isDark;
  final ValueChanged<int> onTap;

  static const _items = [
    _NavigationItem('Maps', Icons.map_outlined, Icons.map),
    _NavigationItem(
      'Events',
      Icons.calendar_today_outlined,
      Icons.calendar_today,
    ),
    _NavigationItem('Discover', Icons.explore_outlined, Icons.explore),
    _NavigationItem('Chats', Icons.chat_bubble_outline, Icons.chat_bubble),
    _NavigationItem('Profile', Icons.person_outline, Icons.person),
  ];

  @override
  Widget build(BuildContext context) {
    final duration = AmicUpMotion.duration(context, AmicUpMotion.standard);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 5),
        child: AmicUpGlassSurface(
          radius: 28,
          color: (isDark ? AppTheme.darkSurface : AppTheme.of(context).surface)
              .withValues(alpha: 0.88),
          borderColor: AppTheme.of(context).line.withValues(alpha: 0.65),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  AnimatedPositionedDirectional(
                    duration: duration,
                    curve: AmicUpMotion.curve,
                    start: constraints.maxWidth / _items.length * currentIndex,
                    top: 5,
                    width: constraints.maxWidth / _items.length,
                    height: 40,
                    child: IgnorePointer(
                      child: Center(
                        child: AnimatedContainer(
                          duration: duration,
                          width: 56,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.of(
                              context,
                            ).violet.withValues(alpha: 0.94),
                            border: Border.all(
                              color: AppTheme.of(
                                context,
                              ).onAccent.withValues(alpha: 0.16),
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: List.generate(_items.length, (index) {
                      final item = _items[index];
                      final selected = currentIndex == index;
                      return Expanded(
                        child: Semantics(
                          button: true,
                          selected: selected,
                          label: item.label,
                          child: InkWell(
                            onTap: () => onTap(index),
                            borderRadius: BorderRadius.circular(22),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: SizedBox(
                                height: 46,
                                child: Center(
                                  child: index == 2
                                      ? const AmicUpLogoMark(
                                          size: 36,
                                          semanticLabel: 'Discover',
                                        )
                                      : Icon(
                                          selected
                                              ? item.activeIcon
                                              : item.inactiveIcon,
                                          size: 24,
                                          color: selected
                                              ? AppTheme.of(context).onAccent
                                              : (isDark
                                                    ? Colors.white60
                                                    : AppTheme.of(
                                                        context,
                                                      ).muted),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
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

class _NavigationItem {
  const _NavigationItem(this.label, this.inactiveIcon, this.activeIcon);
  final String label;
  final IconData inactiveIcon;
  final IconData activeIcon;
}

class _MapAvailabilityView extends StatelessWidget {
  const _MapAvailabilityView();

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _MapPreviewPainter(
                  background: colors.canvas,
                  road: colors.surface,
                  park: Color.lerp(colors.canvas, colors.violet, dark ? 0.13 : 0.09)!,
                  block: colors.surfaceMuted,
                ),
              ),
            ),
            const Align(
              alignment: Alignment(-0.58, -0.48),
              child: _MapPreviewPin(icon: Icons.sports_basketball),
            ),
            const Align(
              alignment: Alignment(0.52, -0.19),
              child: _MapPreviewPin(icon: Icons.local_cafe_outlined),
            ),
            const Align(
              alignment: Alignment(-0.22, 0.19),
              child: _MapPreviewPin(icon: Icons.directions_walk),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
              child: Text('Maps', style: Theme.of(context).textTheme.headlineLarge),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 100),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: colors.line),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: dark ? 0.24 : 0.10),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: colors.primarySoft,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'COMING SOON',
                          style: TextStyle(
                            color: colors.violetStrong,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Find your people nearby',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'A new way to explore people and activities around you is on its way.',
                        style: TextStyle(color: colors.muted, fontSize: 14, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapPreviewPin extends StatelessWidget {
  const _MapPreviewPin({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.of(context);
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: colors.violet,
        shape: BoxShape.circle,
        border: Border.all(color: colors.surface, width: 4),
        boxShadow: [
          BoxShadow(
            color: colors.violet.withValues(alpha: 0.25),
            blurRadius: 18,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Icon(icon, color: colors.onAccent, size: 25),
    );
  }
}

class _MapPreviewPainter extends CustomPainter {
  const _MapPreviewPainter({
    required this.background,
    required this.road,
    required this.park,
    required this.block,
  });

  final Color background;
  final Color road;
  final Color park;
  final Color block;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(background, BlendMode.src);
    final parkPaint = Paint()..color = park;
    final blockPaint = Paint()..color = block;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-35, size.height * .18, size.width * .42, size.height * .30),
        const Radius.circular(44),
      ),
      parkPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * .63, size.height * .36, size.width * .45, size.height * .28),
        const Radius.circular(42),
      ),
      parkPaint,
    );
    for (final rect in [
      Rect.fromLTWH(size.width * .47, size.height * .16, 52, 94),
      Rect.fromLTWH(size.width * .69, size.height * .12, 68, 85),
      Rect.fromLTWH(size.width * .08, size.height * .55, 86, 70),
      Rect.fromLTWH(size.width * .42, size.height * .48, 76, 55),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(14)),
        blockPaint,
      );
    }
    final roadPaint = Paint()
      ..color = road
      ..strokeWidth = 19
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final horizontal = Path()
      ..moveTo(-20, size.height * .32)
      ..cubicTo(size.width * .33, size.height * .27, size.width * .65, size.height * .40, size.width + 20, size.height * .31);
    final diagonal = Path()
      ..moveTo(size.width * .12, -20)
      ..cubicTo(size.width * .38, size.height * .24, size.width * .23, size.height * .49, size.width * .76, size.height + 20);
    final lower = Path()
      ..moveTo(-20, size.height * .70)
      ..quadraticBezierTo(size.width * .48, size.height * .53, size.width + 20, size.height * .73);
    canvas.drawPath(horizontal, roadPaint);
    canvas.drawPath(diagonal, roadPaint);
    canvas.drawPath(lower, roadPaint);
  }

  @override
  bool shouldRepaint(covariant _MapPreviewPainter oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.road != road ||
      oldDelegate.park != park ||
      oldDelegate.block != block;
}
