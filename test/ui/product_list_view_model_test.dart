import 'dart:async';

import 'package:dummy_shop/core/api_exception.dart';
import 'package:dummy_shop/data/models/product.dart';
import 'package:dummy_shop/ui/products/product_list_view_model.dart';
import 'package:fake_async/fake_async.dart';
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

  group('failed next page', () {
    // Page 1 (ids 1-2) is loaded; page 2 is at skip 2. Default retry delays
    // are 2s then 5s, so 3 consecutive failures exhaust automatic retries.
    var calls = 0;

    setUp(() async {
      calls = 0;
      stubPage(0, () => page(skip: 0, count: 2, total: 5));
      await viewModel.loadInitial();
    });

    void failNextPage() => stubPage(2, () {
      calls++;
      throw const ApiException('Timeout');
    });

    void succeedNextPage() => stubPage(2, () {
      calls++;
      return page(skip: 2, count: 2, total: 5);
    });

    test('schedules an automatic retry instead of showing an error', () {
      fakeAsync((async) {
        failNextPage();
        viewModel.loadMore();
        async.flushMicrotasks();

        expect(viewModel.isRetryScheduled, isTrue);
        expect(viewModel.loadMoreError, isNull);
        expect(viewModel.isLoadingMore, isFalse);
        expect(ids(), [1, 2]);
      });
    });

    test('scrolling while a retry is pending sends no requests', () {
      fakeAsync((async) {
        failNextPage();
        viewModel.loadMore();
        async.flushMicrotasks();

        for (var i = 0; i < 10; i++) {
          viewModel.loadMore();
        }
        async.flushMicrotasks();

        expect(calls, 1);
      });
    });

    test('retries after the delay and appends the page', () {
      fakeAsync((async) {
        failNextPage();
        viewModel.loadMore();
        async.flushMicrotasks();

        succeedNextPage();
        async.elapse(const Duration(seconds: 2));

        expect(ids(), [1, 2, 3, 4]);
        expect(viewModel.isRetryScheduled, isFalse);
        expect(calls, 2);
      });
    });

    test('waits longer before each retry', () {
      fakeAsync((async) {
        failNextPage();
        viewModel.loadMore();
        async.flushMicrotasks();

        async.elapse(const Duration(milliseconds: 1999));
        expect(calls, 1);
        async.elapse(const Duration(milliseconds: 1));
        expect(calls, 2);

        async.elapse(const Duration(milliseconds: 4999));
        expect(calls, 2);
        async.elapse(const Duration(milliseconds: 1));
        expect(calls, 3);
      });
    });

    test('shows Try again after all automatic retries fail', () {
      fakeAsync((async) {
        failNextPage();
        viewModel.loadMore();
        async.elapse(const Duration(seconds: 7));

        expect(calls, 3);
        expect(viewModel.loadMoreError, 'Timeout');
        expect(viewModel.isRetryScheduled, isFalse);
        expect(ids(), [1, 2]);

        // Neither scrolling nor time passing retries any more.
        for (var i = 0; i < 10; i++) {
          viewModel.loadMore();
        }
        async.elapse(const Duration(minutes: 1));
        expect(calls, 3);
      });
    });

    test('Try again loads immediately and restarts the retry cycle', () {
      fakeAsync((async) {
        failNextPage();
        viewModel.loadMore();
        async.elapse(const Duration(seconds: 7));

        viewModel.retryLoadMore();
        async.flushMicrotasks();
        expect(calls, 4);
        expect(viewModel.loadMoreError, isNull);
        expect(viewModel.isRetryScheduled, isTrue);

        succeedNextPage();
        async.elapse(const Duration(seconds: 2));
        expect(ids(), [1, 2, 3, 4]);
      });
    });

    test('Try again during a pending retry cancels the timer', () {
      fakeAsync((async) {
        failNextPage();
        viewModel.loadMore();
        async.flushMicrotasks();

        succeedNextPage();
        viewModel.retryLoadMore();
        async.elapse(const Duration(seconds: 10));

        expect(calls, 2);
        expect(ids(), [1, 2, 3, 4]);
      });
    });

    test('a successful refresh cancels a pending retry', () {
      fakeAsync((async) {
        failNextPage();
        viewModel.loadMore();
        async.flushMicrotasks();

        viewModel.refresh();
        async.flushMicrotasks();
        expect(viewModel.isRetryScheduled, isFalse);

        async.elapse(const Duration(seconds: 10));
        expect(calls, 1);
      });
    });

    test('dispose cancels a pending retry', () {
      fakeAsync((async) {
        failNextPage();
        viewModel.loadMore();
        async.flushMicrotasks();

        viewModel.dispose();
        async.elapse(const Duration(seconds: 10));

        expect(calls, 1);
      });
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
