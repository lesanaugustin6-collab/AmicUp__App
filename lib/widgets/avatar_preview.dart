import 'package:flutter/material.dart';

Future<void> showAvatarPreview(BuildContext context, ImageProvider image) =>
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(alignment: Alignment.centerRight, child: IconButton(
              tooltip: 'Close photo', icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            )),
            AspectRatio(aspectRatio: 1, child: ClipOval(child: Image(
              image: image, fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Center(child: Text('Could not load photo')),
            ))),
          ]),
        ),
      ),
    );
