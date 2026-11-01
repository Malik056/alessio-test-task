import 'package:flutter/material.dart';

/// Network image with loading placeholder and broken-image fallback.
class NetworkImageBox extends StatelessWidget {
  const NetworkImageBox(this.url, {super.key, this.fit = BoxFit.cover});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    final fallback = ColoredBox(
      color: color,
      child: const Center(child: Icon(Icons.image_not_supported_outlined)),
    );
    if (url.isEmpty) return fallback;

    return Image.network(
      url,
      fit: fit,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : ColoredBox(color: color),
      errorBuilder: (_, _, _) => fallback,
    );
  }
}
