import 'package:flutter/material.dart';
import '../views/image_gallery_view.dart';

/// A photo stays tappable inside the message's long-press/reaction gestures.
class ChatPhotoThumbnail extends StatelessWidget {
  const ChatPhotoThumbnail({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });
  final List<String> images;
  final int initialIndex;
  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    final index = initialIndex.clamp(0, images.length - 1);
    return Semantics(
      label: 'Open photo ${index + 1} of ${images.length}',
      button: true,
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                ImageGalleryView(images: images, initialIndex: index),
          ),
        ),
        child: Image.network(
          images[index],
          fit: BoxFit.cover,
          cacheWidth: (240 * MediaQuery.devicePixelRatioOf(context))
              .round()
              .clamp(240, 720),
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.broken_image_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
