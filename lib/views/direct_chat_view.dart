import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import 'package:flutter/services.dart';
import '../widgets/message_interaction.dart';
import '../widgets/compact_message_menu.dart';
import '../widgets/reply_message_text.dart';
import '../widgets/chat_message_locator.dart';
import '../widgets/chat_header_capsule.dart';
import '../widgets/typing_indicator.dart';
import '../services/chat_message_write.dart';
import '../widgets/forward_message_sheet.dart';
import '../services/message_forwarding.dart';
import 'review_person_view.dart';
import '../theme/app_theme.dart';
import '../theme/amicup_motion.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_view.dart';
import '../services/supabase_service.dart';
import '../services/inbox_service.dart';

class ImageZoomViewer extends StatefulWidget {
  const ImageZoomViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  final List<String> images;
  final int initialIndex;

  @override
  State<ImageZoomViewer> createState() => _ImageZoomViewerState();
}

class _ImageZoomViewerState extends State<ImageZoomViewer> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(
      0,
      widget.images.isEmpty ? 0 : widget.images.length - 1,
    );
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'No images to display.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              final url = widget.images[index];
              return InteractiveViewer(
                panEnabled: true,
                minScale: 1.0,
                maxScale: 4.0,
                child: Center(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    cacheWidth:
                        (MediaQuery.sizeOf(context).width *
                                MediaQuery.devicePixelRatioOf(context) *
                                2)
                            .round()
                            .clamp(720, 2560),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(
                        Icons.broken_image,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (widget.images.length > 1)
            Positioned(
              bottom: 24,
              right: 18,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.of(context).ink.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_currentIndex + 1} / ${widget.images.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DirectChatView extends StatefulWidget {
  const DirectChatView({
    super.key,
    required this.matchId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
  });

  final String matchId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatar;

  @override
  State<DirectChatView> createState() => _DirectChatViewState();
}

class _DirectChatViewState extends State<DirectChatView>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _composerFocus.addListener(_handleComposerFocusChanged);
    _subscribeToTyping();
    NotificationService().visibleChats[this] = (payload) =>
        mounted &&
        ModalRoute.of(context)?.isCurrent == true &&
        payload['match_id']?.toString() == widget.matchId;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    } else if (state != AppLifecycleState.resumed) {
      unawaited(stopTyping());
    }
  }

  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Map<String, String> _senderNames = {};
  final Set<String> _senderNameLookups = {};
  final List<File> _attachedFiles = [];
  bool _isSending = false;
  final Map<String, String> _messageReactions = {};
  final Set<String> _deletedMessageIds = {};
  final Set<String> _deletingMessageIds = {};
  final Set<String> _knownMessageIds = {};
  final Set<String> _arrivingMessageIds = {};
  bool _hasMessageSnapshot = false;

  Future<void> _insertMessage(Map<String, dynamic> payload) =>
      insertChatMessage(payload, (data) async {
        await _supabase.from('messages').insert(data);
      });
  Map<String, dynamic>? _replyingTo;
  final FocusNode _composerFocus = FocusNode();
  final ChatMessageLocator _messageLocator = ChatMessageLocator();
  RealtimeChannel? _typingChannel;
  Timer? _typingStopTimer;
  Timer? _remoteTypingExpiry;
  bool _typingChannelReady = false;
  bool _sentTyping = false;
  bool _otherUserTyping = false;

  void _subscribeToTyping() {
    final channel = _supabase.channel('typing:${widget.matchId}');
    _typingChannel = channel;
    channel
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            if (payload['user_id']?.toString() != widget.otherUserId) return;
            final isTyping = payload['typing'] == true;
            _remoteTypingExpiry?.cancel();
            if (mounted && _otherUserTyping != isTyping) {
              setState(() => _otherUserTyping = isTyping);
            }
            if (isTyping) {
              _remoteTypingExpiry = Timer(const Duration(seconds: 4), () {
                if (mounted && _otherUserTyping) {
                  setState(() => _otherUserTyping = false);
                }
              });
            }
          },
        )
        .subscribe((status, error) {
          _typingChannelReady = status == RealtimeSubscribeStatus.subscribed;
          if (!_typingChannelReady) _sentTyping = false;
        });
  }

  Future<void> startTyping() async {
    final userId = _currentUserId;
    final channel = _typingChannel;
    if (userId == null || channel == null || !_typingChannelReady) return;
    if (_sentTyping) return;
    _sentTyping = true;
    try {
      await channel.sendBroadcastMessage(
        event: 'typing',
        payload: {'user_id': userId, 'typing': true},
      );
    } catch (_) {
      _sentTyping = false;
    }
  }

  Future<void> stopTyping() async {
    _typingStopTimer?.cancel();
    final userId = _currentUserId;
    final channel = _typingChannel;
    if (!_sentTyping || userId == null || channel == null) return;
    _sentTyping = false;
    try {
      await channel.sendBroadcastMessage(
        event: 'typing',
        payload: {'user_id': userId, 'typing': false},
      );
    } catch (_) {
      // The remote indicator also has a short expiry for interrupted sessions.
    }
  }

  void _handleComposerChanged(String value) {
    _typingStopTimer?.cancel();
    if (value.trim().isEmpty || !_composerFocus.hasFocus) {
      unawaited(stopTyping());
      return;
    }
    unawaited(startTyping());
    _typingStopTimer = Timer(
      const Duration(milliseconds: 1400),
      () => unawaited(stopTyping()),
    );
  }

  void _handleComposerFocusChanged() {
    if (!_composerFocus.hasFocus) unawaited(stopTyping());
  }

  Future<void> _revealOriginal(String text, String? id) async {
    final target = _messageLocator.replyTarget(text, id);
    final found =
        target != null &&
        await _messageLocator.reveal(target, _scrollController);
    if (!found && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Original message is no longer available.'),
        ),
      );
    }
  }

  void _startReply(Map<String, dynamic> message) {
    if (_isSending) return;
    setState(() => _replyingTo = message);
    _composerFocus.requestFocus();
  }

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  late final Stream<List<Map<String, dynamic>>> _messagesStream = _supabase
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('match_id', widget.matchId)
      .order('created_at', ascending: false);

  Future<void> _loadSenderNames(List<Map<String, dynamic>> messages) async {
    final ids = <String>{};
    for (final message in messages) {
      final senderId = message['sender_id']?.toString();
      if (senderId != null && senderId.isNotEmpty) {
        ids.add(senderId);
      }
    }

    ids.removeAll(_senderNames.keys);
    ids.removeAll(_senderNameLookups);
    if (ids.isEmpty) return;
    _senderNameLookups.addAll(ids);

    try {
      final response = await _supabase
          .from('profiles')
          .select('id, first_name, username')
          .inFilter('id', ids.toList());

      final names = <String, String>{};
      for (final row in response as List) {
        final map = Map<String, dynamic>.from(row);
        final userId = map['id']?.toString();
        if (userId == null || userId.isEmpty) continue;

        final firstName = map['first_name']?.toString().trim();
        final username = map['username']?.toString().trim();
        names[userId] = (firstName != null && firstName.isNotEmpty)
            ? firstName
            : (username != null && username.isNotEmpty ? username : 'User');
      }

      if (!mounted) return;
      setState(() {
        _senderNames.addAll(names);
      });
    } catch (_) {
      // Ignore profile lookup errors and fallback to generic labels.
    } finally {
      _senderNameLookups.removeAll(ids);
    }
  }

  List<String> _parseAlbumUrls(Map<String, dynamic> message) {
    final dynamic rawImageUrls = message['image_urls'];
    if (rawImageUrls is List) {
      return rawImageUrls
          .whereType<String>()
          .map((url) => url.trim())
          .where((url) => url.isNotEmpty)
          .toList();
    }
    if (rawImageUrls is String && rawImageUrls.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawImageUrls);
        if (decoded is List) {
          return decoded
              .whereType<String>()
              .map((url) => url.trim())
              .where((url) => url.isNotEmpty)
              .toList();
        }
      } catch (_) {}
    }

    final String content = message['content']?.toString() ?? '';
    if (content.startsWith('[ALBUM]:')) {
      final payload = content.replaceFirst('[ALBUM]:', '').trim();
      if (payload.isEmpty) {
        return const [];
      }
      return payload
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
    }

    final String? imageUrl = message['image_url']?.toString();
    if (imageUrl != null && imageUrl.trim().isNotEmpty) {
      return [imageUrl.trim()];
    }

    if (content.startsWith('[IMAGE]:')) {
      final url = content.replaceFirst('[IMAGE]:', '').trim();
      return url.isEmpty ? const [] : [url];
    }

    final normalized = content.trim();
    if (normalized.contains('chat_images') ||
        normalized.contains('storage/v1') ||
        normalized.endsWith('.jpg') ||
        normalized.endsWith('.jpeg') ||
        normalized.endsWith('.png') ||
        normalized.endsWith('.webp')) {
      return [normalized];
    }

    return const [];
  }

  String _extractCaptionFromMessage(Map<String, dynamic> message) {
    final String content = message['content']?.toString() ?? '';
    final imageUrls = _parseAlbumUrls(message);

    if (imageUrls.isEmpty) {
      return content.trim();
    }

    if (content.startsWith('[ALBUM]:') || content.startsWith('[IMAGE]:')) {
      return '';
    }

    return content.trim();
  }

  Future<void> _reportUser() async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) return;

    final reasonController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Report User'),
          content: TextField(
            controller: reasonController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'Tell us why you are reporting this user...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );

    if (result != true) return;
    final reasonText = reasonController.text.trim();
    if (reasonText.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a report reason.')),
      );
      return;
    }

    try {
      await _supabase.from('reports').insert({
        'reporter_id': currentUserId,
        'reported_user_id': widget.otherUserId,
        'reason': reasonText,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User reported successfully.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to report user: $error')));
    }
  }

  Future<void> _blockUser() async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) return;

    try {
      await _supabase.from('blocked_users').insert({
        'blocker_id': currentUserId,
        'blocked_id': widget.otherUserId,
      });

      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to block user: $error')));
    }
  }

  Future<void> _unmatch() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Amic?'),
        content: const Text(
          'This will remove this Amic and your conversation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove Amic'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await SupabaseService(
        client: _supabase,
      ).unmatchUser(targetUserId: widget.otherUserId);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not remove Amic: $error')));
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  Future<void> _pickGalleryPhotos() async {
    if (_attachedFiles.length >= 5) {
      _showSnackBar('You can attach a maximum of 5 images.');
      return;
    }

    final picker = ImagePicker();
    final List<XFile> picked = await picker.pickMultiImage(imageQuality: 85);
    if (picked.isEmpty) return;

    final int remainingSlots = 5 - _attachedFiles.length;
    List<File> filesToAdd = picked.map((xfile) => File(xfile.path)).toList();

    if (filesToAdd.length > remainingSlots) {
      filesToAdd = filesToAdd.take(remainingSlots).toList();
      _showSnackBar('You can attach a maximum of 5 images.');
    }

    if (filesToAdd.isEmpty) return;

    setState(() {
      _attachedFiles.addAll(filesToAdd);
    });
  }

  Future<void> _showAttachmentOptions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo'),
              onTap: () => Navigator.of(sheetContext).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.of(sheetContext).pop('gallery'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'camera') {
      if (_attachedFiles.length >= 5) {
        _showSnackBar('You can attach a maximum of 5 images.');
        return;
      }
      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (!mounted || photo == null) return;
      setState(() => _attachedFiles.add(File(photo.path)));
      return;
    }
    await _pickGalleryPhotos();
  }

  Future<void> _takePhotoFromCamera() async {
    if (_attachedFiles.length >= 5) {
      _showSnackBar('Maximum 5 images allowed');
      return;
    }
    final photo = await ImagePicker().pickImage(source: ImageSource.camera);
    if (photo == null || !mounted) return;
    setState(() => _attachedFiles.add(File(photo.path)));
  }

  Future<void> _pickFromGallery() => _pickGalleryPhotos();

  Future<List<String>> _uploadAttachedFiles() async {
    if (_attachedFiles.isEmpty) return const [];

    final futures = _attachedFiles.map((file) async {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
      await _supabase.storage.from('chat_attachments').upload(fileName, file);
      return _supabase.storage.from('chat_attachments').getPublicUrl(fileName);
    });

    return Future.wait(futures);
  }

  Future<void> _sendMessage() async {
    final currentUserId = _currentUserId;
    final text = _messageController.text.trim();
    if (currentUserId == null) return;

    if (_isSending) return;
    if (text.isEmpty && _attachedFiles.isEmpty) return;
    unawaited(stopTyping());

    final reply = _replyingTo;
    final originalText = reply?['content']?.toString().trim() ?? '';
    final replyBody =
        originalText.startsWith('↩ ') && originalText.contains('\n')
        ? originalText.substring(originalText.indexOf('\n') + 1)
        : originalText;
    final replyText =
        replyBody.startsWith('[IMAGE]:') || replyBody.startsWith('[ALBUM]:')
        ? 'Photo'
        : replyBody.replaceAll(RegExp(r'\s+'), ' ');
    final composedText = replyText.isEmpty ? text : '↩ $replyText\n$text';
    _replyingTo = null;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      if (_attachedFiles.isNotEmpty) {
        final uploadedUrls = await _uploadAttachedFiles();
        final payload = <String, dynamic>{
          'match_id': widget.matchId,
          'sender_id': currentUserId,
          if (reply != null) 'reply_to_id': reply['id'],
        };

        if (_attachedFiles.length == 1) {
          final singleUrl = uploadedUrls.first;
          if (composedText.isNotEmpty) {
            payload['content'] = composedText;
            payload['image_url'] = singleUrl;
          } else {
            payload['content'] = '[IMAGE]: $singleUrl';
            payload['image_url'] = singleUrl;
          }
        } else {
          final albumBody = composedText.isNotEmpty
              ? composedText
              : '[ALBUM]: ${uploadedUrls.join(',')}';
          payload['content'] = albumBody;
          payload['image_urls'] = uploadedUrls;
        }

        await _insertMessage(payload);

        setState(() => _attachedFiles.clear());
      } else {
        await _insertMessage({
          'match_id': widget.matchId,
          'sender_id': currentUserId,
          'content': composedText,
          if (reply != null) 'reply_to_id': reply['id'],
        });
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send message: $error')));
      if (_messageController.text.isEmpty) {
        _messageController.text = text;
        setState(() => _replyingTo = reply);
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  bool _shouldShowDateHeader(
    Map<String, dynamic> currentMessage,
    Map<String, dynamic> nextOlderMessage,
  ) {
    final currentMessageTime = DateTime.parse(
      currentMessage['created_at'].toString(),
    ).toLocal();
    final nextOlderMessageTime = DateTime.parse(
      nextOlderMessage['created_at'].toString(),
    ).toLocal();

    final gap = currentMessageTime.difference(nextOlderMessageTime).abs();
    final isNewDay =
        currentMessageTime.year != nextOlderMessageTime.year ||
        currentMessageTime.month != nextOlderMessageTime.month ||
        currentMessageTime.day != nextOlderMessageTime.day;

    return gap.inMinutes >= 15 || isNewDay;
  }

  Future<void> _showMessageActions(Map<String, dynamic> message) async {
    final action = await showCompactMessageMenu(
      context,
      preview: forwardText(message),
      imageUrl: forwardPhotos(message).firstOrNull,
      selectedReaction: _messageReactions[message['id']?.toString()],
      anchor: _messageLocator.bounds(message['id']?.toString() ?? ''),
      ownMessage: message['sender_id']?.toString() == _currentUserId,
    );
    if (!mounted || action == null) return;
    final id = message['id']?.toString() ?? '';
    final content = message['content']?.toString() ?? '';
    if (action.startsWith('react:')) {
      setState(
        () => toggleMessageReaction(_messageReactions, id, action.substring(6)),
      );
    } else if (action == 'forward') {
      await showForwardMessageSheet(context, message);
    } else if (action == 'reply') {
      _startReply(message);
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: content));
      _showSnackBar('Message copied');
    } else if (action == 'delete') {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete message?'),
              content: const Text('This message will be removed for everyone.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ) ??
          false;
      if (confirmed) {
        if (!mounted) return;
        try {
          setState(() => _deletingMessageIds.add(id));
          await Future<void>.delayed(
            AmicUpMotion.duration(context, AmicUpMotion.fast),
          );
          final deleted = await _supabase
              .from('messages')
              .delete()
              .eq('id', id)
              .eq('sender_id', _currentUserId!)
              .select('id');
          if (!deleted.any((row) => row['id']?.toString() == id)) {
            throw StateError('The database did not allow this deletion.');
          }
          if (mounted) {
            setState(() {
              _deletedMessageIds.add(id);
              _deletingMessageIds.remove(id);
              _messageReactions.remove(id);
              if (_replyingTo?['id']?.toString() == id) _replyingTo = null;
            });
          }
        } catch (error) {
          if (mounted) setState(() => _deletingMessageIds.remove(id));
          _showSnackBar('Could not delete message');
        }
      }
    } else if (action == 'report') {
      try {
        await _supabase.from('reports').insert({
          'reporter_id': _currentUserId,
          'reported_user_id': message['sender_id'],
          'reported_id': id,
          'reason': 'Inappropriate message',
        });
        _showSnackBar('Message reported');
      } catch (error) {
        _showSnackBar('Could not report message');
      }
    }
  }

  Widget _buildDateHeader(DateTime timestamp) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Center(
        child: Text(
          DateFormat('EEE, MMM d • h:mm a').format(timestamp),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppTheme.of(context).muted,
          ),
        ),
      ),
    );
  }

  bool _markingRead = false;

  Future<void> _markIncomingMessagesAsRead(
    List<Map<String, dynamic>> messages,
  ) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null ||
        _markingRead ||
        !mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed)) {
      return;
    }

    final unreadIds = messages
        .where(
          (message) =>
              message['sender_id'] != currentUserId &&
              message['is_read'] != true,
        )
        .map((message) => message['id'].toString())
        .toList();
    if (unreadIds.isEmpty) return;
    _markingRead = true;

    try {
      await InboxService(_supabase).markRead(widget.matchId, unreadIds);
    } catch (_) {
      // Ignore read receipt update failures and keep the UI responsive.
    } finally {
      _markingRead = false;
    }
  }

  Widget _buildAlbumBubble({
    required List<String> urls,
    required String caption,
    String? replyToId,
    required bool isCurrentUser,
  }) {
    final imageCount = urls.length;
    final thumbnailCacheWidth = (240 * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(240, 720);
    final singleCacheWidth =
        (MediaQuery.sizeOf(context).width *
                0.72 *
                MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(300, 1080);
    final List<Widget> gridTiles = [];

    for (var i = 0; i < urls.length && i < 4; i++) {
      final url = urls[i];
      final moreCount = imageCount - 4;
      final bool showMoreOverlay = i == 3 && imageCount > 4;

      gridTiles.add(
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ImageZoomViewer(images: urls, initialIndex: i),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20.0),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  url,
                  fit: BoxFit.cover,
                  cacheWidth: thumbnailCacheWidth,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : Container(
                          color: AppTheme.of(context).line,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.broken_image,
                    color: AppTheme.of(context).muted,
                  ),
                ),
                if (showMoreOverlay)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black38,
                      alignment: Alignment.center,
                      child: Text(
                        '+$moreCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
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

    Widget albumGrid;
    switch (imageCount) {
      case 1:
        albumGrid = GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ImageZoomViewer(images: urls, initialIndex: 0),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20.0),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
                maxHeight: 400,
              ),
              child: Image.network(
                urls.first,
                fit: BoxFit.contain,
                cacheWidth: singleCacheWidth,
                alignment: Alignment.center,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : SizedBox(
                        width: MediaQuery.of(context).size.width * 0.72,
                        height: 180,
                        child: Container(
                          color: AppTheme.of(context).line,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                errorBuilder: (context, error, stackTrace) => SizedBox(
                  width: MediaQuery.of(context).size.width * 0.72,
                  height: 180,
                  child: Center(
                    child: Icon(
                      Icons.broken_image,
                      color: AppTheme.of(context).muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        break;
      case 2:
        albumGrid = SizedBox(
          width: 240,
          child: Row(
            children: urls
                .take(2)
                .map(
                  (url) => Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ImageZoomViewer(
                              images: urls,
                              initialIndex: urls.indexOf(url),
                            ),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20.0),
                          clipBehavior: Clip.antiAlias,
                          child: Image.network(
                            url,
                            fit: BoxFit.cover,
                            cacheWidth: thumbnailCacheWidth,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        );
        break;
      case 3:
        albumGrid = SizedBox(
          width: 240,
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ImageZoomViewer(images: urls, initialIndex: 0),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20.0),
                    clipBehavior: Clip.antiAlias,
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Image.network(
                        urls[0],
                        fit: BoxFit.cover,
                        cacheWidth: thumbnailCacheWidth,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                flex: 1,
                child: Column(
                  children: urls
                      .sublist(1)
                      .asMap()
                      .entries
                      .map(
                        (entry) => Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ImageZoomViewer(
                                  images: urls,
                                  initialIndex: entry.key + 1,
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: EdgeInsets.only(
                                bottom: entry.key == 1 ? 0 : 2,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20.0),
                                clipBehavior: Clip.antiAlias,
                                child: Image.network(
                                  entry.value,
                                  fit: BoxFit.cover,
                                  cacheWidth: thumbnailCacheWidth,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        );
        break;
      default:
        albumGrid = SizedBox(
          width: 240,
          child: GridView.count(
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
            shrinkWrap: true,
            childAspectRatio: 1,
            children: gridTiles,
          ),
        );
        break;
    }

    return Column(
      crossAxisAlignment: isCurrentUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.70,
            maxHeight: 260,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: albumGrid,
          ),
        ),
        if (caption.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isCurrentUser
                  ? AppTheme.of(context).violet
                  : AppTheme.of(context).surfaceMuted,
              borderRadius: BorderRadius.circular(18),
            ),
            child: ReplyMessageText(
              caption,
              onQuoteTap: () => _revealOriginal(caption, replyToId),
              style: TextStyle(
                color: isCurrentUser
                    ? AppTheme.of(context).onAccent
                    : AppTheme.of(context).ink,
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService().visibleChats.remove(this);
    _typingStopTimer?.cancel();
    _remoteTypingExpiry?.cancel();
    _composerFocus.removeListener(_handleComposerFocusChanged);
    final typingChannel = _typingChannel;
    if (typingChannel != null) {
      unawaited(_supabase.removeChannel(typingChannel));
    }
    _messageLocator.dispose();
    _composerFocus.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        toolbarHeight: 62,
        leadingWidth: 64,
        titleSpacing: 0,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: Color.lerp(
          AppTheme.of(context).canvas,
          AppTheme.of(context).violet,
          Theme.of(context).brightness == Brightness.dark ? 0.17 : 0.08,
        ),
        foregroundColor: AppTheme.of(context).ink,
        leading: Padding(
          padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
          child: ChatHeaderCapsule(
            child: IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        title: ChatHeaderCapsule(
          child: InkWell(
            onTap: () {
              if (widget.otherUserId.isEmpty) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileView(userId: widget.otherUserId),
                ),
              );
            },
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  const SizedBox(width: 7),
                  CircleAvatar(
                    radius: 19,
                    backgroundColor: AppTheme.of(context).surfaceMuted,
                    backgroundImage:
                        widget.otherUserAvatar != null &&
                            widget.otherUserAvatar!.isNotEmpty
                        ? ResizeImage(
                            NetworkImage(widget.otherUserAvatar!),
                            width: (38 * MediaQuery.devicePixelRatioOf(context))
                                .round()
                                .clamp(38, 192),
                          )
                        : null,
                    child:
                        (widget.otherUserAvatar == null ||
                            widget.otherUserAvatar!.isEmpty)
                        ? Text(
                            widget.otherUserName
                                .substring(
                                  0,
                                  widget.otherUserName.length > 1 ? 2 : 1,
                                )
                                .toUpperCase(),
                            style: TextStyle(
                              color: AppTheme.of(context).violetStrong,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      widget.otherUserName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
              ),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(5, 5, 0, 5),
            child: ChatHeaderCapsule(
              child: IconButton(
                tooltip: 'Rate this person',
                icon: const Icon(Icons.star_outline_rounded, size: 25),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReviewPersonView(
                      userId: widget.otherUserId,
                      name: widget.otherUserName,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(5, 5, 10, 5),
            child: ChatHeaderCapsule(
              child: PopupMenuButton<String>(
                tooltip: 'Chat options',
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) {
                  switch (value) {
                    case 'report':
                      _reportUser();
                      break;
                    case 'block':
                      _blockUser();
                      break;
                    case 'unmatch':
                      _unmatch();
                      break;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'report', child: Text('Report User')),
                  PopupMenuItem(value: 'block', child: Text('Block User')),
                  PopupMenuItem(value: 'unmatch', child: Text('Remove Amic')),
                ],
              ),
            ),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: AppTheme.chatBackgroundDecoration(context),
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _messagesStream,
          builder: (context, snapshot) {
            final messages = (snapshot.data ?? <Map<String, dynamic>>[])
                .map(displayMessage)
                .where(
                  (message) =>
                      !_deletedMessageIds.contains(message['id']?.toString()),
                )
                .toList();
            if (snapshot.hasData) {
              final ids = messages.map(
                (message) => message['id']?.toString() ?? '',
              );
              if (_hasMessageSnapshot) {
                _arrivingMessageIds.addAll(
                  ids.where((id) => !_knownMessageIds.contains(id)),
                );
              }
              _knownMessageIds.addAll(ids);
              _hasMessageSnapshot = true;
            }
            _messageLocator.messages = messages;
            if (messages.isNotEmpty) {
              unawaited(_loadSenderNames(messages));
            }

            final currentUserId = _currentUserId;
            String? lastReadMsgId;
            if (currentUserId != null) {
              for (final message in messages) {
                if (message['sender_id'] == currentUserId &&
                    message['is_read'] == true) {
                  lastReadMsgId = message['id'];
                  break;
                }
              }
            }

            if (currentUserId != null &&
                messages.any(
                  (message) =>
                      message['sender_id'] != currentUserId &&
                      message['is_read'] != true,
                )) {
              Future.microtask(() {
                if (!mounted) return;
                _markIncomingMessagesAsRead(messages);
              });
            }

            return Column(
              children: [
                Expanded(
                  child:
                      snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData
                      ? const Center(child: CircularProgressIndicator())
                      : snapshot.hasError
                      ? Center(
                          child: Text(
                            'Unable to load messages: ${snapshot.error}',
                          ),
                        )
                      : messages.isEmpty
                      ? const Center(child: Text('No messages yet. Say hi!'))
                      : ListView.builder(
                          controller: _scrollController,
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          reverse: true,
                          padding: const EdgeInsets.all(16),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final message = messages[index];
                            final senderId = message['sender_id']?.toString();
                            final isCurrentUser = senderId == currentUserId;
                            final String content =
                                message['content']?.toString() ?? '';
                            final messageTime = DateTime.parse(
                              message['created_at'].toString(),
                            ).toLocal();

                            final shouldShowDateHeader =
                                index == messages.length - 1 ||
                                (index < messages.length - 1 &&
                                    _shouldShowDateHeader(
                                      message,
                                      messages[index + 1],
                                    ));

                            final List<String> albumUrls = _parseAlbumUrls(
                              message,
                            );
                            final String caption = _extractCaptionFromMessage(
                              message,
                            );
                            final bool hasAlbum = albumUrls.isNotEmpty;
                            final showSeen =
                                isCurrentUser && message['id'] == lastReadMsgId;
                            final messageId = message['id']?.toString() ?? '';

                            return AmicUpMessageMotion(
                              key: ValueKey(message['id']),
                              animateEntrance: _arrivingMessageIds.contains(
                                messageId,
                              ),
                              visible: !_deletingMessageIds.contains(messageId),
                              ownMessage: isCurrentUser,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (shouldShowDateHeader)
                                    _buildDateHeader(messageTime),
                                  Align(
                                    alignment: isCurrentUser
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: MessageInteraction(
                                      key: _messageLocator.keyFor(messageId),
                                      ownMessage: isCurrentUser,
                                      messageId: messageId,
                                      forwarded:
                                          message['is_forwarded'] == true,
                                      sentAt: DateTime.tryParse(
                                        message['created_at']?.toString() ?? '',
                                      ),
                                      highlighted: _messageLocator.highlighted,
                                      onOptions: () =>
                                          _showMessageActions(message),
                                      onHeart: () => setState(
                                        () => toggleMessageReaction(
                                          _messageReactions,
                                          messageId,
                                          '❤️',
                                        ),
                                      ),
                                      onReply: () => _startReply(message),
                                      child: Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        constraints: BoxConstraints(
                                          maxWidth:
                                              MediaQuery.of(
                                                context,
                                              ).size.width *
                                              0.75,
                                        ),
                                        child: Column(
                                          crossAxisAlignment: isCurrentUser
                                              ? CrossAxisAlignment.end
                                              : CrossAxisAlignment.start,
                                          children: [
                                            if (hasAlbum)
                                              _buildAlbumBubble(
                                                urls: albumUrls,
                                                caption: caption,
                                                replyToId:
                                                    message['reply_to_id']
                                                        ?.toString(),
                                                isCurrentUser: isCurrentUser,
                                              )
                                            else
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 12,
                                                    ),
                                                decoration:
                                                    AppTheme.chatBubbleDecoration(
                                                      context,
                                                      own: isCurrentUser,
                                                    ),
                                                child: ReplyMessageText(
                                                  content,
                                                  onQuoteTap: () =>
                                                      _revealOriginal(
                                                        content,
                                                        message['reply_to_id']
                                                            ?.toString(),
                                                      ),
                                                  style: TextStyle(
                                                    color: isCurrentUser
                                                        ? AppTheme.of(
                                                            context,
                                                          ).onAccent
                                                        : AppTheme.of(
                                                            context,
                                                          ).ink,
                                                  ),
                                                ),
                                              ),
                                            if (_messageReactions[messageId] !=
                                                null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 2,
                                                ),
                                                child: Text(
                                                  _messageReactions[messageId]!,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                            if (showSeen)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 4,
                                                  right: 2,
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.done_all,
                                                      size: 12,
                                                      color: AppTheme.of(
                                                        context,
                                                      ).violet,
                                                    ),
                                                    SizedBox(width: 2),
                                                    Text(
                                                      'Seen',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: AppTheme.of(
                                                          context,
                                                        ).violet,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                TypingIndicator(visible: _otherUserTyping),
                _buildMessageInputField(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMessageInputField() {
    return SafeArea(
      top: false,
      bottom: true,
      child: AmicUpGlassSurface(
        radius: 26,
        blur: 0,
        color: AppTheme.of(context).surface.withValues(alpha: 0.86),
        borderColor: AppTheme.of(context).line.withValues(alpha: 0.6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: Colors.transparent),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_replyingTo != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                  decoration: BoxDecoration(
                    color: AppTheme.of(context).surfaceMuted,
                    borderRadius: BorderRadius.circular(20),
                    border: Border(
                      left: BorderSide(
                        color: AppTheme.of(context).violet,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Replying to: ${_replyingTo!['content'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _replyingTo = null),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
              if (_attachedFiles.isNotEmpty)
                SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: _attachedFiles.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(
                            _attachedFiles[index],
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _attachedFiles.removeAt(index)),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: AppTheme.of(context).ink,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Take Photo',
                    onPressed: _takePhotoFromCamera,
                    onLongPress: _showAttachmentOptions,
                    icon: Icon(
                      Icons.camera_alt_rounded,
                      color: AppTheme.of(context).muted,
                      size: 24,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Choose from Gallery',
                    onPressed: _pickFromGallery,
                    icon: Icon(
                      Icons.photo_library_rounded,
                      color: AppTheme.of(context).muted,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.of(context).surfaceMuted,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: TextField(
                        controller: _messageController,
                        focusNode: _composerFocus,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                        onChanged: _handleComposerChanged,
                        onSubmitted: (_) => _sendMessage(),
                        style: const TextStyle(fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Message...',
                          filled: false,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintStyle: TextStyle(
                            color: AppTheme.of(context).muted,
                            fontSize: 15,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _messageController,
                    builder: (context, value, _) {
                      final canSend =
                          !_isSending &&
                          (value.text.trim().isNotEmpty ||
                              _attachedFiles.isNotEmpty);
                      return IconButton.filled(
                        tooltip: 'Send message',
                        onPressed: canSend ? _sendMessage : null,
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.of(context).violet,
                          foregroundColor: AppTheme.of(context).onAccent,
                          disabledBackgroundColor: AppTheme.of(
                            context,
                          ).surfaceMuted,
                          disabledForegroundColor: AppTheme.of(context).muted,
                        ),
                        icon: const Icon(Icons.send_rounded, size: 19),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
