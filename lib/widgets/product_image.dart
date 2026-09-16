import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders either SVG or raster (PNG, JPG, WebP) product images from network URLs,
/// with animated loading spinners and graceful fallback to healthcare icons.
class ProductImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;
  final double iconSize;

  const ProductImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
    this.iconSize = 40,
  });

  @override
  Widget build(BuildContext context) {
    final cleanUrl = imageUrl.trim();
    if (cleanUrl.isEmpty) {
      return _buildFallback();
    }

    final isSvg = cleanUrl.toLowerCase().contains('.svg');

    if (isSvg) {
      return SvgPicture.network(
        cleanUrl,
        fit: fit,
        width: width,
        height: height,
        placeholderBuilder: (context) => _buildPlaceholder(),
        errorBuilder: (context, error, stackTrace) => _buildFallback(),
      );
    }

    return Image.network(
      cleanUrl,
      fit: fit,
      width: width,
      height: height,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _buildPlaceholder();
      },
      errorBuilder: (context, error, stackTrace) => _buildFallback(),
    );
  }

  Widget _buildPlaceholder() {
    if (placeholder != null) return placeholder!;
    return const Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Color(0xFF00A86B),
        ),
      ),
    );
  }

  Widget _buildFallback() {
    if (errorWidget != null) return errorWidget!;
    return Center(
      child: Icon(
        Icons.medical_services_rounded,
        size: iconSize,
        color: const Color(0xFF52B788),
      ),
    );
  }
}
