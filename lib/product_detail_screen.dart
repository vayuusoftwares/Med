import 'package:flutter/material.dart';
import 'models/product.dart';
import 'widgets/product_image.dart';

class ProductDetailScreen extends StatefulWidget {
  final Product product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideIn;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideIn = Tween<Offset>(
      begin: const Offset(0.08, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape ||
            MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9F6),
      body: Stack(
        children: [
          // Background blobs
          _buildBg(),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(context, p),
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeIn,
                    child: isLandscape
                        ? _buildLandscape(p)
                        : _buildPortrait(p),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── App bar ─────────────────────────────────────────────────────────────────

  Widget _buildAppBar(BuildContext context, Product p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD1FAE5)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 17, color: Color(0xFF1E293B)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              p.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1B4332),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFD1FAE5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.star_rounded,
                    color: Color(0xFFF59E0B), size: 14),
                const SizedBox(width: 4),
                Text(
                  p.rating.toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1B4332),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Landscape (tablet / wide phone) ─────────────────────────────────────────

  Widget _buildLandscape(Product p) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Left: Image ──────────────────────────────────────────────────
          Expanded(
            flex: 5,
            child: _buildImagePanel(p),
          ),
          const SizedBox(width: 20),
          // ── Right: Details ───────────────────────────────────────────────
          Expanded(
            flex: 5,
            child: SlideTransition(
              position: _slideIn,
              child: _buildDetailsPanel(p),
            ),
          ),
        ],
      ),
    );
  }

  // ── Portrait (normal phone) ──────────────────────────────────────────────────

  Widget _buildPortrait(Product p) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildImagePanel(p),
          const SizedBox(height: 16),
          SlideTransition(
            position: _slideIn,
            child: _buildDetailsPanel(p),
          ),
        ],
      ),
    );
  }

  // ── Image panel ──────────────────────────────────────────────────────────────

  Widget _buildImagePanel(Product p) {
    return Container(
      height: 320,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00A86B).withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Soft green tint background (matches the image style)
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFE8F5E9),
                    Color(0xFFF1FFF7),
                  ],
                ),
              ),
            ),
            // Product image (supports SVG and PNG/JPG)
            ProductImage(
              imageUrl: p.imageUrl,
              fit: BoxFit.contain,
              iconSize: 80,
            ),
            // Bottom gradient fade
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.4),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Details panel ─────────────────────────────────────────────────────────────

  Widget _buildDetailsPanel(Product p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFD1FAE5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            p.category.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF065F46),
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Generic Name
        if (p.genericName.isNotEmpty) ...[
          Text(
            p.genericName,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0284C7),
            ),
          ),
          const SizedBox(height: 4),
        ],

        // Product name
        Text(
          p.name,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1B4332),
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),

        // Description
        Text(
          p.description,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF52796F),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),

        // Divider
        Container(height: 1, color: const Color(0xFFE2F0E8)),
        const SizedBox(height: 16),

        // Details rows
        _detailRow(Icons.science_rounded, 'Composition', p.composition.isEmpty ? 'Not specified' : p.composition),
        const SizedBox(height: 12),
        _detailRow(Icons.inventory_2_rounded, 'Pack Size', p.packSize),
        const SizedBox(height: 12),
        _detailRow(Icons.medication_rounded, 'Dosage', p.dosage),
        if (p.indications.isNotEmpty) ...[
          const SizedBox(height: 12),
          _detailRow(Icons.health_and_safety_rounded, 'Indications', p.indications),
        ],
        const SizedBox(height: 12),
        _detailRow(Icons.business_rounded, 'Company', 'MedSafe LifeScience'),
        const SizedBox(height: 20),

        // Price + rating row
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF00A86B).withValues(alpha: 0.08),
                const Color(0xFF52B788).withValues(alpha: 0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD1FAE5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Price',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF52796F),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.price > 0
                          ? '₹${p.price.toStringAsFixed(2)} / pack'
                          : 'Contact for pricing',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1B4332),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Rating',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF52796F),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          color: Color(0xFFF59E0B), size: 18),
                      const SizedBox(width: 3),
                      Text(
                        p.rating.toString(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1B4332),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Contact/Order button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A86B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
              shadowColor: const Color(0xFF00A86B).withValues(alpha: 0.4),
            ),
            icon: const Icon(Icons.shopping_cart_checkout_rounded, size: 20),
            label: const Text(
              'Order Now',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF00A86B),
              side: const BorderSide(color: Color(0xFF00A86B), width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.contact_support_rounded, size: 20),
            label: const Text(
              'Contact Representative',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: const Color(0xFFD1FAE5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: const Color(0xFF065F46)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF52796F),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF1E293B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBg() {
    return Positioned.fill(
      child: CustomPaint(painter: _BgPainter()),
    );
  }
}

class _BgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p1 = Paint()
      ..color = const Color(0xFF00A86B).withValues(alpha: 0.06);
    final p2 = Paint()
      ..color = const Color(0xFF52B788).withValues(alpha: 0.04);
    canvas.drawCircle(
        Offset(size.width * 0.9, size.height * 0.1), size.width * 0.4, p1);
    canvas.drawCircle(
        Offset(size.width * 0.05, size.height * 0.85), size.width * 0.35, p2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
