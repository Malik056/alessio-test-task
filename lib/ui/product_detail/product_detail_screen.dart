import 'package:flutter/material.dart';

import '../../data/models/product.dart';
import '../widgets/network_image_box.dart';

/// Pure presentation: the list response already contains every field shown
/// here, so there is no extra request and no view model to manage.
class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.product});

  final Product product;

  static Route<void> route(Product product) =>
      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final images = product.images.isEmpty
        ? [product.thumbnail]
        : product.images;
    final hasDiscount = product.discountPercentage > 0;
    final originalPrice = hasDiscount
        ? product.price / (1 - product.discountPercentage / 100)
        : null;

    return Scaffold(
      appBar: AppBar(title: Text(product.title)),
      body: ListView(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Hero(
              tag: 'product-${product.id}',
              child: _ImageGallery(images: images),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.title, style: theme.textTheme.headlineSmall),
                if (product.brand != null) ...[
                  const SizedBox(height: 4),
                  Text(product.brand!, style: theme.textTheme.titleSmall),
                ],
                const SizedBox(height: 16),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 8,
                  children: [
                    Text(
                      '\$${product.price.toStringAsFixed(2)}',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    if (originalPrice != null) ...[
                      Text(
                        '\$${originalPrice.toStringAsFixed(2)}',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          decoration: TextDecoration.lineThrough,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      Text(
                        '-${product.discountPercentage.toStringAsFixed(0)}%',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.star, color: Colors.amber),
                      label: Text(product.rating.toStringAsFixed(1)),
                    ),
                    Chip(
                      avatar: const Icon(Icons.inventory_2_outlined),
                      label: Text(
                        product.stock > 0
                            ? '${product.stock} in stock'
                            : 'Out of stock',
                      ),
                    ),
                    Chip(label: Text(product.category)),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Description', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(product.description, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageGallery extends StatefulWidget {
  const _ImageGallery({required this.images});

  final List<String> images;

  @override
  State<_ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<_ImageGallery> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      children: [
        PageView.builder(
          itemCount: widget.images.length,
          onPageChanged: (page) => setState(() => _page = page),
          itemBuilder: (_, index) =>
              NetworkImageBox(widget.images[index], fit: BoxFit.contain),
        ),
        if (widget.images.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.images.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 16 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? colors.primary
                          : colors.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
