import 'dart:async';

import 'package:dummy_shop/core/api_exception.dart';
import 'package:dummy_shop/data/models/product.dart';
import 'package:dummy_shop/ui/products/product_list_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/fixtures.dart';

void main() {
  const pageSize = 2;
  late MockProductRepository repository;
  late ProductListViewModel viewModel;

  void stubPage(int skip, FutureOr<ProductPage> Function() answer) {
    when(() => repository.fetchProducts(skip: skip, limit: pageSize))
        .thenAnswer((_) async => answer());
  }

  List<int> ids() => viewModel.products.map((p) => p.id).toList();

  setUp(() {
    repository = MockProductRepository();
    viewModel = ProductListViewModel(
      repository: repository,
      pageSize: pageSize,
    );
  });

  group('loadInitial', () {
    test('starts in loading state', () {
      expect(viewModel.status, ProductListStatus.loading);
    });

    test('loads the first page', () async {
      stubPage(0, () => page(skip: 0, count: 2, total: 5));

      await viewModel.loadInitial();

      expect(viewModel.status, ProductListStatus.success);
      expect(ids(), [1, 2]);
      expect(viewModel.hasMore, isTrue);
    });

    test('emits empty state when there are no products', () async {
      stubPage(0, () => page(skip: 0, count: 0, total: 0));

      await viewModel.loadInitial();

      expect(viewModel.status, ProductListStatus.empty);
      expect(viewModel.hasMore, isFalse);
    });

    test('emits error state with the message on failure', () async {
      stubPage(0, () => throw const ApiException('No internet'));

      await viewModel.loadInitial();

      expect(viewModel.status, ProductListStatus.error);
      expect(viewModel.errorMessage, 'No internet');
    });

    test('retry after an error recovers', () async {
      stubPage(0, () => throw const ApiException('No internet'));
      await viewModel.loadInitial();

      stubPage(0, () => page(skip: 0, count: 2, total: 2));
      await viewModel.loadInitial();

      expect(viewModel.status, ProductListStatus.success);
      expect(viewModel.errorMessage, isNull);
    });
  });

  group('loadMore', () {
    setUp(() async {
      stubPage(0, () => page(skip: 0, count: 2, total: 5));
      await viewModel.loadInitial();
    });

    test('appends the next page using the current length as skip', () async {
      stubPage(2, () => page(skip: 2, count: 2, total: 5));

      await viewModel.loadMore();

      expect(ids(), [1, 2, 3, 4]);
      expect(viewModel.hasMore, isTrue);
      expect(viewModel.isLoadingMore, isFalse);
    });

    test('stops when the last page is reached', () async {
      stubPage(2, () => page(skip: 2, count: 2, total: 5));
      stubPage(4, () => page(skip: 4, count: 1, total: 5));

      await viewModel.loadMore();
      await viewModel.loadMore();
      await viewModel.loadMore(); // no-op

      expect(ids(), [1, 2, 3, 4, 5]);
      expect(viewModel.hasMore, isFalse);
      verify(() => repository.fetchProducts(skip: 4, limit: pageSize))
          .called(1);
      verifyNever(() => repository.fetchProducts(skip: 5, limit: pageSize));
    });

    test('ignores calls while a page is already loading', () async {
      final completer = Completer<ProductPage>();
      stubPage(2, () => completer.future);

      final first = viewModel.loadMore();
      expect(viewModel.isLoadingMore, isTrue);
      await viewModel.loadMore();
      completer.complete(page(skip: 2, count: 2, total: 5));
      await first;

      verify(() => repository.fetchProducts(skip: 2, limit: pageSize))
          .called(1);
      expect(ids(), [1, 2, 3, 4]);
    });

    test('keeps loaded items and exposes an inline error on failure', () async {
      stubPage(2, () => throw const ApiException('Timeout'));

      await viewModel.loadMore();

      expect(viewModel.status, ProductListStatus.success);
      expect(ids(), [1, 2]);
      expect(viewModel.loadMoreError, 'Timeout');
      expect(viewModel.isLoadingMore, isFalse);

      stubPage(2, () => page(skip: 2, count: 2, total: 5));
      await viewModel.loadMore();

      expect(viewModel.loadMoreError, isNull);
      expect(ids(), [1, 2, 3, 4]);
    });

    test('does nothing when the list is not in success state', () async {
      stubPage(0, () => throw const ApiException('x'));
      await viewModel.loadInitial();
      clearInteractions(repository);

      await viewModel.loadMore();

      verifyNever(
        () => repository.fetchProducts(
          skip: any(named: 'skip'),
          limit: any(named: 'limit'),
        ),
      );
    });
  });

  group('refresh', () {
    setUp(() async {
      stubPage(0, () => page(skip: 0, count: 2, total: 5));
      await viewModel.loadInitial();
      stubPage(2, () => page(skip: 2, count: 2, total: 5));
      await viewModel.loadMore();
    });

    test('replaces the list with a fresh first page', () async {
      stubPage(0, () => page(skip: 0, count: 2, total: 3));

      final error = await viewModel.refresh();

      expect(error, isNull);
      expect(ids(), [1, 2]);
      expect(viewModel.hasMore, isTrue);
    });

    test('keeps current items and returns the error on failure', () async {
      stubPage(0, () => throw const ApiException('Offline'));

      final error = await viewModel.refresh();

      expect(error, 'Offline');
      expect(viewModel.status, ProductListStatus.success);
      expect(ids(), [1, 2, 3, 4]);
    });

    test(
      'discards a next page that was in flight before the refresh',
      () async {
        final pending = Completer<ProductPage>();
        stubPage(4, () => pending.future);
        final loadMore = viewModel.loadMore();

        stubPage(0, () => page(skip: 0, count: 2, total: 5));
        await viewModel.refresh();
        pending.complete(page(skip: 4, count: 1, total: 5));
        await loadMore;

        expect(ids(), [1, 2]);
        expect(viewModel.isLoadingMore, isFalse);
      },
    );

    test('a failed refresh lets an in-flight next page finish', () async {
      final pending = Completer<ProductPage>();
      stubPage(4, () => pending.future);
      final loadMore = viewModel.loadMore();

      stubPage(0, () => throw const ApiException('Offline'));
      await viewModel.refresh();
      pending.complete(page(skip: 4, count: 1, total: 5));
      await loadMore;

      expect(ids(), [1, 2, 3, 4, 5]);
      expect(viewModel.isLoadingMore, isFalse);
    });

    test('from the error state performs a full reload', () async {
      stubPage(0, () => throw const ApiException('x'));
      await viewModel.loadInitial();

      stubPage(0, () => page(skip: 0, count: 2, total: 2));
      final error = await viewModel.refresh();

      expect(error, isNull);
      expect(viewModel.status, ProductListStatus.success);
    });
  });

  test('does not notify after dispose', () async {
    final pending = Completer<ProductPage>();
    stubPage(0, () => pending.future);
    final load = viewModel.loadInitial();

    viewModel.dispose();
    pending.complete(page(skip: 0, count: 2, total: 2));

    await expectLater(load, completes);
  });
}
