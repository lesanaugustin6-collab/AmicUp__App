import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/profile_field_codec.dart';
import 'profile_view.dart';
import 'profile_search_view.dart';
import '../services/supabase_service.dart';

class DiscoverView extends StatefulWidget {
  const DiscoverView({super.key, this.loadProfiles, this.onInteraction});

  final Future<List<Map<String, dynamic>>> Function()? loadProfiles;
  final Future<void> Function(String id, bool isLike)? onInteraction;

  @override
  State<DiscoverView> createState() => _DiscoverViewState();
}

class _DiscoverViewState extends State<DiscoverView>
    with WidgetsBindingObserver {
  SupabaseClient get _supabase => Supabase.instance.client;
  CardSwiperController _swipeController = CardSwiperController();
  Key _swiperKey = UniqueKey();
  Timer? _resumeRefreshTimer;

  bool _loading = true;
  bool _isSubmitting = false;
  bool _isFeedEmpty = false;
  String? _feedError;
  int _fetchVersion = 0;
  int _remainingCards = 0;
  final Set<String> _preloadedPhotos = {};
  List<Map<String, dynamic>> _profiles = const [];
  Map<String, dynamic>? _currentUserProfile;

  double? _dragStartX;
  final ValueNotifier<_SwipeFeedback> _swipeFeedback = ValueNotifier(
    const _SwipeFeedback(),
  );

  final TextEditingController _reportReasonController = TextEditingController();
  String? _reportSelectedReason;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_fetchDiscoverProfiles());
    SupabaseService.unmatchChanges.addListener(_onUnmatched);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SupabaseService.unmatchChanges.removeListener(_onUnmatched);
    _resumeRefreshTimer?.cancel();
    _swipeFeedback.dispose();
    _reportReasonController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _resumeRefreshTimer?.cancel();
    _resumeRefreshTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) unawaited(_handleFeedRefresh());
    });
  }

  String _profileId(Map<String, dynamic> profile) => _extractProfileId(profile);

  void _onUnmatched() => unawaited(_handleFeedRefresh());

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final SchedulerPhase phase = WidgetsBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else {
      setState(fn);
    }
  }

  Future<void> recordFeedInteraction({
    required String targetUserId,
    required bool isLike,
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null || targetUserId.isEmpty) return;

    final String action = isLike ? 'like' : 'pass';

    await Future.wait([
      _supabase
          .from('interactions')
          .insert({
            'user_id': currentUserId,
            'target_user_id': targetUserId,
            'action': action,
          })
          .catchError((e) {
            debugPrint('Error inserting into interactions table from feed: $e');
          }),
      _supabase
          .from('likes')
          .insert({
            'liker_id': currentUserId,
            'liked_id': targetUserId,
            'is_like': isLike,
            'action': action,
          })
          .catchError((e) {
            debugPrint('Error inserting into likes table from feed: $e');
          }),
    ]);
  }

  Future<void> _recordInteraction(
    Map<String, dynamic> profile,
    bool isLike,
  ) async {
    final targetProfileId = _profileId(profile);
    if (widget.onInteraction != null) {
      await widget.onInteraction!(targetProfileId, isLike);
      return;
    }

    if (_isSubmitting) return;
    _isSubmitting = true;

    try {
      await recordFeedInteraction(
        targetUserId: targetProfileId,
        isLike: isLike,
      );
    } finally {
      _safeSetState(() => _isSubmitting = false);
    }
  }

  String _profileDisplayName(Map<String, dynamic> profile) {
    final String firstName = (profile['first_name'] ?? '').toString().trim();
    final String lastName = (profile['last_name'] ?? '').toString().trim();
    final String username = (profile['username'] ?? '').toString().trim();
    final String displayName = [
      firstName,
      lastName,
    ].where((value) => value.isNotEmpty).join(' ').trim();
    return displayName.isNotEmpty
        ? displayName
        : (username.isNotEmpty ? username : 'this profile');
  }

  static const List<String> _reportReasons = [
    'Fake Profile',
    'Inappropriate Photos',
    'Harassment',
    'Other',
  ];

  void _closeReportModal(BuildContext modalContext) {
    if (Navigator.of(modalContext).canPop()) {
      Navigator.of(modalContext).pop();
    }
  }

  Future<void> _submitReport(
    BuildContext modalContext,
    String targetUserId,
    String reason,
  ) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null || targetUserId.isEmpty) return;

    try {
      await _supabase.from('reports').insert({
        'reporter_id': currentUserId,
        'reported_user_id': targetUserId,
        'reason': reason.isEmpty ? 'Inappropriate content' : reason,
      });

      if (modalContext.mounted) {
        _closeReportModal(modalContext);
      }

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Report submitted. Thank you for keeping AmicUp safe.',
              ),
            ),
          );
      }
    } catch (e) {
      debugPrint('Error submitting report: $e');

      if (modalContext.mounted) {
        ScaffoldMessenger.of(modalContext)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Failed to submit report. Please try again.'),
            ),
          );
      }
    }
  }

  Future<void> _reportProfile(Map<String, dynamic> profile) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    final targetProfileId = _profileId(profile);

    if (currentUserId == null ||
        currentUserId.isEmpty ||
        targetProfileId.isEmpty) {
      return;
    }

    _reportReasonController.clear();
    _reportSelectedReason = null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Report Profile',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _reportReasons.map((reason) {
                      final bool selected = _reportSelectedReason == reason;
                      return ChoiceChip(
                        label: Text(reason),
                        selected: selected,
                        selectedColor: AppTheme.of(context).violet,
                        labelStyle: TextStyle(
                          color: selected
                              ? AppTheme.of(context).onAccent
                              : null,
                        ),
                        onSelected: (_) {
                          setSheetState(() => _reportSelectedReason = reason);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _reportReasonController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Add details (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.of(context).violet,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () {
                            final details = _reportReasonController.text.trim();
                            final reason = [
                              ?_reportSelectedReason,
                              if (details.isNotEmpty) details,
                            ].join(': ');
                            unawaited(
                              _submitReport(
                                sheetContext,
                                targetProfileId,
                                reason,
                              ),
                            );
                          },
                          child: const Text('Submit Report'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () => _closeReportModal(sheetContext),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveProfile(Map<String, dynamic> profile) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    final targetProfileId = _profileId(profile);
    final messenger = ScaffoldMessenger.of(context);

    if (currentUserId == null ||
        currentUserId.isEmpty ||
        targetProfileId.isEmpty) {
      return;
    }

    try {
      await _supabase.from('saved_profiles').insert({
        'user_id': currentUserId,
        'saved_profile_id': targetProfileId,
      });

      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Profile saved.')));
    } on PostgrestException catch (error) {
      if (!mounted) return;
      final bool alreadySaved = error.code == '23505';
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              alreadySaved
                  ? 'You already saved this profile.'
                  : 'Failed to save profile: ${error.message}',
            ),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Failed to save profile: $error')),
        );
    }
  }

  Future<void> _shareProfile(Map<String, dynamic> profile) async {
    final name = _profileDisplayName(profile);
    final profileId = _profileId(profile);
    final text = 'Check out $name on AmicUp! amicup://profile/$profileId';

    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Failed to share profile: $error')),
        );
    }
  }

  static const double _dragFeedbackThreshold = 90;

  void _handleDragPointerDown(PointerDownEvent event) {
    if (!mounted) return;
    _dragStartX = event.position.dx;
  }

  void _handleDragPointerMove(PointerMoveEvent event) {
    if (!mounted) return;
    final startX = _dragStartX;
    if (startX == null) return;

    final double delta = event.position.dx - startX;
    final double progress = (delta.abs() / _dragFeedbackThreshold)
        .clamp(0, 1)
        .toDouble();
    final CardSwiperDirection? direction = delta == 0
        ? null
        : (delta > 0 ? CardSwiperDirection.right : CardSwiperDirection.left);

    final previous = _swipeFeedback.value;
    if (direction != previous.direction ||
        (progress - previous.progress).abs() >= 0.02) {
      _swipeFeedback.value = _SwipeFeedback(
        direction: direction,
        progress: progress,
      );
    }
  }

  void _handleDragPointerEnd(PointerEvent event) {
    if (!mounted) return;
    if (_dragStartX == null && _swipeFeedback.value.direction == null) {
      return;
    }
    _dragStartX = null;
    _swipeFeedback.value = const _SwipeFeedback();
  }

  Widget _buildSwipeFeedbackChip({
    required bool isLike,
    required double progress,
  }) {
    final color = isLike ? Colors.green.shade600 : Colors.red.shade600;
    final alignment = isLike ? Alignment.centerLeft : Alignment.centerRight;
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: progress,
          duration: const Duration(milliseconds: 80),
          child: Transform.rotate(
            angle: isLike ? -0.12 : 0.12,
            child: Container(
              margin: EdgeInsets.only(
                left: isLike ? 22 : 0,
                right: isLike ? 0 : 22,
              ),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.9),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: Icon(
                isLike ? Icons.check_rounded : Icons.close_rounded,
                color: Colors.white,
                size: 38,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(Map<String, dynamic> profile) {
    final isFrontCard =
        _remainingCards > 0 &&
        _remainingCards <= _profiles.length &&
        _profileId(profile) == _profileId(_profiles[_remainingCards - 1]);
    return _ProfileCard(
      key: ValueKey(_profileId(profile)),
      profile: profile,
      swipeFeedback: _swipeFeedback,
      isFrontCard: isFrontCard,
      onOpenProfile: (profileId) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProfileView(userId: profileId)),
        );
      },
    );
  }

  Widget _profileActionsMenu(Map<String, dynamic> profile) =>
      PopupMenuButton<String>(
        tooltip: 'Profile options',
        icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
        color: AppTheme.of(context).surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        onSelected: (value) {
          switch (value) {
            case 'report':
              _reportProfile(profile);
              break;
            case 'save':
              _saveProfile(profile);
              break;
            case 'share':
              _shareProfile(profile);
              break;
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'report', child: Text('Report')),
          PopupMenuItem(value: 'save', child: Text('Save profile')),
          PopupMenuItem(value: 'share', child: Text('Share profile')),
        ],
      );

  Future<void> _fetchDiscoverProfiles() async {
    if (!mounted) return;
    final version = ++_fetchVersion;
    setState(() {
      _loading = true;
      _feedError = null;
    });
    if (widget.loadProfiles != null) {
      try {
        final profiles = await widget.loadProfiles!();
        if (mounted && version == _fetchVersion) _installProfiles(profiles);
      } catch (_) {
        if (mounted && version == _fetchVersion) _showFeedLoadError();
      }
      return;
    }
    final currentUserId = _supabase.auth.currentUser?.id;

    if (currentUserId == null || currentUserId.isEmpty) {
      setState(() {
        _loading = false;
        _isFeedEmpty = true;
      });
      return;
    }

    // Start both profile reads together so calculating the badge does not add
    // another serial network wait to opening Discover.
    final currentProfileFuture = _supabase
        .from('profiles')
        .select('sports,hobbies,music,lifestyle,social_vibe,match_intent')
        .eq('id', currentUserId)
        .maybeSingle();

    try {
      setState(() => _loading = true);

      List<String> swipedIds = const [];
      try {
        final swipedResponse = await _supabase
            .from('likes')
            .select('liked_id')
            .eq('liker_id', currentUserId);
        swipedIds = (swipedResponse as List)
            .whereType<Map>()
            .map((item) => item['liked_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
      } catch (error) {
        // A stale/missing likes policy should not prevent the main Discover
        // profiles query from loading or refreshing.
        debugPrint(
          'Unable to read swipe history; showing available profiles: $error',
        );
      }

      // If unavailable, the feed still works and simply omits compatibility
      // badges. Ignore stale responses from an older refresh.
      try {
        final currentProfile = await currentProfileFuture;
        if (!mounted || version != _fetchVersion) return;
        _currentUserProfile = currentProfile;
      } catch (error) {
        if (version == _fetchVersion) _currentUserProfile = null;
        debugPrint('Unable to load profile for compatibility: $error');
      }

      // Keep the profile query simple and filter locally. PostgREST's
      // `not.in` syntax is strict about UUID quoting; passing a Dart list can
      // intermittently produce a malformed request during pull-to-refresh.
      // Local filtering is deterministic and keeps refresh reliable.
      final response = await _supabase
          .from('profiles')
          .select(
            'id,first_name,last_name,username,avatar_url,gallery_photos,'
            'birth_date,location,match_intent,sports,hobbies,music,lifestyle,'
            'social_vibe,languages,bio',
          )
          .neq('id', currentUserId);
      debugPrint('Profiles fetched for Discover: ${response.length}');

      final swipedSet = swipedIds.toSet();
      final profiles = <Map<String, dynamic>>[];
      for (final item in response) {
        final profile = Map<String, dynamic>.from(item);
        if (swipedSet.contains(profile['id']?.toString())) continue;

        final galleryPhotos = _normalizePhotoList(profile['gallery_photos']);
        if (galleryPhotos.isEmpty) {
          final avatarUrl = profile['avatar_url']?.toString().trim() ?? '';
          profile['gallery_photos'] = [
            if (avatarUrl.isNotEmpty) avatarUrl,
            if (avatarUrl.isEmpty) 'https://via.placeholder.com/600x800',
          ];
        } else {
          profile['gallery_photos'] = galleryPhotos;
        }

        profile['compatibility_percent'] = _calculateCompatibilityPercent(
          _currentUserProfile,
          profile,
        );

        final verification = profile['verified_users'];
        profile['is_verified'] = verification is Map
            ? verification['is_verified'] == true
            : verification is List &&
                  verification.whereType<Map>().any(
                    (row) => row['is_verified'] == true,
                  );
        profiles.add(profile);
      }

      if (!mounted || version != _fetchVersion) return;
      _installProfiles(profiles);
    } on PostgrestException catch (error, stackTrace) {
      debugPrint(
        'SUPABASE POSTGREST ERROR in _fetchDiscoverProfiles: '
        '${error.message} (${error.code})',
      );
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted || version != _fetchVersion) return;
      _showFeedLoadError();
    } catch (error, stackTrace) {
      debugPrint('UNEXPECTED ERROR in _fetchDiscoverProfiles: $error');
      debugPrint(stackTrace.toString());
      if (!mounted || version != _fetchVersion) return;
      _showFeedLoadError();
    }
  }

  Future<void> _handleFeedRefresh() async {
    await _fetchDiscoverProfiles();
  }

  void _showFeedLoadError() => setState(() {
    _loading = false;
    _feedError = 'Could not load Discover. Please try again.';
  });

  void _installProfiles(List<Map<String, dynamic>> profiles) {
    setState(() {
      _profiles = List.of(profiles);
      _remainingCards = profiles.length;
      _swipeController = CardSwiperController();
      _swiperKey = UniqueKey();
      _isFeedEmpty = profiles.isEmpty;
      _loading = false;
      _feedError = null;
      _preloadedPhotos.clear();
    });
    _preloadNextPhotos(profiles.length - 1);
  }

  /// Compares the profile interests and social preferences currently
  /// collected by AmicUp. This Jaccard score is a simple overlap indicator,
  /// not a prediction that two people will become friends.
  int? _calculateCompatibilityPercent(
    Map<String, dynamic>? mine,
    Map<String, dynamic> other,
  ) {
    if (mine == null) return null;

    Set<String> matchingInputs(Map<String, dynamic> profile) => {
      for (final field in const [
        'sports',
        'hobbies',
        'music',
        'lifestyle',
        'social_vibe',
      ])
        ...decodeProfileList(profile[field]).map((value) => value.toLowerCase()),
    };

    final myInputs = matchingInputs(mine);
    final theirInputs = matchingInputs(other);
    if (myInputs.isEmpty || theirInputs.isEmpty) return null;

    final union = myInputs.union(theirInputs).length;
    if (union == 0) return null;
    final shared = myInputs.intersection(theirInputs).length;
    return ((shared / union) * 100).round();
  }

  void _preloadNextPhotos(int frontIndex) {
    final cacheWidth = _discoverImageCacheWidth(context);
    // This installed swiper displays the list from last to first.
    for (
      var index = frontIndex;
      index >= 0 && index >= frontIndex - 2;
      index--
    ) {
      final photos = _getProfilePhotos(_profiles[index]);
      if (photos.isEmpty || !_preloadedPhotos.add(photos.first)) continue;
      unawaited(
        precacheImage(
          ResizeImage(NetworkImage(photos.first), width: cacheWidth),
          context,
          onError: (Object error, StackTrace? stack) {
            _preloadedPhotos.remove(photos.first);
          },
        ),
      );
    }
  }

  AppBar _searchHeader() => AppBar(
    title: const Text(
      'Discover',
      style: TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    ),
    backgroundColor: AppTheme.darkSurface,
    foregroundColor: Colors.white,
    toolbarHeight: 48,
    actions: [
      IconButton(
        tooltip: 'Find people',
        icon: const Icon(Icons.search_rounded),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileSearchView()),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (_feedError != null) {
      return Scaffold(
        appBar: _searchHeader(),
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_feedError!, style: const TextStyle(color: Colors.white)),
              TextButton(
                onPressed: _handleFeedRefresh,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_loading) {
      return Scaffold(
        appBar: _searchHeader(),
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            color: AppTheme.of(context).violetStrong,
          ),
        ),
      );
    }

    if (_isFeedEmpty || _profiles.isEmpty) {
      return Scaffold(
        appBar: _searchHeader(),
        backgroundColor: Colors.black,
        body: RefreshIndicator(
          onRefresh: _handleFeedRefresh,
          color: AppTheme.of(context).violet,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: MediaQuery.of(context).size.height,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.search_off_rounded,
                        size: 56,
                        color: Colors.white70,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No people to discover yet',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _handleFeedRefresh,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.of(context).violet,
                          foregroundColor: AppTheme.of(context).onAccent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        icon: const Icon(Icons.refresh),
                        label: const Text('✨ Refresh Feed'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _handleFeedRefresh,
          color: AppTheme.of(context).violet,
          child: LayoutBuilder(
            builder: (context, constraints) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                SizedBox(
                  height: constraints.maxHeight,
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: _handleDragPointerDown,
                    onPointerMove: _handleDragPointerMove,
                    onPointerUp: _handleDragPointerEnd,
                    onPointerCancel: _handleDragPointerEnd,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CardSwiper(
                            key: _swiperKey,
                            controller: _swipeController,
                            cards: _profiles
                                .map((profile) => _buildProfileCard(profile))
                                .toList(),
                            isLoop: false,
                            numberOfCardsDisplayed: _profiles.length >= 2
                                ? 2
                                : 1,
                            padding: EdgeInsets.zero,
                            isHorizontalSwipingEnabled: true,
                            isVerticalSwipingEnabled: false,
                            onSwipe: (index, direction) {
                              _safeSetState(() => _remainingCards = index);
                              _preloadNextPhotos(index - 1);
                              final profile = _profiles[index];
                              final bool isLike =
                                  direction == CardSwiperDirection.right;
                              _dragStartX = null;
                              _swipeFeedback.value = const _SwipeFeedback();
                              unawaited(_recordInteraction(profile, isLike));
                            },
                            onEnd: () {
                              if (_remainingCards == 0) {
                                _safeSetState(() => _isFeedEmpty = true);
                              }
                            },
                          ),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: 78,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.58),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          left: 20,
                          right: 12,
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Discover',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (_remainingCards > 0 &&
                                  _remainingCards <= _profiles.length)
                                _profileActionsMenu(
                                  _profiles[_remainingCards - 1],
                                ),
                              IconButton(
                                tooltip: 'Find people',
                                color: Colors.white,
                                icon: const Icon(Icons.search_rounded),
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ProfileSearchView(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ValueListenableBuilder<_SwipeFeedback>(
                          valueListenable: _swipeFeedback,
                          builder: (context, feedback, _) {
                            if (feedback.direction ==
                                CardSwiperDirection.right) {
                              return _buildSwipeFeedbackChip(
                                isLike: true,
                                progress: feedback.progress,
                              );
                            }
                            if (feedback.direction ==
                                CardSwiperDirection.left) {
                              return _buildSwipeFeedbackChip(
                                isLike: false,
                                progress: feedback.progress,
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _extractProfileId(Map<String, dynamic> profile) {
  final rawValue = profile['id'];
  return rawValue?.toString() ?? '';
}

int _discoverImageCacheWidth(BuildContext context) =>
    (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(360, 1440);

class _SwipeFeedback {
  const _SwipeFeedback({this.direction, this.progress = 0});

  final CardSwiperDirection? direction;
  final double progress;
}

List<String> _normalizePhotoList(dynamic value) {
  return decodeProfileList(value);
}

List<String> _getProfilePhotos(Map<String, dynamic> profile) {
  final List<String> galleryPhotos = _normalizePhotoList(
    profile['gallery_photos'],
  );
  final String avatarUrl = (profile['avatar_url'] ?? '').toString().trim();

  if (galleryPhotos.isNotEmpty) {
    return galleryPhotos;
  }
  if (avatarUrl.isNotEmpty) {
    return [avatarUrl];
  }

  return const <String>['https://via.placeholder.com/600x800'];
}

int? _calculateAge(dynamic birthDateValue) {
  if (birthDateValue == null) return null;
  DateTime? birthDate;
  if (birthDateValue is DateTime) {
    birthDate = birthDateValue;
  } else if (birthDateValue is String && birthDateValue.isNotEmpty) {
    birthDate = DateTime.tryParse(birthDateValue);
  }
  if (birthDate == null) return null;

  final now = DateTime.now();
  int age = now.year - birthDate.year;
  if (now.month < birthDate.month ||
      (now.month == birthDate.month && now.day < birthDate.day)) {
    age--;
  }
  return age >= 0 ? age : null;
}

String _cleanIntentValue(dynamic value) {
  final text = (value ?? '').toString();
  final interests = text
      .replaceAll(RegExp(r'[\[\]\"]'), '')
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .where(
        (part) => !{
          'dating',
          'relationship',
          'something serious',
        }.contains(part.toLowerCase()),
      )
      .map((part) => part.toLowerCase() == 'casual' ? 'Hanging Out' : part)
      .toList();
  return interests.isEmpty ? 'Friendship' : interests.join(' • ');
}

Widget _buildStoryProgressBars(int photoCount, int activeIndex) {
  if (photoCount <= 0) {
    return const SizedBox.shrink();
  }

  return Row(
    children: List.generate(photoCount, (index) {
      final isActive = index == activeIndex;
      return Expanded(
        child: Container(
          height: 4,
          margin: EdgeInsets.only(right: index < photoCount - 1 ? 6 : 0),
          decoration: BoxDecoration(
            color: isActive
                ? Colors.white
                : Colors.white.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      );
    }),
  );
}

/// A single discover card that owns its own photo-carousel state so tapping
/// left/right to change photos rebuilds immediately, independent of
/// [CardSwiper]'s internal widget caching.
class _ProfileCard extends StatefulWidget {
  const _ProfileCard({
    super.key,
    required this.profile,
    required this.onOpenProfile,
    required this.swipeFeedback,
    required this.isFrontCard,
  });

  final Map<String, dynamic> profile;
  final ValueChanged<String> onOpenProfile;
  final ValueListenable<_SwipeFeedback> swipeFeedback;
  final bool isFrontCard;

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  int _activePhotoIndex = 0;

  List<String> get _photos => _getProfilePhotos(widget.profile);

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final SchedulerPhase phase = WidgetsBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else {
      setState(fn);
    }
  }

  void _handlePhotoTap(TapUpDetails details, double cardWidth) {
    final photos = _photos;
    if (photos.isEmpty) return;

    final double tapX = details.localPosition.dx;

    _safeSetState(() {
      if (tapX < cardWidth * 0.3) {
        _activePhotoIndex = (_activePhotoIndex - 1).clamp(0, photos.length - 1);
      } else {
        _activePhotoIndex = (_activePhotoIndex + 1).clamp(0, photos.length - 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final List<String> photos = _photos;
    final int activePhotoIndex = _activePhotoIndex.clamp(
      0,
      photos.isEmpty ? 0 : photos.length - 1,
    );
    final String displayImageUrl = photos.isNotEmpty
        ? photos[activePhotoIndex]
        : 'https://via.placeholder.com/600x800';

    final String firstName = (profile['first_name'] ?? '').toString().trim();
    final String lastName = (profile['last_name'] ?? '').toString().trim();
    final String username = (profile['username'] ?? '').toString().trim();
    final String displayName = [
      firstName,
      lastName,
    ].where((value) => value.isNotEmpty).join(' ').trim();
    final String resolvedName = displayName.isNotEmpty ? displayName : username;

    final String bio = (profile['bio'] ?? '').toString().trim();
    final String location = (profile['location'] ?? profile['city'] ?? '')
        .toString()
        .trim();
    final String matchIntent = (profile['match_intent'] ?? 'Friendship')
        .toString();
    final languages = decodeProfileList(
      profile['languages'],
    ).toSet().take(3).toList();
    final int? age = _calculateAge(profile['birth_date']);

    final List<String> interestTags =
        <String>[
              ..._normalizePhotoList(profile['sports']),
              ..._normalizePhotoList(profile['hobbies']),
              ..._normalizePhotoList(profile['music']),
              ..._normalizePhotoList(profile['lifestyle']),
            ]
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .take(4)
            .toList();

    final Size screenSize = MediaQuery.sizeOf(context);
    double cardWidth = screenSize.width;
    double cardHeight = cardWidth * 16 / 9;
    if (cardHeight > screenSize.height) {
      cardHeight = screenSize.height;
      cardWidth = cardHeight * 9 / 16;
    }

    return DecoratedBox(
      decoration: BoxDecoration(color: AppTheme.of(context).ink),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.network(
              displayImageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              cacheWidth: _discoverImageCacheWidth(context),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: AppTheme.darkSurface,
                  child: const Center(child: CircularProgressIndicator()),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: AppTheme.darkSurface,
                  child: const Icon(
                    Icons.person,
                    size: 72,
                    color: Colors.white70,
                  ),
                );
              },
            ),
          ),
          if (widget.isFrontCard)
            Positioned.fill(
              child: IgnorePointer(
                child: ValueListenableBuilder<_SwipeFeedback>(
                  valueListenable: widget.swipeFeedback,
                  builder: (context, feedback, _) => AnimatedOpacity(
                    opacity: feedback.direction == null ? 0 : feedback.progress,
                    duration: const Duration(milliseconds: 80),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: feedback.direction == CardSwiperDirection.right
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          end: feedback.direction == CardSwiperDirection.right
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          colors: [
                            (feedback.direction == CardSwiperDirection.right
                                    ? Colors.green.shade600
                                    : Colors.red.shade600)
                                .withValues(alpha: 0.24),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) => _handlePhotoTap(details, cardWidth),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  widthFactor: 1,
                  heightFactor: 0.55,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 62, 16, 16),
              child: _buildStoryProgressBars(photos.length, activePhotoIndex),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (profile['compatibility_percent'] is num) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 7),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.of(context).violet.withValues(
                              alpha: 0.88,
                            ),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.32),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                color: AppTheme.of(context).onAccent,
                                size: 14,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${(profile['compatibility_percent'] as num).round()}% compatible',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  height: 1.1,
                                ).copyWith(
                                  color: AppTheme.of(context).onAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => widget.onOpenProfile(
                                _extractProfileId(profile),
                              ),
                              child: Text(
                                resolvedName.isNotEmpty
                                    ? resolvedName
                                    : 'AmicUp member',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          if (age != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              '$age',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const SizedBox(width: 5),
                          Icon(
                            Icons.verified_rounded,
                            color: AppTheme.of(context).violetStrong,
                            size: 17,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_rounded,
                            color: AppTheme.of(context).onDarkAccent,
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              location.isNotEmpty
                                  ? location
                                  : 'Somewhere in the city',
                              style: TextStyle(
                                color: AppTheme.of(context).onDarkAccent,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (languages.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.language_rounded,
                              color: AppTheme.of(context).onDarkAccent,
                              size: 13,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                languages.join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppTheme.of(context).onDarkAccent,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _cleanIntentValue(matchIntent),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (bio.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          bio,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (interestTags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 28,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: interestTags.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 6),
                            itemBuilder: (context, index) {
                              final tag = interestTags[index];
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  tag,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
