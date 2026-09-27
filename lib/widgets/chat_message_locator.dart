import 'dart:async';
import 'package:flutter/material.dart';

/// Locates lazy-built messages without assuming a fixed bubble height.
class ChatMessageLocator {
  final Map<String, GlobalKey> _keys = {};
  final highlighted = ValueNotifier<String?>(null);
  List<Map<String, dynamic>> messages = [];
  Timer? _timer;
  int _request = 0;
  bool _disposed = false;
  GlobalKey keyFor(String id) => _keys.putIfAbsent(id, () => GlobalKey());
  Rect? bounds(String id) {
    final box = _keys[id]?.currentContext?.findRenderObject();
    return box is RenderBox && box.attached
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
  }

  Future<bool> reveal(String id, ScrollController controller) async {
    final targetIndex = messages.indexWhere((m) => m['id']?.toString() == id);
    if (targetIndex < 0 || !controller.hasClients || _disposed) return false;
    final request = ++_request;
    // Each pass moves by a viewport until the lazy list builds the target.
    for (var step = 0; step <= messages.length + 1; step++) {
      if (_disposed || request != _request || !controller.hasClients) {
        return false;
      }
      final context = _keys[id]?.currentContext;
      if (context != null && context.mounted) {
        await Scrollable.ensureVisible(
          context,
          alignment: .5,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
        );
        if (_disposed || request != _request) return false;
        _timer?.cancel();
        highlighted.value = id;
        _timer = Timer(
          const Duration(seconds: 1),
          () => highlighted.value = null,
        );
        return true;
      }
      final built = <int>[];
      for (var i = 0; i < messages.length; i++) {
        if (_keys[messages[i]['id']?.toString()]?.currentContext != null) {
          built.add(i);
        }
      }
      final direction = built.isEmpty || targetIndex > built.last ? 1 : -1;
      final position = controller.position;
      final next =
          (position.pixels + direction * position.viewportDimension * .8).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          );
      if (next == position.pixels) return false;
      controller.jumpTo(next);
      await WidgetsBinding.instance.endOfFrame;
    }
    return false;
  }

  String? replyTarget(String text, String? storedId) {
    if (storedId != null && storedId.isNotEmpty) return storedId;
    // Old replies had only a text quote. Resolve only unambiguous matches.
    final end = text.indexOf('\n');
    if (!text.startsWith('↩ ') || end < 0) return null;
    final quote = text.substring(2, end);
    final matches = messages.where((m) => m['content'] == quote).toList();
    return matches.length == 1 ? matches.single['id']?.toString() : null;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    highlighted.dispose();
  }
}
