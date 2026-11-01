import '../../core/api_client.dart';
import '../models/product.dart';

class ProductRepository {
  ProductRepository({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;

  /// Throws [ApiException] on failure.
  Future<ProductPage> fetchProducts({
    required int skip,
    required int limit,
  }) async {
    final json = await _api.get(
      '/products',
      query: {'skip': '$skip', 'limit': '$limit'},
    );
    return ProductPage.fromJson(json);
  }
}
