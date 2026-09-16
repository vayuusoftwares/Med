import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'product_list_screen.dart';

// ─── Data model ──────────────────────────────────────────────────────────────

class _CatalogCategory {
  final String name;
  final String subtitle;
  final Color accent;
  final IconData icon;
  final double bottleScale; // relative height factor

  const _CatalogCategory({
    required this.name,
    required this.subtitle,
    required this.accent,
    required this.icon,
    this.bottleScale = 1.0,
  });
}

const _categories = [
  _CatalogCategory(
    name: 'General',
    subtitle: 'General Products',
    accent: Color(0xFF0284C7),
    icon: Icons.medication_rounded,
    bottleScale: 0.82,
  ),
  _CatalogCategory(
    name: 'Orthopedic',
    subtitle: 'Ortho Care',
    accent: Color(0xFF6A1B9A),
    icon: Icons.accessibility_new_rounded,
    bottleScale: 1.0,
  ),
  _CatalogCategory(
    name: 'Gastroenterology',
    subtitle: 'Gastro Care',
    accent: Color(0xFF2E7D32),
    icon: Icons.medical_services_rounded,
    bottleScale: 0.80,
  ),
  _CatalogCategory(
    name: 'Neurology',
    subtitle: 'Neuro Care',
    accent: Color(0xFF1565C0),
    icon: Icons.psychology_rounded,
    bottleScale: 0.85,
  ),
  _CatalogCategory(
    name: 'Gynecology',
    subtitle: "Obstetrics & Gynaecology",
    accent: Color(0xFFAD1457),
    icon: Icons.favorite_rounded,
    bottleScale: 0.75,
  ),
  _CatalogCategory(
    name: 'All Products',
    subtitle: 'Full Catalog',
    accent: Color(0xFF00A86B),
    icon: Icons.grid_view_rounded,
    bottleScale: 0.88,
  ),
];

// ─── Screen ──────────────────────────────────────────────────────────────────

class ProductCatalogScreen extends StatefulWidget {
  final int initialCategory;
  const ProductCatalogScreen({super.key, this.initialCategory = 2});

  @override
  State<ProductCatalogScreen> createState() => _ProductCatalogScreenState();
}

