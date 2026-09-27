import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ProfileCardWidget extends StatefulWidget {
  const ProfileCardWidget({
    super.key,
    required this.name,
    required this.age,
    required this.imageUrl,
    required this.bio,
    this.imageUrls,
    this.isVerified = false,
    this.location,
    this.matchFeatures = const <String>[],
    this.matchPercent,
  });

  final String name;
  final int age;
  final String imageUrl;
  final String bio;
  final List<String>? imageUrls;
  final bool isVerified;
  final String? location;
  final List<String> matchFeatures;
  final int? matchPercent;

  @override
  State<ProfileCardWidget> createState() => _ProfileCardWidgetState();
}

class _ProfileCardWidgetState extends State<ProfileCardWidget> {
  late final PageController _pageController;
  int _activePhotoIndex = 0;

  List<String> _resolvePhotos() {
    final fromList =
        widget.imageUrls?.where((u) => u.trim().isNotEmpty).toList() ??
        <String>[];
    if (fromList.isNotEmpty) return fromList;
    if (widget.imageUrl.trim().isNotEmpty) {
      return <String>[widget.imageUrl.trim()];
    }
    return const <String>[''];
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void didUpdateWidget(covariant ProfileCardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldPhotos = oldWidget.imageUrls ?? <String>[oldWidget.imageUrl];
    final newPhotos = widget.imageUrls ?? <String>[widget.imageUrl];
    final photosChanged =
        oldPhotos.length != newPhotos.length ||
        oldWidget.imageUrl != widget.imageUrl ||
        oldPhotos.join('|') != newPhotos.join('|');

    if (photosChanged && _activePhotoIndex != 0) {
      _activePhotoIndex = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.jumpToPage(0);
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPhoto(int index, int totalPhotos) {
    if (totalPhotos <= 1) return;
    final bounded = index.clamp(0, totalPhotos - 1);
    if (bounded == _activePhotoIndex) return;

    _pageController.animateToPage(
      bounded,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final photos = _resolvePhotos();
    final hasPhotos = photos.isNotEmpty && photos.first.trim().isNotEmpty;

    final chips = <String>[
      if (widget.matchPercent != null) '🎯 ${widget.matchPercent}% Match',
      ...widget.matchFeatures,
    ].take(3).toList();
    const cardRadius = 16.0;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(cardRadius),
          boxShadow: [
            BoxShadow(
              color: AppTheme.of(context).ink.withValues(alpha: 0.16),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(cardRadius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = constraints.maxWidth;
                  final sideTapWidth = cardWidth * 0.45;

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      hasPhotos
                          ? PageView.builder(
                              controller: _pageController,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: photos.length,
                              onPageChanged: (index) {
                                setState(() {
                                  _activePhotoIndex = index.clamp(
                                    0,
                                    photos.length - 1,
                                  );
                                });
                              },
                              itemBuilder: (context, index) {
                                final url =
                                    photos[index.clamp(0, photos.length - 1)];
                                if (url.trim().isEmpty) {
                                  return Container(
                                    color: AppTheme.of(context).line,
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.person,
                                      size: 64,
                                      color: Colors.white,
                                    ),
                                  );
                                }

                                return Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) {
                                    return Container(
                                      color: AppTheme.of(context).line,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.person,
                                        size: 64,
                                        color: Colors.white,
                                      ),
                                    );
                                  },
                                );
                              },
                            )
                          : Container(
                              color: AppTheme.of(context).line,
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.person,
                                size: 64,
                                color: Colors.white,
                              ),
                            ),

                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: sideTapWidth,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () {
                            _goToPhoto(_activePhotoIndex - 1, photos.length);
                          },
                        ),
                      ),

                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: sideTapWidth,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () {
                            _goToPhoto(_activePhotoIndex + 1, photos.length);
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),

              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Row(
                  children: List.generate(photos.length, (index) {
                    final isActive = index == _activePhotoIndex;
                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.only(
                          right: index == photos.length - 1 ? 0 : 4,
                        ),
                        height: 4,
                        decoration: BoxDecoration(
                          color: isActive
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),

              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      widthFactor: 1,
                      heightFactor: 0.30,
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
                left: 16,
                right: 16,
                bottom: 74,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            '${widget.name}, ${widget.age}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 24,
                                  height: 1.1,
                                ),
                          ),
                        ),
                        if (widget.isVerified)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified_rounded,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Verified',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),

                    if (widget.location != null &&
                        widget.location!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 16,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              widget.location!.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 32,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: chips.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.25),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              chips[index],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],

                    if (widget.bio.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        widget.bio.trim(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.35,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
