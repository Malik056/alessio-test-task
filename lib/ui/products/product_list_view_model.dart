import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/product.dart';
import '../../data/repositories/product_repository.dart';
import '../error_message.dart';

enum ProductListStatus { loading, success, empty, error }

class ProductListViewModel extends ChangeNotifier {
  ProductListViewModel({
    required this._repository,
    this.pageSize = 20,
    this.retryDelays = const [Duration(seconds: 2), Duration(seconds: 5)],
  });

  final ProductRepository _repository;
  final int pageSize;

  /// Waits before each automatic retry of a failed next page. Once these are
  /// used up, [loadMoreError] is set and only [retryLoadMore] tries again.
  final List<Duration> retryDelays;

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

  /// Set once automatic retries are exhausted; the footer then shows it with
  /// a "Try again" button.
  String? _loadMoreError;
  String? get loadMoreError => _loadMoreError;

  Timer? _retryTimer;

  /// A failed next page is waiting to be retried automatically.
  bool get isRetryScheduled => _retryTimer != null;

  int _consecutiveFailures = 0;

  /// Bumped whenever the list is reset, so an in-flight [loadMore] started
  /// before a refresh can't append stale items to the new list.
  int _generation = 0;
  bool _disposed = false;

  Future<void> loadInitial() async {
    _generation++;
    _resetPagination();
    _status = ProductListStatus.loading;
    _errorMessage = null;
    _notify();

    try {
      _applyFirstPage(
        await _repository.fetchProducts(skip: 0, limit: pageSize),
      );
    } catch (e) {
      _products = const [];
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

  /// Scroll-triggered. Never retries a failed page: that is left to the
  /// retry timer or the "Try again" button, so scrolling while offline can't
  /// flood the network.
  Future<void> loadMore() async {
    if (!_canLoadMore || isRetryScheduled || _loadMoreError != null) return;
    await _loadNextPage();
  }

  /// "Try again" button: loads immediately and restarts the retry cycle.
  Future<void> retryLoadMore() async {
    if (!_canLoadMore) return;
    _cancelRetry();
    _consecutiveFailures = 0;
    await _loadNextPage();
  }

  bool get _canLoadMore =>
      _status == ProductListStatus.success && _hasMore && !_isLoadingMore;

  Future<void> _loadNextPage() async {
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
      _consecutiveFailures = 0;
    } else if (_consecutiveFailures < retryDelays.length) {
      _retryTimer = Timer(retryDelays[_consecutiveFailures++], () {
        _retryTimer = null;
        _loadNextPage();
      });
    } else {
      _loadMoreError = errorMessageFor(error!);
    }
    _isLoadingMore = false;
    _notify();
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _resetPagination() {
    _cancelRetry();
    _consecutiveFailures = 0;
    _loadMoreError = null;
    _isLoadingMore = false;
  }

  void _applyFirstPage(ProductPage page) {
    _resetPagination();
    _products = page.products;
    _hasMore = page.hasMore;
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
    _cancelRetry();
    super.dispose();
  }
}