class _ProductCatalogScreenState extends State<ProductCatalogScreen>
    with TickerProviderStateMixin {
  late final PageController _pageController;
  late int _currentPage;

  // Entry animation
  late final AnimationController _entryController;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;


  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialCategory;

    _pageController = PageController(
      viewportFraction: 0.55,
      initialPage: _currentPage,
    );

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _fadeIn = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pageController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9F6),
      body: Stack(
        children: [
          // ── Decorative background blobs ──
          _BackgroundBlobs(),

          // ── Main content ──
          SafeArea(
            child: FadeTransition(
              opacity: _fadeIn,
              child: SlideTransition(
                position: _slideUp,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTopBar(context),
                    const SizedBox(height: 8),
                    _buildHeading(),
                    const SizedBox(height: 4),
                    _buildSubHeading(),
                    const SizedBox(height: 28),
                    _buildCarousel(),
                    const SizedBox(height: 24),
                    _buildDots(),
                    const SizedBox(height: 28),
                    _buildCategoryChips(),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          _GlassButton(
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 18, color: Color(0xFF1E293B)),
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00A86B),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00A86B).withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.inventory_2_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          const Text(
            'MedSafe LifeScience',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  // ── Heading ───────────────────────────────────────────────────────────────

  Widget _buildHeading() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        'Product Catalog',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1B4332),
          letterSpacing: -0.5,
          height: 1.1,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildSubHeading() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        'Explore our pharmaceutical product lines across 6 medical specialties',
        style: TextStyle(
          fontSize: 13,
          color: Color(0xFF52796F),
          height: 1.4,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ── Carousel ──────────────────────────────────────────────────────────────

  Widget _buildCarousel() {
    return SizedBox(
      height: 280,
      child: PageView.builder(
        controller: _pageController,
        itemCount: _categories.length,
        onPageChanged: (i) => setState(() => _currentPage = i),
        itemBuilder: (context, index) {
          return AnimatedBuilder(
            animation: _pageController,
            builder: (context, child) {
              double page = _currentPage.toDouble();
              try {
                page = _pageController.page ?? _currentPage.toDouble();
              } catch (_) {}

              final diff = (index - page).abs();
              final scale = (1.0 - diff * 0.12).clamp(0.78, 1.0);
              final opacity = (1.0 - diff * 0.35).clamp(0.45, 1.0);

              return Transform.scale(
                scale: scale,
                alignment: Alignment.bottomCenter,
                child: Opacity(
                  opacity: opacity,
                  child: child,
                ),
              );
            },
            child: GestureDetector(
              onTap: () {
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                );
                _showCategoryDetail(context, _categories[index]);
              },
              child: _BottleCard(
                category: _categories[index],
                isSelected: _currentPage == index,
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Dots ──────────────────────────────────────────────────────────────────

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_categories.length, (i) {
        final selected = i == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: selected ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: selected
                ? _categories[_currentPage].accent
                : const Color(0xFFB7E4C7),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ── Category chips ────────────────────────────────────────────────────────

  Widget _buildCategoryChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: List.generate(_categories.length, (i) {
          final cat = _categories[i];
          final selected = i == _currentPage;
          return GestureDetector(
            onTap: () {
              _pageController.animateToPage(
                i,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
              );
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: selected
                    ? cat.accent
                    : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? cat.accent : const Color(0xFFD1FAE5),
                  width: 1.5,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: cat.accent.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        )
                      ]
                    : [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(cat.icon,
                      size: 14,
                      color: selected ? Colors.white : cat.accent),
                  const SizedBox(width: 6),
                  Text(
                    cat.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : const Color(0xFF1B4332),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Category detail bottom sheet ──────────────────────────────────────────

  void _showCategoryDetail(BuildContext context, _CatalogCategory cat) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProductListScreen(categoryName: cat.name),
      ),
    );
  }
}

// ─── Bottle card ─────────────────────────────────────────────────────────────

class _BottleCard extends StatefulWidget {
  final _CatalogCategory category;
  final bool isSelected;

  const _BottleCard({required this.category, required this.isSelected});

  @override
  State<_BottleCard> createState() => _BottleCardState();
}

class _BottleCardState extends State<_BottleCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;
    final bottleH = 160.0 * cat.bottleScale;
    final bottleW = bottleH * 0.55;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              cat.accent.withValues(alpha: 0.06),
            ],
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: widget.isSelected
                ? cat.accent.withValues(alpha: 0.5)
                : const Color(0xFFE2F0E8),
            width: widget.isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.isSelected
                  ? cat.accent.withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: 0.07),
              blurRadius: widget.isSelected ? 20 : 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            // Bottle illustration
            _PharmaceuticalBottle(
              width: bottleW,
              height: bottleH,
              color: cat.accent,
              icon: cat.icon,
              shimmerController: _shimmerController,
            ),
            const SizedBox(height: 16),
            // Category name
            Text(
              cat.name,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: cat.accent,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'PRODUCT',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
                color: const Color(0xFF52796F).withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}

// ─── Pharmaceutical bottle painter ───────────────────────────────────────────

class _PharmaceuticalBottle extends StatelessWidget {
  final double width;
  final double height;
  final Color color;
  final IconData icon;
  final AnimationController shimmerController;

  const _PharmaceuticalBottle({
    required this.width,
    required this.height,
    required this.color,
    required this.icon,
    required this.shimmerController,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shimmerController,
      builder: (context, _) {
        return CustomPaint(
          size: Size(width, height),
          painter: _BottlePainter(
            accentColor: color,
            shimmerProgress: shimmerController.value,
          ),
          child: SizedBox(
            width: width,
            height: height,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: height * 0.12),
                Icon(icon,
                    color: color.withValues(alpha: 0.85),
                    size: width * 0.45),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BottlePainter extends CustomPainter {
  final Color accentColor;
  final double shimmerProgress;

  _BottlePainter({required this.accentColor, required this.shimmerProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFF0F0F0),
          const Color(0xFFE0E0E0),
          const Color(0xFFF5F5F5),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.1)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    // Cap dimensions
    final capW = w * 0.6;
    final capH = h * 0.14;
    final capLeft = (w - capW) / 2;

    // Body dimensions
    final bodyTop = capH + h * 0.03;
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, bodyTop, w, h - bodyTop),
      Radius.circular(w * 0.18),
    );

    // Shadow
    canvas.drawRRect(
      bodyRect.shift(const Offset(3, 5)),
      shadowPaint,
    );

    // Bottle body
    canvas.drawRRect(bodyRect, bodyPaint);

    // Highlight strip on left side
    final highlightPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.white.withValues(alpha: 0.7),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, bodyTop, w * 0.3, h - bodyTop));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.06, bodyTop + 8, w * 0.15, h - bodyTop - 16),
        Radius.circular(w * 0.08),
      ),
      highlightPaint,
    );

    // Shimmer sweep
    final shimmerAngle = shimmerProgress * math.pi * 2;
    final shimmerPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment(math.cos(shimmerAngle), math.sin(shimmerAngle)),
        end: Alignment(-math.cos(shimmerAngle), -math.sin(shimmerAngle)),
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, bodyTop, w, h - bodyTop));
    canvas.drawRRect(bodyRect, shimmerPaint);

    // Label band
    final labelTop = bodyTop + h * 0.28;
    final labelH = h * 0.3;
    final labelPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.04, labelTop, w * 0.92, labelH),
        Radius.circular(w * 0.08),
      ),
      labelPaint,
    );

    // Cap shadow
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(capLeft + 2, 4, capW, capH),
        Radius.circular(capH * 0.4),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Cap
    final capGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        accentColor.withValues(alpha: 0.9),
        accentColor,
        accentColor.withValues(alpha: 0.7),
      ],
    ).createShader(Rect.fromLTWH(capLeft, 0, capW, capH));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(capLeft, 0, capW, capH),
        Radius.circular(capH * 0.4),
      ),
      Paint()..shader = capGradient,
    );

    // Cap highlight
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(capLeft + capW * 0.1, 2, capW * 0.3, capH * 0.35),
        Radius.circular(capH * 0.2),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );

    // Neck ring
    final neckPaint = Paint()
      ..color = const Color(0xFFD0D0D0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(capLeft - 4, capH + 1),
      Offset(capLeft + capW + 4, capH + 1),
      neckPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BottlePainter old) =>
      old.shimmerProgress != shimmerProgress || old.accentColor != accentColor;
}

// ─── Background blobs ─────────────────────────────────────────────────────────

class _BackgroundBlobs extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(painter: _BlobPainter()),
    );
  }
}

class _BlobPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p1 = Paint()
      ..color = const Color(0xFF00A86B).withValues(alpha: 0.07);
    final p2 = Paint()
      ..color = const Color(0xFF52B788).withValues(alpha: 0.05);

    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.12),
        size.width * 0.45, p1);
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.8),
        size.width * 0.4, p2);
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 1.0),
        size.width * 0.35, p1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── Glass button ─────────────────────────────────────────────────────────────

class _GlassButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  const _GlassButton({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD1FAE5), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(child: child),
      ),
    );
  }
}

