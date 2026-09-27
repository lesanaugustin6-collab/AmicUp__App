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
import '../services/chat_message_write.dart';
import '../widgets/forward_message_sheet.dart';
import '../services/message_forwarding.dart';
import '../services/inbox_service.dart';
import '../widgets/chat_photo_thumbnail.dart';
import '../theme/app_theme.dart';
import '../theme/amicup_motion.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'image_gallery_view.dart';
import 'group_info_view.dart';

class ChannelChatView extends StatefulWidget {
  const ChannelChatView({
    super.key,
    required this.channelId,
    required this.channelName,
  });

  final String channelId;
  final String channelName;

  @override
  State<ChannelChatView> createState() => _ChannelChatViewState();
}

class _ChannelChatViewState extends State<ChannelChatView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final Map<String, String> _userNames = {};
  final Set<String> _userNameLookups = {};
  final List<File> _attachedFiles = [];
  bool _isSending = false;
  int? _memberCount;
  int _messageCooldownSeconds = 0;
  String? _channelImageUrl;
  RealtimeChannel? _membershipChannel;
  Timer? _memberRefresh;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMemberCount());
    unawaited(_loadChannelSettings());
    NotificationService().visibleChats[this] = (payload) =>
        mounted &&
        ModalRoute.of(context)?.isCurrent == true &&
        payload['channel_id']?.toString() == widget.channelId;
    _membershipChannel = _supabase
        .channel(
          'group-count-${widget.channelId}-${DateTime.now().microsecondsSinceEpoch}',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'channel_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'channel_id',
            value: widget.channelId,
          ),
          callback: (_) {
            _memberRefresh?.cancel();
            _memberRefresh = Timer(
              const Duration(milliseconds: 300),
              _loadMemberCount,
            );
          },
        )
        .subscribe();
  }

  Future<void> _loadMemberCount() async {
    try {
      final counts = await InboxService(
        _supabase,
      ).memberCounts([widget.channelId]);
      if (mounted) setState(() => _memberCount = counts[widget.channelId]);
    } catch (_) {
      // An unavailable count must never masquerade as zero members.
    }
  }

  Future<void> _loadChannelSettings() async {
    try {
      final channel = await _supabase
          .from('channels')
          .select('message_cooldown_seconds,icon_url')
          .eq('id', widget.channelId)
          .single();
      final cooldown = (channel['message_cooldown_seconds'] as num?)?.toInt();
      if (mounted) {
        setState(() {
          if (cooldown != null) _messageCooldownSeconds = cooldown;
          _channelImageUrl = channel['icon_url']?.toString();
        });
      }
    } catch (_) {
      // The SQL migration has not been applied yet; retain the safe default.
    }
  }

  Future<void> _markMessagesRead(List<Map<String, dynamic>> messages) async {
    final ids = messages
        .where((message) => message['sender_id']?.toString() != _currentUserId)
        .map((message) => message['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;
    try {
      await _supabase.rpc(
        'mark_channel_messages_read',
        params: {'p_channel_id': widget.channelId, 'p_message_ids': ids},
      );
    } catch (_) {
      // Read receipts are supplementary and must not interrupt the chat.
    }
  }

  DateTime? _lastMessageSentTime;
  String? _lastDisplayedMessageId;
  String? _lastReadMessageId;
  final Map<String, String> _messageReactions = {};
  final Set<String> _deletedMessageIds = {};
  final Set<String> _deletingMessageIds = {};
  final Set<String> _knownMessageIds = {};
  final Set<String> _arrivingMessageIds = {};
  bool _hasMessageSnapshot = false;

  Future<void> _insertMessage(Map<String, dynamic> payload) =>
      insertChatMessage(payload, (data) async {
        await _supabase.from('channel_messages').insert(data);
      });
  Map<String, dynamic>? _replyingTo;
  final FocusNode _composerFocus = FocusNode();
  final ChatMessageLocator _messageLocator = ChatMessageLocator();

  Future<void> _revealOriginal(String text, String? id) async {
    final target = _messageLocator.replyTarget(text, id);
    final found =
        target != null &&
        await _messageLocator.reveal(target, _scrollController);
    if (!found && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Original message is no longer available.')),
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
      .from('channel_messages')
      .stream(primaryKey: ['id'])
      .eq('channel_id', widget.channelId)
      .order('created_at', ascending: true);

  Future<void> _loadUserNames(List<Map<String, dynamic>> messages) async {
    final userIds = <String>{};
    for (final message in messages) {
      final senderId = message['sender_id']?.toString();
      if (senderId != null && senderId.isNotEmpty) {
        userIds.add(senderId);
      }
    }

    userIds.removeAll(_userNames.keys);
    userIds.removeAll(_userNameLookups);
    if (userIds.isEmpty) return;
    _userNameLookups.addAll(userIds);

    try {
      final profiles = await _supabase
          .from('profiles')
          .select('id, first_name, last_name, username')
          .inFilter('id', userIds.toList());

      final names = <String, String>{};
      for (final profile in profiles as List) {
        final id = profile['id']?.toString();
        if (id == null || id.isEmpty) continue;

        final firstName = profile['first_name']?.toString().trim();
        final lastName = profile['last_name']?.toString().trim();
        final username = profile['username']?.toString().trim();

        if (firstName != null && firstName.isNotEmpty) {
          names[id] = [
            firstName,
            lastName ?? '',
          ].where((part) => part.isNotEmpty).join(' ');
        } else if (username != null && username.isNotEmpty) {
          names[id] = username;
        } else {
          names[id] = 'User';
        }
      }

      if (!mounted) return;
      setState(() => _userNames.addAll(names));
    } catch (_) {
      // Ignore profile lookup errors and continue with generic sender labels.
    } finally {
      _userNameLookups.removeAll(userIds);
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
      _showSnackBar('Maximum 5 images allowed');
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

  Future<void> _sendTextMessage() async {
    final currentUserId = _currentUserId;
    final text = _textController.text.trim();

    if (currentUserId == null) return;

    final now = DateTime.now();
    if (_messageCooldownSeconds > 0 &&
        _lastMessageSentTime != null &&
        now.difference(_lastMessageSentTime!).inSeconds <
            _messageCooldownSeconds) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Slow down! Wait $_messageCooldownSeconds seconds before sending again.',
          ),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    if (_isSending || (text.isEmpty && _attachedFiles.isEmpty)) return;

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
    _textController.clear();

    try {
      if (_attachedFiles.isNotEmpty) {
        final uploadedUrls = await _uploadAttachedFiles();
        final payload = <String, dynamic>{
          'channel_id': widget.channelId,
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
        _lastMessageSentTime = DateTime.now();
      } else {
        if (text.isEmpty) return;

        await _insertMessage({
          'channel_id': widget.channelId,
          'sender_id': currentUserId,
          'content': composedText,
          if (reply != null) 'reply_to_id': reply['id'],
        });
        _lastMessageSentTime = DateTime.now();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send message: $error')));
      if (_textController.text.isEmpty) {
        _textController.text = text;
        setState(() => _replyingTo = reply);
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _leaveGroup() async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Group?'),
        content: const Text('Are you sure you want to leave this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _supabase
          .from('channel_members')
          .delete()
          .eq('channel_id', widget.channelId)
          .eq('user_id', currentUserId);

      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to leave group: $error')));
    }
  }

  Future<void> _showGroupPanel() => showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close group info',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, animation, secondaryAnimation) => Align(
      alignment: Alignment.centerRight,
      child: FractionallySizedBox(
        widthFactor: .88,
        child: Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: GroupInfoView(
            channelId: widget.channelId,
            name: widget.channelName,
            embedded: true,
          ),
        ),
      ),
    ),
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) =>
        SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        ),
  );

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
    if (action.startsWith('react:')) {
      setState(
        () => toggleMessageReaction(_messageReactions, id, action.substring(6)),
      );
    } else if (action == 'forward') {
      await showForwardMessageSheet(context, message);
    } else if (action == 'reply') {
      _startReply(message);
    } else if (action == 'copy') {
      await Clipboard.setData(
        ClipboardData(text: message['content']?.toString() ?? ''),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Message copied')));
      }
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
              .from('channel_messages')
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
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not delete message')),
            );
          }
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
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Message reported')));
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not report message')),
          );
        }
      }
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
    final List<Widget> gridTiles = [];

    for (var i = 0; i < urls.length && i < 4; i++) {
      final url = urls[i];
      final moreCount = imageCount - 4;
      final bool showMoreOverlay = i == 3 && imageCount > 4;

      gridTiles.add(
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ImageGalleryView(images: urls, initialIndex: i),
            ),
          ),
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
                errorBuilder: (context, error, stackTrace) =>
                    Icon(Icons.broken_image, color: AppTheme.of(context).muted),
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
      );
    }

    Widget albumGrid;
    switch (imageCount) {
      case 1:
        albumGrid = ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            width: 240,
            child: AspectRatio(
              aspectRatio: 1,
              child: ChatPhotoThumbnail(images: urls),
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
                            builder: (_) => ImageGalleryView(
                              images: urls,
                              initialIndex: urls.indexOf(url),
                            ),
                          ),
                        ),
                        child: Image.network(
                          url,
                          fit: BoxFit.cover,
                          cacheWidth: thumbnailCacheWidth,
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
          height: 160,
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ImageGalleryView(images: urls, initialIndex: 0),
                    ),
                  ),
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
                                builder: (_) => ImageGalleryView(
                                  images: urls,
                                  initialIndex: entry.key + 1,
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: EdgeInsets.only(
                                bottom: entry.key == 1 ? 0 : 2,
                              ),
                              child: Image.network(
                                entry.value,
                                fit: BoxFit.cover,
                                cacheWidth: thumbnailCacheWidth,
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
    _memberRefresh?.cancel();
    NotificationService().visibleChats.remove(this);
    if (_membershipChannel != null) {
      unawaited(_supabase.removeChannel(_membershipChannel!));
    }
    _messageLocator.dispose();
    _composerFocus.dispose();
    _textController.dispose();
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
            onTap: _showGroupPanel,
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  const SizedBox(width: 7),
                  CircleAvatar(
                    radius: 19,
                    backgroundColor: AppTheme.of(context).surfaceMuted,
                    backgroundImage: _channelImageUrl?.isNotEmpty == true
                        ? ResizeImage(
                            NetworkImage(_channelImageUrl!),
                            width: (38 * MediaQuery.devicePixelRatioOf(context))
                                .round()
                                .clamp(38, 192),
                          )
                        : null,
                    child: _channelImageUrl?.isNotEmpty == true
                        ? null
                        : Icon(
                            Icons.groups_rounded,
                            size: 21,
                            color: AppTheme.of(context).violetStrong,
                          ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.channelName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _memberCount == null
                              ? 'Group chat'
                              : '$_memberCount ${_memberCount == 1 ? 'member' : 'members'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
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
            padding: const EdgeInsets.fromLTRB(5, 5, 10, 5),
            child: ChatHeaderCapsule(
              child: IconButton(
                icon: const Icon(Icons.exit_to_app_rounded),
                tooltip: 'Leave group',
                onPressed: _leaveGroup,
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
            if (messages.isNotEmpty &&
                messages.last['id']?.toString() != _lastReadMessageId) {
              _lastReadMessageId = messages.last['id']?.toString();
              Future.microtask(() => _markMessagesRead(messages));
            }
            if (messages.isNotEmpty &&
                messages.last['id']?.toString() != _lastDisplayedMessageId) {
              _lastDisplayedMessageId = messages.last['id']?.toString();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    _scrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  );
                }
              });
              unawaited(_loadUserNames(messages));
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
                      ? const Center(
                          child: Text(
                            'No messages yet. Be the first to say hello!',
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final message = messages[index];
                            final senderId = message['sender_id']?.toString();
                            final isCurrentUser = senderId == _currentUserId;
                            final String content =
                                message['content']?.toString() ?? '';
                            final senderName = _userNames[senderId] ?? 'User';
                            final List<String> albumUrls = _parseAlbumUrls(
                              message,
                            );
                            final String caption = _extractCaptionFromMessage(
                              message,
                            );
                            final bool hasAlbum = albumUrls.isNotEmpty;
                            final messageId = message['id']?.toString() ?? '';

                            return AmicUpMessageMotion(
                              key: ValueKey(messageId),
                              animateEntrance: _arrivingMessageIds.contains(
                                messageId,
                              ),
                              visible: !_deletingMessageIds.contains(messageId),
                              ownMessage: isCurrentUser,
                              child: Align(
                                alignment: isCurrentUser
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: MessageInteraction(
                                  key: _messageLocator.keyFor(messageId),
                                  ownMessage: isCurrentUser,
                                  messageId: messageId,
                                  forwarded: message['is_forwarded'] == true,
                                  sentAt: DateTime.tryParse(
                                    message['created_at']?.toString() ?? '',
                                  ),
                                  highlighted: _messageLocator.highlighted,
                                  onOptions: () => _showMessageActions(message),
                                  onHeart: () => setState(
                                    () => toggleMessageReaction(
                                      _messageReactions,
                                      messageId,
                                      '❤️',
                                    ),
                                  ),
                                  onReply: () => _startReply(message),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width *
                                          0.78,
                                    ),
                                    child: Column(
                                      crossAxisAlignment: isCurrentUser
                                          ? CrossAxisAlignment.end
                                          : CrossAxisAlignment.start,
                                      children: [
                                        if (!isCurrentUser)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 8,
                                              bottom: 4,
                                            ),
                                            child: Text(
                                              senderName,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.of(
                                                  context,
                                                ).muted,
                                              ),
                                            ),
                                          ),
                                        if (hasAlbum)
                                          _buildAlbumBubble(
                                            urls: albumUrls,
                                            caption: caption,
                                            replyToId: message['reply_to_id']
                                                ?.toString(),
                                            isCurrentUser: isCurrentUser,
                                          )
                                        else
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration:
                                                AppTheme.chatBubbleDecoration(
                                                  context,
                                                  own: isCurrentUser,
                                                ),
                                            child: ReplyMessageText(
                                              content,
                                              onQuoteTap: () => _revealOriginal(
                                                content,
                                                message['reply_to_id']
                                                    ?.toString(),
                                              ),
                                              style: TextStyle(
                                                color: isCurrentUser
                                                    ? AppTheme.of(
                                                        context,
                                                      ).onAccent
                                                    : AppTheme.of(context).ink,
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
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
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
                        controller: _textController,
                        focusNode: _composerFocus,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                        onSubmitted: (_) => _sendTextMessage(),
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
                    valueListenable: _textController,
                    builder: (context, value, _) {
                      final canSend =
                          !_isSending &&
                          (value.text.trim().isNotEmpty ||
                              _attachedFiles.isNotEmpty);
                      return IconButton.filled(
                        tooltip: 'Send message',
                        onPressed: canSend ? _sendTextMessage : null,
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
