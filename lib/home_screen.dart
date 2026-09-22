import 'package:flutter/material.dart';
import 'camera_screen.dart';
import 'document_crop_service.dart';
import 'review_screen.dart';
import 'settings_screen.dart';
import 'temporary_contact_service.dart';
import 'temporary_contacts_screen.dart';
import 'contacts_writer_service.dart';

enum MenuDisplayMode { carousel, wheel }

/// The redesigned main dashboard / 1st page of Contact Scanner.
///
/// Refactored into a smooth rotating carousel / 3D wheel interface:
/// - No trailing chevron/arrow icons (>)
/// - Preserves all onTap routing, autoscan, temporary contacts, saved contacts, and settings logic
/// - Interactive rotating effect with PageView.builder (horizontal 3D carousel) and
///   ListWheelScrollView (vertical 3D wheel)
/// - Focus State: center item is scaled to 100% and fully opaque (1.0); off-center items
///   shrink and fade to emphasize 3D depth.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLaunchingScan = false;
  MenuDisplayMode _displayMode = MenuDisplayMode.carousel;

  // Page controller for horizontal 3D carousel
  late final PageController _pageController;
  int _currentCarouselIndex = 0;

  // Scroll controller for vertical 3D wheel
  late final FixedExtentScrollController _wheelController;
  int _currentWheelIndex = 0;

  @override
  void initState() {
    super.initState();
    TemporaryContactService().init();

    _pageController = PageController(
      initialPage: 0,
      viewportFraction: 0.82,
    );

    _wheelController = FixedExtentScrollController(initialItem: 0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _wheelController.dispose();
    super.dispose();
  }

  /// Directly launches the document autoscan with automatic edge detection and crop.
  Future<void> _startAutoScan() async {
    if (_isLaunchingScan) return;
    setState(() => _isLaunchingScan = true);

    try {
      final croppedFile = await DocumentCropService.scanAndCropDocument();

      if (!mounted) return;

      if (croppedFile != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ReviewScreen(imagePath: croppedFile.path),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Auto-scan notice: $e'),
          action: SnackBarAction(
            label: 'Open Camera',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const CameraScreen()),
              );
            },
          ),
          backgroundColor: const Color(0xFF1E2433),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLaunchingScan = false);
      }
    }
  }

  void _openSettingsScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
  }

  void _onCardTap(int index) {
    switch (index) {
      case 0:
        _startAutoScan();
        break;
      case 1:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const TemporaryContactsScreen(),
          ),
        );
        break;
      case 2:
        ContactsWriterService.openContactsApp();
        break;
      case 3:
        _openSettingsScreen();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1118),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.asset(
                          'assets/logo.png',
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                            Icons.contacts,
                            size: 32,
                            color: Color(0xFF00E5FF),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Contact Scanner',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Turn a handwritten contact sheet into phone contacts.',
                    style: TextStyle(
                      color: Color(0xFF8F97A6),
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Header Badges and Switcher Row
                  Row(
                    children: [
                      // Fully Offline Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B2335),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF2A3752),
                            width: 1.0,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_off_outlined,
                              color: Color(0xFF6C93D6),
                              size: 15,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Fully Offline',
                              style: TextStyle(
                                color: Color(0xFF6C93D6),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),

                      // Mode Switcher (Carousel / 3D Wheel)
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141822),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF242C3F), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildModeToggleItem(
                              icon: Icons.view_carousel_outlined,
                              mode: MenuDisplayMode.carousel,
                              tooltip: 'Horizontal Carousel',
                            ),
                            _buildModeToggleItem(
                              icon: Icons.view_day_outlined,
                              mode: MenuDisplayMode.wheel,
                              tooltip: 'Vertical 3D Wheel',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Rotating Interactive Menu Area
            Expanded(
              child: _displayMode == MenuDisplayMode.carousel
                  ? _buildHorizontalCarousel()
                  : _buildVerticalWheel(),
            ),

            // Bottom Area: Page Indicator (in carousel mode) + Fallback Camera
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_displayMode == MenuDisplayMode.carousel) ...[
                    _buildCarouselIndicators(),
                    const SizedBox(height: 8),
                  ],

                  // Fallback Camera Viewfinder Button
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const CameraScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.camera_alt_outlined,
                          size: 16, color: Color(0xFF6C93D6)),
                      label: const Text(
                        'Open Camera Viewfinder',
                        style: TextStyle(color: Color(0xFF6C93D6), fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact toggle icon button in the header
  Widget _buildModeToggleItem({
    required IconData icon,
    required MenuDisplayMode mode,
    required String tooltip,
  }) {
    final bool isSelected = _displayMode == mode;
    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          setState(() => _displayMode = mode);
        }
      },
      child: Tooltip(
        message: tooltip,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF2B3A5E) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            icon,
            size: 17,
            color: isSelected ? Colors.white : const Color(0xFF7E8A9E),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 1. HORIZONTAL 3D CAROUSEL (PageView.builder with scale, opacity & 3D tilt)
  // ===========================================================================
  Widget _buildHorizontalCarousel() {
    return PageView.builder(
      controller: _pageController,
      itemCount: 4,
      onPageChanged: (index) {
        setState(() => _currentCarouselIndex = index);
      },
      itemBuilder: (context, index) {
        return AnimatedBuilder(
          animation: _pageController,
          builder: (context, child) {
            double page = _currentCarouselIndex.toDouble();
            if (_pageController.position.haveDimensions &&
                _pageController.page != null) {
              page = _pageController.page!;
            }

            final double diff = index - page;
            final double dist = diff.abs().clamp(0.0, 1.0);

            // Center item is 1.0 (100% scale), scaling down to 0.86 as it moves away
            final double scale = 1.0 - (dist * 0.14);

            // Center item is 1.0 (fully opaque), fading down to 0.45 as it rotates away
            final double opacity = (1.0 - (dist * 0.55)).clamp(0.40, 1.0);

            // 3D cylindrical rotation matrix around Y axis
            final Matrix4 matrix = Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY(diff * -0.22)
              ..scaleByDouble(scale, scale, 1.0, 1.0);

            final bool isCenter = dist < 0.25;

            return Center(
              child: Transform(
                transform: matrix,
                alignment: Alignment.center,
                child: Opacity(
                  opacity: opacity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 12.0,
                    ),
                    child: _buildCarouselCard(
                      index: index,
                      isFocused: isCenter,
                      onTap: () {
                        if (!isCenter) {
                          _pageController.animateToPage(
                            index,
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                          );
                        }
                        _onCardTap(index);
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Builds a prominent showcase card for the horizontal 3D carousel.
  /// Strictly NO trailing chevron/arrow icons (>).
  Widget _buildCarouselCard({
    required int index,
    required bool isFocused,
    required VoidCallback onTap,
  }) {
    switch (index) {
      case 0:
        // Card 1: Scan Contact Sheet (Primary Indigo / Slate Card)
        return _buildShowcaseCard(
          isFocused: isFocused,
          isPrimary: true,
          gradient: const LinearGradient(
            colors: [Color(0xFF2B3A5E), Color(0xFF1E2840)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderColor: isFocused ? const Color(0xFF5B7DC4) : const Color(0xFF384B75),
          icon: Icons.document_scanner,
          badgeText: 'PRIMARY ACTION',
          badgeColor: const Color(0xFF435A88),
          badgeTextColor: const Color(0xFF9EC2FF),
          title: 'Scan Contact Sheet',
          subtitle: 'Photograph a page of names and numbers',
          actionText: _isLaunchingScan ? 'Launching Scanner...' : 'Start Autoscan',
          isLoading: _isLaunchingScan,
          onTap: onTap,
        );

      case 1:
        // Card 2: Temporary Contacts
        return ValueListenableBuilder<List<ScheduledContact>>(
          valueListenable: TemporaryContactService().activeContacts,
          builder: (context, activeList, _) {
            final int count = activeList.length;
            return _buildShowcaseCard(
              isFocused: isFocused,
              isPrimary: false,
              gradient: const LinearGradient(
                colors: [Color(0xFF171B26), Color(0xFF10131B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderColor: isFocused ? const Color(0xFF3E4F73) : const Color(0xFF232B3C),
              icon: Icons.timer_outlined,
              badgeText: count > 0 ? '$count ACTIVE' : 'AUTO-EXPIRE',
              badgeColor: count > 0 ? const Color(0xFF2D3C5C) : const Color(0xFF1B2130),
              badgeTextColor: count > 0 ? const Color(0xFF97BCFF) : const Color(0xFF7E8A9E),
              title: 'Temporary Contacts',
              subtitle: 'Contacts that expire automatically',
              actionText: 'Manage Temporary Contacts',
              onTap: onTap,
            );
          },
        );

      case 2:
        // Card 3: Saved Contacts
        return _buildShowcaseCard(
          isFocused: isFocused,
          isPrimary: false,
          gradient: const LinearGradient(
            colors: [Color(0xFF171B26), Color(0xFF10131B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderColor: isFocused ? const Color(0xFF3E4F73) : const Color(0xFF232B3C),
          icon: Icons.contacts_outlined,
          badgeText: 'SYSTEM ARCHIVE',
          badgeColor: const Color(0xFF1B2130),
          badgeTextColor: const Color(0xFF7E8A9E),
          title: 'Saved Contacts',
          subtitle: 'Everything this app has saved',
          actionText: 'Open Device Contacts',
          onTap: onTap,
        );

      case 3:
      default:
        // Card 4: Settings
        return _buildShowcaseCard(
          isFocused: isFocused,
          isPrimary: false,
          gradient: const LinearGradient(
            colors: [Color(0xFF171B26), Color(0xFF10131B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderColor: isFocused ? const Color(0xFF3E4F73) : const Color(0xFF232B3C),
          icon: Icons.settings_outlined,
          badgeText: 'PRIVACY & ABOUT',
          badgeColor: const Color(0xFF1B2130),
          badgeTextColor: const Color(0xFF7E8A9E),
          title: 'Settings',
          subtitle: 'Privacy, images and about',
          actionText: 'Open Settings',
          onTap: onTap,
        );
    }
  }

  /// Generates the individual showcase card container with rich aesthetics
  /// Strictly NO trailing chevron/arrow icons (>).
  Widget _buildShowcaseCard({
    required bool isFocused,
    required bool isPrimary,
    required Gradient gradient,
    required Color borderColor,
    required IconData icon,
    required String badgeText,
    required Color badgeColor,
    required Color badgeTextColor,
    required String title,
    required String subtitle,
    required String actionText,
    bool isLoading = false,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(24),
        splashColor: Colors.white10,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360, maxHeight: 370),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: borderColor,
              width: isFocused ? 1.8 : 1.0,
            ),
            boxShadow: isFocused
                ? [
                    BoxShadow(
                      color: isPrimary
                          ? const Color(0xFF2B3A5E).withValues(alpha: 0.45)
                          : const Color(0xFF141824).withValues(alpha: 0.6),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Icon Container + Category Badge (NO ARROW)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: isPrimary
                          ? Colors.white.withValues(alpha: 0.12)
                          : const Color(0xFF202738),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            icon,
                            color: isPrimary ? Colors.white : const Color(0xFF8FB7FF),
                            size: 28,
                          ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        color: badgeTextColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // Title
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),

              // Subtitle
              Text(
                subtitle,
                style: TextStyle(
                  color: isPrimary ? const Color(0xFFA7B9DC) : const Color(0xFF8F97A6),
                  fontSize: 14,
                  height: 1.35,
                ),
              ),

              const Spacer(),

              // Bottom Action Button / Pill (strictly NO arrows)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isPrimary
                      ? const Color(0xFF3F5585)
                      : const Color(0xFF1D2332),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isPrimary
                        ? const Color(0xFF5672AE)
                        : const Color(0xFF2B344B),
                    width: 1.0,
                  ),
                ),
                child: Center(
                  child: Text(
                    actionText,
                    style: TextStyle(
                      color: isPrimary ? Colors.white : const Color(0xFF8FB7FF),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
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

  /// Sleek dot indicators for the horizontal carousel
  Widget _buildCarouselIndicators() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final bool isSelected = _currentCarouselIndex == index;
        return GestureDetector(
          onTap: () {
            _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: isSelected ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF6C93D6) : const Color(0xFF283042),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }),
    );
  }

  // ===========================================================================
  // 2. VERTICAL 3D WHEEL (ListWheelScrollView with cylindrical perspective)
  // ===========================================================================
  Widget _buildVerticalWheel() {
    return Center(
      child: SizedBox(
        height: 480,
        child: ListWheelScrollView.useDelegate(
          controller: _wheelController,
          itemExtent: 116,
          physics: const FixedExtentScrollPhysics(),
          perspective: 0.003,
          diameterRatio: 2.0,
          useMagnifier: true,
          magnification: 1.06,
          overAndUnderCenterOpacity: 0.42,
          onSelectedItemChanged: (index) {
            setState(() => _currentWheelIndex = index % 4);
          },
          childDelegate: ListWheelChildLoopingListDelegate(
            children: [
              _buildWheelCardItem(0),
              _buildWheelCardItem(1),
              _buildWheelCardItem(2),
              _buildWheelCardItem(3),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a wide horizontal card item for the vertical 3D wheel.
  /// Strictly NO trailing chevron/arrow icons (>).
  Widget _buildWheelCardItem(int index) {
    final bool isCenter = _currentWheelIndex == index;

    switch (index) {
      case 0:
        return _buildWheelBar(
          index: 0,
          isFocused: isCenter,
          isPrimary: true,
          title: 'Scan Contact Sheet',
          subtitle: 'Photograph a page of names and numbers',
          icon: Icons.document_scanner,
          badgeText: null,
          isLoading: _isLaunchingScan,
          onTap: () => _onCardTap(0),
        );

      case 1:
        return ValueListenableBuilder<List<ScheduledContact>>(
          valueListenable: TemporaryContactService().activeContacts,
          builder: (context, activeList, _) {
            final int count = activeList.length;
            return _buildWheelBar(
              index: 1,
              isFocused: isCenter,
              isPrimary: false,
              title: 'Temporary Contacts',
              subtitle: 'Contacts that expire automatically',
              icon: Icons.timer_outlined,
              badgeText: count > 0 ? '$count active' : null,
              onTap: () => _onCardTap(1),
            );
          },
        );

      case 2:
        return _buildWheelBar(
          index: 2,
          isFocused: isCenter,
          isPrimary: false,
          title: 'Saved Contacts',
          subtitle: 'Everything this app has saved',
          icon: Icons.contacts_outlined,
          badgeText: null,
          onTap: () => _onCardTap(2),
        );

      case 3:
      default:
        return _buildWheelBar(
          index: 3,
          isFocused: isCenter,
          isPrimary: false,
          title: 'Settings',
          subtitle: 'Privacy, images and about',
          icon: Icons.settings_outlined,
          badgeText: null,
          onTap: () => _onCardTap(3),
        );
    }
  }

  /// Generates a single bar card inside the 3D vertical wheel.
  /// Strictly NO trailing chevron/arrow icons (>).
  Widget _buildWheelBar({
    required int index,
    required bool isFocused,
    required bool isPrimary,
    required String title,
    required String subtitle,
    required IconData icon,
    String? badgeText,
    bool isLoading = false,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 6.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading
              ? null
              : () {
                  if (!isFocused) {
                    _wheelController.animateToItem(
                      index,
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                    );
                  }
                  onTap();
                },
          borderRadius: BorderRadius.circular(18),
          splashColor: Colors.white10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: isPrimary
                  ? const Color(0xFF2B3A5E)
                  : (isFocused ? const Color(0xFF1A1F2C) : const Color(0xFF141720)),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isPrimary
                    ? (isFocused ? const Color(0xFF5B7DC4) : const Color(0xFF384B75))
                    : (isFocused ? const Color(0xFF3D4B68) : const Color(0xFF222837)),
                width: isFocused ? 1.5 : 1.0,
              ),
              boxShadow: isFocused
                  ? [
                      BoxShadow(
                        color: isPrimary
                            ? const Color(0xFF2B3A5E).withValues(alpha: 0.4)
                            : const Color(0xFF141720).withValues(alpha: 0.5),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                // Icon Box
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isPrimary
                        ? Colors.white.withValues(alpha: 0.1)
                        : const Color(0xFF1E2433),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          icon,
                          color: isPrimary ? Colors.white : const Color(0xFF8FB7FF),
                          size: 24,
                        ),
                ),
                const SizedBox(width: 14),

                // Title & Subtitle
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (badgeText != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2B3A5E),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFF3E5488),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                badgeText,
                                style: const TextStyle(
                                  color: Color(0xFF8FB7FF),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isPrimary
                              ? const Color(0xFFA7B9DC)
                              : const Color(0xFF788296),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Notice: Strictly NO trailing chevron/arrow icons (>)!
              ],
            ),
          ),
        ),
      ),
    );
  }
}

