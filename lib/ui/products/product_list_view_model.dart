import 'package:flutter/foundation.dart';

import '../../data/models/product.dart';
import '../../data/repositories/product_repository.dart';
import '../error_message.dart';

enum ProductListStatus { loading, success, empty, error }

class ProductListViewModel extends ChangeNotifier {
  ProductListViewModel({required this._repository, this.pageSize = 20});

  final ProductRepository _repository;
  final int pageSize;

  ProductListStatus _status = ProductListStatus.loading;
  ProductListStatus get status => _status;

  List<Product> _products = const [];
  List<Product> get products => _products;

  /// Full-screen error, set when [status] is [ProductListStatus.error].
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _hasMore = false;
  bool get hasMore => _hasMore;

  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;

  /// Error of the last "next page" request; shown inline at the list footer.
  String? _loadMoreError;
  String? get loadMoreError => _loadMoreError;

  /// Bumped whenever the list is reset, so an in-flight [loadMore] started
  /// before a refresh can't append stale items to the new list.
  int _generation = 0;
  bool _disposed = false;

  Future<void> loadInitial() async {
    _generation++;
    _status = ProductListStatus.loading;
    _errorMessage = null;
    _notify();

    try {
      _applyFirstPage(
        await _repository.fetchProducts(skip: 0, limit: pageSize),
      );
    } catch (e) {
      _products = const [];
      _isLoadingMore = false;
      _status = ProductListStatus.error;
      _errorMessage = errorMessageFor(e);
    }
    _notify();
  }

  /// Pull-to-refresh. Keeps the current items if the refresh fails and returns
  /// the error message so the view can show it non-intrusively (e.g. snackbar).
  Future<String?> refresh() async {
    if (_status != ProductListStatus.success) {
      await loadInitial();
      return null;
    }

    try {
      final page = await _repository.fetchProducts(skip: 0, limit: pageSize);
      // Only invalidate in-flight pagination once the list is really replaced;
      // a failed refresh leaves the current list (and its next page) intact.
      _generation++;
      _applyFirstPage(page);
      _notify();
      return null;
    } catch (e) {
      return errorMessageFor(e);
    }
  }

  Future<void> loadMore() async {
    if (_status != ProductListStatus.success || !_hasMore || _isLoadingMore) {
      return;
    }

    final generation = _generation;
    _isLoadingMore = true;
    _loadMoreError = null;
    _notify();

    ProductPage? page;
    Object? error;
    try {
      page = await _repository.fetchProducts(
        skip: _products.length,
        limit: pageSize,
      );
    } catch (e) {
      error = e;
    }
    // The list was reset while this request was in flight; drop the result.
    if (generation != _generation) return;

    if (page != null) {
      _products = [..._products, ...page.products];
      _hasMore = page.hasMore && page.products.isNotEmpty;
    } else {
      _loadMoreError = errorMessageFor(error!);
    }
    _isLoadingMore = false;
    _notify();
  }

  void _applyFirstPage(ProductPage page) {
    _products = page.products;
    _hasMore = page.hasMore;
    _loadMoreError = null;
    _isLoadingMore = false;
    _errorMessage = null;
    _status = page.products.isEmpty
        ? ProductListStatus.empty
        : ProductListStatus.success;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
