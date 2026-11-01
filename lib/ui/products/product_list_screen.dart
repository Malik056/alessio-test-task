import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/product.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../login/login_screen.dart';
import '../product_detail/product_detail_screen.dart';
import '../widgets/network_image_box.dart';
import '../widgets/status_view.dart';
import 'product_list_view_model.dart';

class ProductListScreen extends StatelessWidget {
  const ProductListScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const ProductListScreen());

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) =>
          ProductListViewModel(repository: context.read<ProductRepository>())
            ..loadInitial(),
      child: const ProductListView(),
    );
  }
}

/// Exposed (without the provider) so widget tests can inject a view model.
class ProductListView extends StatelessWidget {
  const ProductListView({super.key});

  Future<void> _logout(BuildContext context) async {
    await context.read<AuthRepository>().logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(LoginScreen.route(), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: const _ProductListBody(),
    );
  }
}

class _ProductListBody extends StatelessWidget {
  const _ProductListBody();

  Future<void> _onRefresh(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await context.read<ProductListViewModel>().refresh();
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ProductListViewModel>();

    final Widget content = switch (viewModel.status) {
      ProductListStatus.loading => const Center(
        child: CircularProgressIndicator(),
      ),
      ProductListStatus.error => StatusView(
        icon: Icons.cloud_off_outlined,
        message: viewModel.errorMessage ?? 'Something went wrong.',
        actionLabel: 'Retry',
        onAction: viewModel.loadInitial,
      ),
      ProductListStatus.empty => const StatusView(
        icon: Icons.inventory_2_outlined,
        message: 'No products found.',
      ),
      ProductListStatus.success => _ProductList(viewModel: viewModel),
    };

    if (viewModel.status == ProductListStatus.loading) return content;
    return RefreshIndicator(
      onRefresh: () => _onRefresh(context),
      child: content,
    );
  }
}

class _ProductList extends StatelessWidget {
  const _ProductList({required this.viewModel});

  final ProductListViewModel viewModel;

  bool _onScroll(ScrollNotification notification) {
    // Prefetch the next page shortly before the user hits the bottom.
    if (notification.metrics.extentAfter < 400) viewModel.loadMore();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final products = viewModel.products;
    final showFooter = viewModel.hasMore || viewModel.loadMoreError != null;

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: products.length + (showFooter ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 104),
        itemBuilder: (context, index) {
          if (index == products.length) {
            return _ListFooter(viewModel: viewModel);
          }
          final product = products[index];
          return ProductTile(
            product: product,
            onTap: () =>
                Navigator.of(context).push(ProductDetailScreen.route(product)),
          );
        },
      ),
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({required this.viewModel});

  final ProductListViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final error = viewModel.loadMoreError;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: error == null
            ? const CircularProgressIndicator()
            : Column(
                children: [
                  Text(error, textAlign: TextAlign.center),
                  TextButton(
                    onPressed: viewModel.loadMore,
                    child: const Text('Try again'),
                  ),
                ],
              ),
      ),
    );
  }
}

class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox.square(
                dimension: 72,
                child: Hero(
                  tag: 'product-${product.id}',
                  child: NetworkImageBox(product.thumbnail),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.brand ?? product.category,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '\$${product.price.toStringAsFixed(2)}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.star, size: 16, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(product.rating.toStringAsFixed(1)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
