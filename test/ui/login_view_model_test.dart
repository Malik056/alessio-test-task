import 'dart:async';

import 'package:dummy_shop/core/api_exception.dart';
import 'package:dummy_shop/data/models/user.dart';
import 'package:dummy_shop/ui/login/login_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/fixtures.dart';

void main() {
  late MockAuthRepository repository;
  late LoginViewModel viewModel;

  const user = User(
    id: 1,
    username: 'emilys',
    firstName: 'Emily',
    lastName: 'Johnson',
    email: '',
    image: '',
  );

  setUp(() {
    repository = MockAuthRepository();
    viewModel = LoginViewModel(repository: repository);
  });

  test('succeeds and trims the username', () async {
    when(() => repository.login(username: 'emilys', password: 'emilyspass'))
        .thenAnswer((_) async => user);

    final result = await viewModel.login('  emilys ', 'emilyspass');

    expect(result, isTrue);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.isLoading, isFalse);
  });

  test('exposes loading state while the request is in flight', () async {
    final completer = Completer<User>();
    when(
      () => repository.login(
        username: any(named: 'username'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) => completer.future);

    final future = viewModel.login('emilys', 'emilyspass');
    expect(viewModel.isLoading, isTrue);

    completer.complete(user);
    await future;
    expect(viewModel.isLoading, isFalse);
  });

  test('shows the API error message on failure', () async {
    when(
      () => repository.login(
        username: any(named: 'username'),
        password: any(named: 'password'),
      ),
    ).thenThrow(const ApiException('Invalid credentials', statusCode: 400));

    final result = await viewModel.login('emilys', 'wrong');

    expect(result, isFalse);
    expect(viewModel.errorMessage, 'Invalid credentials');
    expect(viewModel.isLoading, isFalse);
  });

  test('shows a generic message for unexpected errors', () async {
    when(
      () => repository.login(
        username: any(named: 'username'),
        password: any(named: 'password'),
      ),
    ).thenThrow(StateError('boom'));

    await viewModel.login('emilys', 'pw');

    expect(viewModel.errorMessage, contains('Something went wrong'));
  });

  test('validates empty fields without calling the repository', () async {
    final result = await viewModel.login('  ', '');

    expect(result, isFalse);
    expect(viewModel.errorMessage, isNotNull);
    verifyNever(
      () => repository.login(
        username: any(named: 'username'),
        password: any(named: 'password'),
      ),
    );
  });

  test('clearError resets the error and notifies', () async {
    await viewModel.login('', '');
    var notified = false;
    viewModel.addListener(() => notified = true);

    viewModel.clearError();

    expect(viewModel.errorMessage, isNull);
    expect(notified, isTrue);
  });
}
