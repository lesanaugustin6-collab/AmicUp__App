import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/profile_field_codec.dart';
import '../widgets/saved_profiles_tab.dart';
import '../widgets/profile_reviews_tab.dart';
import '../services/review_service.dart';
import 'direct_chat_view.dart';
import 'edit_profile_view.dart';
import 'event_details_view.dart';
import 'settings_view.dart';
import 'friends_view.dart';
import '../widgets/avatar_preview.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key, this.userId});

  final String? userId;

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _PromptData {
  const _PromptData({required this.question, required this.answer});

  final String question;
  final String answer;
}

class _ProfileViewState extends State<ProfileView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;
  late final TabController _tabController;
  Map<String, dynamic> _profile = {};
  List<String> _photos = const [];
  List<String> _interests = const [];
  List<String> _languages = const [];
  List<_PromptData> _prompts = const [];
  List<Map<String, dynamic>> _hostedEvents = const [];
  List<Map<String, dynamic>> _attendedEvents = const [];
  int? _friendsCount;
  int? _reviewCount;
  double? _averageRating;
  bool _loading = true;
  bool _notFound = false;
  bool _isCurrentUser = false;
  bool _isVerified = false;
  bool _hasLiked = false;
  bool _hasMatch = false;
  bool _isMatching = false;
  bool _photoBusy = false;

  String? get _currentUserId => _supabase.auth.currentUser?.id;
  String get _targetUserId {
    final current = _currentUserId;
    return widget.userId == null || widget.userId == current
        ? (current ?? '')
        : widget.userId!;
  }

  String get _displayName {
    final first = (_profile['first_name'] ?? '').toString().trim();
    final last = (_profile['last_name'] ?? '').toString().trim();
    final name = [first, last].where((part) => part.isNotEmpty).join(' ');
    return name.isNotEmpty
        ? name
        : (_profile['username'] ?? 'AmicUp member').toString();
  }

  String get _username => (_profile['username'] ?? '').toString().trim();
  String get _bio => (_profile['bio'] ?? '').toString().trim();
  String get _country => (_profile['country'] ?? '').toString().trim();
  String get _location =>
      (_profile['location'] ?? _profile['city'] ?? '').toString().trim();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(
      length: widget.userId == null || widget.userId == _currentUserId ? 4 : 3,
      vsync: this,
    );
    unawaited(_loadProfile());
    unawaited(_fetchFriendsCount());
    ReviewService.changes.addListener(_reviewsChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ReviewService.changes.removeListener(_reviewsChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_handleRefresh());
    }
  }

  Future<void> _loadProfile({bool loadRelated = true}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _notFound = false;
    });
    final id = _targetUserId;
    _isCurrentUser = widget.userId == null || widget.userId == _currentUserId;
    if (id.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _notFound = true;
        });
      }
      return;
    }
    try {
      final row = await _supabase
          .from('profiles')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        setState(() {
          _loading = false;
          _notFound = true;
        });
        return;
      }
      final verification = await _supabase
          .from('verified_users')
          .select('is_verified')
          .eq('user_id', id)
          .maybeSingle();
      if (!mounted) return;
      final profile = Map<String, dynamic>.from(row);
      setState(() {
        _profile = profile;
        _photos = [
          ..._list(profile['gallery_photos']),
        ].where((value) => value.isNotEmpty).toSet().toList();
        _interests = [
          ..._list(profile['sports']),
          ..._list(profile['hobbies']),
          ..._list(profile['music']),
          ..._list(profile['lifestyle']),
        ].where((value) => value.isNotEmpty).toSet().toList();
        _languages = _list(profile['languages']).toSet().toList();
        _prompts = _readPrompts(profile['prompts']);
        _isVerified = verification?['is_verified'] == true;
        _loading = false;
      });
      if (!loadRelated) return;
      unawaited(_loadReviewCount(id));
      if (_isCurrentUser) {
        unawaited(_loadHostedEvents(id));
        unawaited(_loadAttendedEvents(id));
      } else {
        unawaited(_loadAttendedEvents(id));
        unawaited(_checkExistingLike(id));
      }
    } catch (error) {
      debugPrint('Failed to load profile: $error');
      if (mounted) {
        setState(() {
          _loading = false;
          _notFound = true;
        });
      }
    }
  }

  Future<void> _fetchFriendsCount() async {
    try {
      final userId = _targetUserId;
      if (userId.isEmpty) {
        debugPrint('DEBUG MATCHES: Current user ID is NULL');
        return;
      }

      final result = await _supabase.rpc(
        'get_profile_friends',
        params: {'target_id': userId, 'page_size': 0},
      );
      final totalCount = (result['count'] as num).toInt();

      debugPrint('=== REAL FRIEND/MATCH COUNT FETCHED: $totalCount ===');
      if (!mounted) return;
      setState(() => _friendsCount = totalCount);
    } catch (error) {
      debugPrint('Error fetching friends count: $error');
    }
  }

  Future<void> _addProfilePhoto() async {
    if (_photoBusy || _photos.length >= 6) {
      if (_photos.length >= 6 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You can add up to 6 profile photos.')),
        );
      }
      return;
    }
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 84,
    );
    if (picked == null || !mounted) return;
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) return;
    setState(() => _photoBusy = true);
    try {
      final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _supabase.storage
          .from('profiles')
          .upload(
            path,
            File(picked.path),
            fileOptions: const FileOptions(upsert: false),
          );
      final url = _supabase.storage.from('profiles').getPublicUrl(path);
      final next = [..._photos, url];
      await _supabase
          .from('profiles')
          .update({'gallery_photos': encodeProfileList(next)})
          .eq('id', userId);
      if (mounted) setState(() => _photos = next);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not add photo: $error')));
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _removeProfilePhoto(String url) async {
    if (_photoBusy) return;
    if (_photos.length <= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keep at least 2 profile photos.')),
      );
      return;
    }
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) return;
    final previous = List<String>.from(_photos);
    final next = List<String>.from(previous)..remove(url);
    setState(() {
      _photos = next;
      _photoBusy = true;
    });
    try {
      await _supabase
          .from('profiles')
          .update({'gallery_photos': encodeProfileList(next)})
          .eq('id', userId);
    } catch (error) {
      if (mounted) {
        setState(() => _photos = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove photo: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _loadHostedEvents(String id) async {
    try {
      final rows = await _supabase
          .from('events')
          .select(
            'id, title, cover_image_url, start_time, location_name, category',
          )
          .eq('host_id', id)
          .order('start_time', ascending: false);
      if (mounted) {
        setState(
          () => _hostedEvents = (rows as List)
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList(),
        );
      }
    } catch (error) {
      debugPrint('Failed to load hosted events: $error');
    }
  }

  Future<void> _loadAttendedEvents(String userId) async {
    try {
      final rows = await _supabase
          .from('event_attendees')
          .select(
            'event_id, events(id, title, cover_image_url, start_time, location_name, category)',
          )
          .eq('user_id', userId)
          .eq('status', 'going');
      if (!mounted) return;
      final events = <Map<String, dynamic>>[];
      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final event = row['events'];
        if (event is Map) {
          events.add(Map<String, dynamic>.from(event));
        }
      }
      setState(() => _attendedEvents = events);
    } catch (error) {
      debugPrint('Failed to load attended events: $error');
    }
  }

  Future<void> _handleRefresh() async {
    final profileId = _targetUserId;
    if (profileId.isEmpty) return;

    await Future.wait<void>([
      _loadProfile(loadRelated: false),
      _fetchFriendsCount(),
      _loadHostedEvents(profileId),
      _loadAttendedEvents(profileId),
      _loadReviewCount(profileId),
    ]);

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _checkExistingLike(String id) async {
    final current = _currentUserId;
    if (current == null) return;
    try {
      final rows = await _supabase
          .from('likes')
          .select('action,is_like')
          .eq('liker_id', current)
          .eq('liked_id', id)
          .order('created_at', ascending: false)
          .limit(1);
      final matches = await _supabase
          .from('matches')
          .select('id')
          .or(
            'and(user_1.eq.$current,user_2.eq.$id),and(user_1.eq.$id,user_2.eq.$current)',
          )
          .limit(1);
      if (mounted) {
        final row = rows.isEmpty ? null : rows.first;
        final action = row?['action']?.toString();
        setState(() {
          _hasMatch = matches.isNotEmpty;
          _hasLiked =
              action == 'like' ||
              action == 'superlike' ||
              ((action == null || action.isEmpty) && row?['is_like'] == true);
        });
      }
    } catch (_) {}
  }

  Future<void> _handleMatch() async {
    final current = _currentUserId;
    if (current == null ||
        _targetUserId.isEmpty ||
        _hasLiked ||
        _hasMatch ||
        _isMatching) {
      return;
    }
    setState(() => _isMatching = true);
    try {
      final previous = await _supabase
          .from('likes')
          .select('id')
          .eq('liker_id', current)
          .eq('liked_id', _targetUserId);
      if (previous.isEmpty) {
        await _supabase.from('likes').insert({
          'liker_id': current,
          'liked_id': _targetUserId,
          'action': 'like',
          'is_like': true,
        });
      } else {
        final updated = await _supabase
            .from('likes')
            .update({'action': 'like', 'is_like': true})
            .eq('liker_id', current)
            .eq('liked_id', _targetUserId)
            .select('id');
        if (updated.isEmpty) {
          throw StateError('Could not change the previous pass.');
        }
      }
      final interactions = await _supabase
          .from('interactions')
          .select('id')
          .eq('user_id', current)
          .eq('target_user_id', _targetUserId);
      if (interactions.isEmpty) {
        await _supabase.from('interactions').insert({
          'user_id': current,
          'target_user_id': _targetUserId,
          'action': 'like',
        });
      } else {
        await _supabase
            .from('interactions')
            .update({'action': 'like'})
            .eq('user_id', current)
            .eq('target_user_id', _targetUserId);
      }
      await _checkExistingLike(_targetUserId);
      if (!mounted) return;
      setState(() {
        _hasLiked = true;
        _isMatching = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isMatching = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not connect: $error')));
    }
  }

  Future<void> _openChat() async {
    final current = _currentUserId;
    if (current == null || _targetUserId.isEmpty) return;
    try {
      final rows = await _supabase
          .from('matches')
          .select('id, user_1, user_2')
          .or('user_1.eq.$current,user_2.eq.$current');
      String? matchId;
      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        if ((row['user_1'] == current && row['user_2'] == _targetUserId) ||
            (row['user_1'] == _targetUserId && row['user_2'] == current)) {
          matchId = row['id']?.toString();
        }
      }
      if (!mounted) return;
      if (matchId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are not connected yet.')),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DirectChatView(
            matchId: matchId!,
            otherUserId: _targetUserId,
            otherUserName: _displayName,
            otherUserAvatar: _profile['avatar_url']?.toString(),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to open chat: $error')));
      }
    }
  }

  Future<void> _shareProfile() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text:
              'Check out $_displayName on AmicUp! amicup://profile/$_targetUserId',
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to share profile: $error')),
        );
      }
    }
  }

  void _openEditProfile() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const EditProfileView()))
        .then((result) {
          if (result == true && mounted) unawaited(_loadProfile());
        });
  }

  void _openReviews() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Reviews')),
          body: ProfileReviewsTab(
            userId: _targetUserId,
            onCount: (count) {
              if (mounted) setState(() => _reviewCount = count);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _loadReviewCount(String id) async {
    try {
      final ratings = await _supabase
          .from('profile_reviews')
          .select('rating')
          .eq('reviewed_user_id', id);
      if (mounted) {
        final values = ratings
            .map((row) => row['rating'])
            .whereType<num>()
            .map((value) => value.toDouble())
            .toList();
        setState(() {
          _reviewCount = values.length;
          _averageRating = values.isEmpty
              ? null
              : values.reduce((a, b) => a + b) / values.length;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _reviewCount = null;
          _averageRating = null;
        });
      }
    }
  }

  void _reviewsChanged() => unawaited(_loadReviewCount(_targetUserId));

  Future<List<Map<String, dynamic>>> _loadSavedProfiles() async {
    final owner = _currentUserId;
    if (!_isCurrentUser || owner == null) return [];
    final saved = await _supabase
        .from('saved_profiles')
        .select('saved_profile_id')
        .eq('user_id', owner)
        .order('created_at', ascending: false);
    final ids = saved
        .map((row) => row['saved_profile_id'])
        .whereType<String>()
        .toSet()
        .toList();
    if (ids.isEmpty) return [];
    final profiles = await _supabase
        .from('profiles')
        .select('id, first_name, last_name, username, avatar_url')
        .inFilter('id', ids);
    final byId = {for (final profile in profiles) profile['id']: profile};
    // Keep save order and omit deleted or inaccessible profiles.
    return [
      for (final id in ids)
        if (byId.containsKey(id)) byId[id]!,
    ];
  }

  List<String> _list(dynamic value) => decodeProfileList(value);
  List<_PromptData> _readPrompts(dynamic raw) {
    final map = decodeProfilePrompts(raw);
    const questions = [
      "I'm looking for a friend who...",
      'My ideal way to spend a free afternoon with friends is...',
      'The fastest way to become my friend is...',
    ];
    return [
      for (var index = 0; index < questions.length; index++)
        if ((map['prompt_${index + 1}'] ?? '').toString().trim().isNotEmpty)
          _PromptData(
            question: questions[index],
            answer: map['prompt_${index + 1}'].toString().trim(),
          ),
    ];
  }

  Widget _stat(BuildContext context, String label, String value) => Column(
    children: [
      Text(
        value,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = theme.scaffoldBackgroundColor;
    final foregroundColor =
        theme.textTheme.bodyLarge?.color ?? theme.colorScheme.onSurface;
    if (_loading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: CircularProgressIndicator(
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      );
    }
    if (_notFound) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
        ),
        body: Center(
          child: Text(
            'Profile not found',
            style: TextStyle(color: foregroundColor),
          ),
        ),
      );
    }
    final avatar = _profile['avatar_url']?.toString() ?? '';
    return Scaffold(
      backgroundColor: backgroundColor,
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: NestedScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          headerSliverBuilder: (context, _) => [
            SliverAppBar(
              pinned: true,
              backgroundColor: backgroundColor,
              foregroundColor: foregroundColor,
              automaticallyImplyLeading: Navigator.canPop(context),
              centerTitle: true,
              title: Text(
                _username.isEmpty ? 'Profile' : '@$_username',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              actions: [
                if (_isCurrentUser)
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsView()),
                    ),
                    icon: const Icon(Icons.settings_outlined),
                  ),
              ],
            ),
            SliverToBoxAdapter(
              child: Container(
                color: backgroundColor,
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          child: GestureDetector(
                            onTap: avatar.isEmpty
                                ? null
                                : () => showAvatarPreview(
                                    context,
                                    NetworkImage(avatar),
                                  ),
                            child: CircleAvatar(
                              radius: 43,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              backgroundImage: avatar.isEmpty
                                  ? null
                                  : NetworkImage(avatar),
                              child: avatar.isEmpty
                                  ? Icon(
                                      Icons.person,
                                      size: 42,
                                      color: foregroundColor.withValues(
                                        alpha: 0.7,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 22),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: foregroundColor,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  if (_isVerified)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Icon(
                                        Icons.verified,
                                        color: theme
                                            .colorScheme
                                            .onPrimaryContainer,
                                        size: 21,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _stat(
                                    context,
                                    'Events',
                                    _hostedEvents.length.toString(),
                                  ),
                                  InkWell(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            FriendsView(userId: _targetUserId),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: _stat(
                                        context,
                                        'Friends',
                                        _friendsCount?.toString() ?? '—',
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: _openReviews,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: _stat(
                                        context,
                                        'Reviews',
                                        _reviewCount?.toString() ?? '—',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ProfileLocationAndLanguages(
                      country: _country,
                      location: _location,
                      languages: _languages,
                    ),
                    if (_bio.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _bio,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: foregroundColor, height: 1.35),
                      ),
                    ],
                    const SizedBox(height: 3),
                    InkWell(
                      onTap: _openReviews,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Semantics(
                              label: _averageRating == null
                                  ? 'No ratings yet'
                                  : '${_averageRating!.toStringAsFixed(1)} out of 5 stars',
                              child: Row(
                                children: List.generate(5, (index) {
                                  final rating = _averageRating ?? 0;
                                  final icon = rating >= index + 0.75
                                      ? Icons.star_rounded
                                      : rating >= index + 0.25
                                      ? Icons.star_half_rounded
                                      : Icons.star_outline_rounded;
                                  return Icon(
                                    icon,
                                    size: 22,
                                    color:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? const Color(0xFFFFD166)
                                        : const Color(0xFFD99800),
                                  );
                                }),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              _reviewCount == null
                                  ? '—'
                                  : _averageRating == null
                                  ? '0.0'
                                  : _averageRating!.toStringAsFixed(1),
                              style: TextStyle(
                                color: foregroundColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (_reviewCount != null && _reviewCount! > 0) ...[
                              const SizedBox(width: 7),
                              Text(
                                '($_reviewCount)',
                                style: TextStyle(
                                  color: AppTheme.of(context).muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            const SizedBox(width: 3),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: AppTheme.of(context).muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_interests.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _InterestsStrip(interests: _interests),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isCurrentUser
                                ? _openEditProfile
                                : (_hasLiked || _hasMatch || _isMatching
                                      ? null
                                      : _handleMatch),
                            icon: Icon(
                              _isCurrentUser
                                  ? Icons.edit_outlined
                                  : (_hasLiked
                                        ? Icons.check
                                        : Icons.check_rounded),
                            ),
                            label: Text(
                              _isCurrentUser
                                  ? 'Edit Profile'
                                  : (_isMatching
                                        ? 'Connecting…'
                                        : _hasMatch
                                        ? 'Connected'
                                        : _hasLiked
                                        ? 'Connect sent'
                                        : 'Connect'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isCurrentUser
                                ? _shareProfile
                                : _openChat,
                            icon: Icon(
                              _isCurrentUser
                                  ? Icons.share_outlined
                                  : Icons.chat_bubble_outline,
                            ),
                            label: Text(_isCurrentUser ? 'Share' : 'Message'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: foregroundColor,
                              side: BorderSide(
                                color: foregroundColor.withValues(alpha: 0.24),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverTabBarDelegate(
                TabBar(
                  controller: _tabController,
                  indicatorColor: theme.primaryColor,
                  labelColor: theme.colorScheme.onSurface,
                  unselectedLabelColor: AppTheme.of(context).muted,
                  tabs: [
                    const Tab(icon: Icon(Icons.grid_on_rounded)),
                    const Tab(icon: Icon(Icons.photo_library_outlined)),
                    const Tab(icon: Icon(Icons.lightbulb_outline)),
                    if (_isCurrentUser)
                      const Tab(
                        icon: Tooltip(
                          message: 'Saved profiles',
                          child: Icon(Icons.bookmark_border_rounded),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              _EventsProfileTab(
                hostedEvents: _hostedEvents,
                attendedEvents: _attendedEvents,
              ),
              _MediaTab(
                photos: _photos,
                editable: _isCurrentUser,
                busy: _photoBusy,
                onAdd: _addProfilePhoto,
                onDelete: _removeProfilePhoto,
              ),
              _IcebreakersTab(prompts: _prompts),
              if (_isCurrentUser)
                SavedProfilesTab(
                  loadProfiles: _loadSavedProfiles,
                  onOpen: (id) => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ProfileView(userId: id)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileLocationAndLanguages extends StatelessWidget {
  const ProfileLocationAndLanguages({
    super.key,
    this.country = '',
    required this.location,
    required this.languages,
  });

  final String country;
  final String location;
  final List<String> languages;

  String get _placeLabel {
    final selectedCountry = country.trim();
    final enteredLocation = location.trim();
    if (selectedCountry.isEmpty && enteredLocation.isEmpty) {
      return 'Location not set';
    }
    if (selectedCountry.isEmpty) return enteredLocation;
    if (enteredLocation.isEmpty) return selectedCountry;
    final countryLower = selectedCountry.toLowerCase();
    final locationLower = enteredLocation.toLowerCase();
    if (locationLower == countryLower ||
        locationLower.startsWith('$countryLower,') ||
        locationLower.startsWith('$countryLower -')) {
      return enteredLocation;
    }
    return '$selectedCountry, $enteredLocation';
  }

  Future<void> _showLanguages(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: AppTheme.of(context).surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (sheetContext) {
          final colors = AppTheme.of(sheetContext);
          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.55,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Languages',
                            style: Theme.of(sheetContext).textTheme.titleMedium
                                ?.copyWith(
                                  color: colors.ink,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close languages',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final language in languages)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: colors.surfaceMuted,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: colors.line),
                            ),
                            child: Text(
                              language,
                              style: TextStyle(
                                color: colors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.of(context);
    final visibleLanguages = languages.take(2).join(', ');
    final maxWidth = MediaQuery.sizeOf(context).width - 36;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on_outlined, size: 16, color: colors.muted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  _placeLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.muted, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        if (languages.isNotEmpty)
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.language_rounded, size: 16, color: colors.muted),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    visibleLanguages,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted, fontSize: 13),
                  ),
                ),
                if (languages.length > 2) ...[
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () => _showLanguages(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Show more',
                      style: TextStyle(
                        color: colors.violetStrong,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _DarkChip extends StatelessWidget {
  const _DarkChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    ),
  );
}

class _InterestsStrip extends StatelessWidget {
  const _InterestsStrip({required this.interests});

  final List<String> interests;

  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    width: double.infinity,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.72),
      ),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0, 0.045, 0.92, 1],
        ).createShader(bounds),
        child: ListView.separated(
          physics: const BouncingScrollPhysics(),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          itemCount: interests.length,
          separatorBuilder: (_, _) => const SizedBox(width: 7),
          itemBuilder: (_, index) => _DarkChip(label: interests[index]),
        ),
      ),
    ),
  );
}

class _EventsProfileTab extends StatelessWidget {
  const _EventsProfileTab({
    required this.hostedEvents,
    required this.attendedEvents,
  });

  final List<Map<String, dynamic>> hostedEvents;
  final List<Map<String, dynamic>> attendedEvents;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: 'Hosted'),
            Tab(text: 'Attended'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              _CompactEventsList(
                events: hostedEvents,
                emptyText: 'No hosted events yet.',
              ),
              _CompactEventsList(
                events: attendedEvents,
                emptyText: 'No attended events yet.',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CompactEventsList extends StatelessWidget {
  const _CompactEventsList({required this.events, required this.emptyText});

  final List<Map<String, dynamic>> events;
  final String emptyText;

  @override
  Widget build(BuildContext context) => events.isEmpty
      ? _EmptyTab(icon: Icons.event_available_outlined, text: emptyText)
      : ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          itemCount: events.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) =>
              ProfileEventCard(event: events[index]),
        );
}

class ProfileEventCard extends StatelessWidget {
  const ProfileEventCard({super.key, required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final image = event['cover_image_url']?.toString().trim() ?? '';
    final title = event['title']?.toString().trim() ?? 'Untitled event';
    final category = event['category']?.toString().trim() ?? 'Event';
    final location =
        event['location_name']?.toString().trim() ?? 'Location TBA';
    final start = DateTime.tryParse(
      event['start_time']?.toString() ?? '',
    )?.toLocal();
    final eventId = event['id']?.toString() ?? '';

    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: eventId.isEmpty
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EventDetailsView(eventId: eventId),
                ),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 21 / 9,
              child: image.isEmpty
                  ? ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.event_outlined,
                        color: scheme.onSurfaceVariant,
                        size: 36,
                      ),
                    )
                  : Image.network(
                      image,
                      fit: BoxFit.cover,
                      cacheWidth:
                          (MediaQuery.sizeOf(context).width *
                                  MediaQuery.devicePixelRatioOf(context))
                              .round()
                              .clamp(360, 1440),
                      errorBuilder: (_, _, _) => ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.event_outlined,
                          color: scheme.onSurfaceVariant,
                          size: 36,
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$category · $location',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (start != null) ...[
                        const SizedBox(width: 10),
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: scheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('MMM d · h:mm a').format(start),
                          style: TextStyle(
                            color: scheme.onPrimaryContainer,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
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

class _MediaTab extends StatelessWidget {
  const _MediaTab({
    required this.photos,
    this.editable = false,
    this.busy = false,
    this.onAdd,
    this.onDelete,
  });
  final List<String> photos;
  final bool editable;
  final bool busy;
  final VoidCallback? onAdd;
  final ValueChanged<String>? onDelete;
  @override
  Widget build(BuildContext context) => photos.isEmpty && !editable
      ? const _EmptyTab(
          icon: Icons.photo_library_outlined,
          text: 'No profile media yet',
        )
      : GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          itemCount: photos.length + (editable && photos.length < 6 ? 1 : 0),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemBuilder: (context, index) {
            if (index == photos.length) {
              return InkWell(
                onTap: busy ? null : onAdd,
                borderRadius: BorderRadius.circular(20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Center(
                    child: busy
                        ? const CircularProgressIndicator()
                        : Icon(
                            Icons.add_a_photo_outlined,
                            color: Theme.of(context).colorScheme.primary,
                            size: 28,
                          ),
                  ),
                ),
              );
            }
            final photo = photos[index];
            return Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  onTap: () => _showFullscreenPhoto(context, photo),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.network(
                      photo,
                      fit: BoxFit.cover,
                      cacheWidth:
                          (MediaQuery.sizeOf(context).width /
                                  3 *
                                  MediaQuery.devicePixelRatioOf(context))
                              .round()
                              .clamp(120, 480),
                      errorBuilder: (_, _, _) => Icon(
                        Icons.broken_image_outlined,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                if (editable)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: photos.length <= 2
                            ? 'Keep at least 2 photos'
                            : 'Remove photo',
                        visualDensity: VisualDensity.compact,
                        onPressed: busy ? null : () => onDelete?.call(photo),
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
}

void _showFullscreenPhoto(BuildContext context, String imageUrl) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            child: Center(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                cacheWidth:
                    (MediaQuery.sizeOf(context).width *
                            MediaQuery.devicePixelRatioOf(context) *
                            2)
                        .round()
                        .clamp(720, 2560),
              ),
            ),
          ),
          Positioned(
            top: 16,
            right: 12,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        ],
      ),
    ),
  );
}

class _IcebreakersTab extends StatelessWidget {
  const _IcebreakersTab({required this.prompts});

  final List<_PromptData> prompts;

  @override
  Widget build(BuildContext context) {
    if (prompts.isEmpty) {
      return const _EmptyTab(
        icon: Icons.lightbulb_outline,
        text: 'No icebreakers added yet.',
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(18),
      itemCount: prompts.length,
      itemBuilder: (context, index) {
        final prompt = prompts[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: _StatPanel(
            title: prompt.question,
            children: [
              Text(
                prompt.answer,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatPanel extends StatelessWidget {
  const _StatPanel({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.38),
          size: 48,
        ),
        const SizedBox(height: 12),
        Text(
          text,
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    ),
  );
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  const _SliverTabBarDelegate(this.tabBar);
  final TabBar tabBar;
  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Container(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: tabBar,
  );
  @override
  bool shouldRebuild(covariant _SliverTabBarDelegate oldDelegate) => false;
}
