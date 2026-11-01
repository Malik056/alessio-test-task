class Product {
  const Product({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.price,
    required this.discountPercentage,
    required this.rating,
    required this.stock,
    required this.thumbnail,
    required this.images,
    this.brand,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id'] as int,
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    category: json['category'] as String? ?? '',
    price: (json['price'] as num? ?? 0).toDouble(),
    discountPercentage: (json['discountPercentage'] as num? ?? 0).toDouble(),
    rating: (json['rating'] as num? ?? 0).toDouble(),
    stock: json['stock'] as int? ?? 0,
    // Some products (e.g. groceries) have no brand.
    brand: json['brand'] as String?,
    thumbnail: json['thumbnail'] as String? ?? '',
    images: (json['images'] as List<dynamic>? ?? const [])
        .cast<String>()
        .toList(growable: false),
  );

  final int id;
  final String title;
  final String description;
  final String category;
  final double price;
  final double discountPercentage;
  final double rating;
  final int stock;
  final String? brand;
  final String thumbnail;
  final List<String> images;

  @override
  bool operator ==(Object other) => other is Product && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// One page of the `/products` endpoint.
class ProductPage {
  const ProductPage({
    required this.products,
    required this.total,
    required this.skip,
    required this.limit,
  });

  factory ProductPage.fromJson(Map<String, dynamic> json) => ProductPage(
    products: (json['products'] as List<dynamic>)
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList(growable: false),
    total: json['total'] as int,
    skip: json['skip'] as int,
    limit: json['limit'] as int,
  );

  final List<Product> products;
  final int total;
  final int skip;
  final int limit;

  bool get hasMore => skip + products.length < total;
}
