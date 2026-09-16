import 'package:flutter/material.dart';
import 'models/product.dart';
import 'data/product_data.dart';
import 'product_detail_screen.dart';
import 'widgets/product_image.dart';

class ProductListScreen extends StatefulWidget {
  final String categoryName;

  const ProductListScreen({super.key, required this.categoryName});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  late List<Product> _allProducts;
  late List<Product> _filtered;
  String _sortOption = 'Default sorting';
  final TextEditingController _searchCtrl = TextEditingController();

  final List<String> _sortOptions = [
    'Default sorting',
    'Sort by popularity',
    'Sort by latest',
    'Sort by price: low to high',
    'Sort by price: high to low',
    'Sort by rating',
  ];

  @override
  void initState() {
    super.initState();
    _allProducts = ProductData.getProductsByCategory(widget.categoryName);
    _filtered = List.from(_allProducts);
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filtered = _allProducts
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.genericName.toLowerCase().contains(q) ||
              p.composition.toLowerCase().contains(q) ||
              p.indications.toLowerCase().contains(q) ||
              p.description.toLowerCase().contains(q))
          .toList();
      _applySortToList(_filtered);
    });
  }

  void _applySortToList(List<Product> list) {
    switch (_sortOption) {
      case 'Sort by price: low to high':
        list.sort((a, b) => a.price.compareTo(b.price));
        break;
      case 'Sort by price: high to low':
        list.sort((a, b) => b.price.compareTo(a.price));
        break;
      case 'Sort by rating':
        list.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case 'Sort by popularity':
      case 'Sort by latest':
      case 'Default sorting':
      default:
        list.sort((a, b) => a.name.compareTo(b.name));
    }
  }

  void _applySort() {
    setState(() => _applySortToList(_filtered));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3FAF5),
      body: Stack(
        children: [
          _BackgroundBlobs(),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(context),
                const SizedBox(height: 8),
                _buildSearchAndSort(),
                const SizedBox(height: 8),
                _buildResultCount(),
                const SizedBox(height: 4),
                Expanded(child: _buildGrid()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          _GlassBtn(
            icon: Icons.arrow_back_ios_new_rounded,
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
                  color: const Color(0xFF00A86B).withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.inventory_2_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.categoryName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1B4332),
                ),
              ),
              const Text(
                'MedSafe LifeScience',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF52796F),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Search + Sort ─────────────────────────────────────────────────────────────

  Widget _buildSearchAndSort() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Search bar
          Expanded(
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(23),
                border: Border.all(color: const Color(0xFFD1FAE5)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => _onSearch(),
                style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
                decoration: const InputDecoration(
                  hintText: 'Search for medicines...',
                  hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: Color(0xFF52796F), size: 20),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Sort dropdown
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(23),
              border: Border.all(color: const Color(0xFFD1FAE5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _sortOption,
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 18, color: Color(0xFF52796F)),
                style: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _sortOption = v);
                    _applySort();
                  }
                },
                items: _sortOptions
                    .map((s) => DropdownMenuItem<String>(
                          value: s,
                          child: Text(s),
                        ))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Result count ──────────────────────────────────────────────────────────────

  Widget _buildResultCount() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(
            'Showing ${_filtered.length} result${_filtered.length != 1 ? 's' : ''}',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF52796F),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Grid ──────────────────────────────────────────────────────────────────────

  Widget _buildGrid() {
    if (_filtered.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 56, color: Color(0xFFB7E4C7)),
            SizedBox(height: 12),
            Text(
              'No medicines found',
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF52796F),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.68,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: _filtered.length,
      itemBuilder: (context, i) => _MedicineCard(
        product: _filtered[i],
        onTap: () {
          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (_, anim, __) =>
                  ProductDetailScreen(product: _filtered[i]),
              transitionsBuilder: (_, anim, __, child) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.05, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: anim, curve: Curves.easeOut),
                  ),
                  child: child,
                ),
              ),
              transitionDuration: const Duration(milliseconds: 400),
            ),
          );
        },
      ),
    );
  }
}

// ─── Medicine Card ────────────────────────────────────────────────────────────

class _MedicineCard extends StatefulWidget {
  final Product product;
  final VoidCallback onTap;

  const _MedicineCard({required this.product, required this.onTap});

  @override
  State<_MedicineCard> createState() => _MedicineCardState();
}

class _MedicineCardState extends State<_MedicineCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.product;

    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: _hovered
                    ? const Color(0xFF00A86B).withValues(alpha: 0.18)
                    : Colors.black.withValues(alpha: 0.07),
                blurRadius: _hovered ? 20 : 12,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: _hovered
                  ? const Color(0xFF00A86B).withValues(alpha: 0.4)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Image area with green tint ──────────────────────────────
              Expanded(
                flex: 5,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Mint-green gradient background (matching screenshot)
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFFDDF3E8),
                              Color(0xFFF0FAF5),
                            ],
                          ),
                        ),
                      ),
                      // Product image (supports SVG and PNG/JPG)
                      ProductImage(
                        imageUrl: p.imageUrl,
                        fit: BoxFit.contain,
                        iconSize: 40,
                      ),
                      // "More Details" badge on hover
                      if (_hovered)
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00A86B),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'More Details',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── Text area ───────────────────────────────────────────────
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      Text(
                        p.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Color(0xFF1E293B),
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      // Composition / Generic Name
                      Text(
                        p.composition.isNotEmpty
                            ? p.composition
                            : (p.genericName.isNotEmpty ? p.genericName : p.description),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF64748B),
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      // Pack Size + Rating row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              p.packSize,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0284C7),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded,
                                  color: Color(0xFFF59E0B), size: 13),
                              const SizedBox(width: 2),
                              Text(
                                p.rating.toString(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Reusable widgets ─────────────────────────────────────────────────────────

class _GlassBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassBtn({required this.icon, required this.onTap});

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
          border: Border.all(color: const Color(0xFFD1FAE5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(child: Icon(icon, size: 18, color: const Color(0xFF1E293B))),
      ),
    );
  }
}

class _BackgroundBlobs extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(child: CustomPaint(painter: _BlobPainter()));
  }
}

class _BlobPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p1 = Paint()
      ..color = const Color(0xFF00A86B).withValues(alpha: 0.06);
    final p2 = Paint()
      ..color = const Color(0xFF52B788).withValues(alpha: 0.04);
    canvas.drawCircle(
        Offset(size.width * 0.88, size.height * 0.1), size.width * 0.42, p1);
    canvas.drawCircle(
        Offset(size.width * 0.08, size.height * 0.82), size.width * 0.38, p2);
    canvas.drawCircle(
        Offset(size.width * 0.5, size.height * 1.0), size.width * 0.3, p1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}
