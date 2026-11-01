import '../core/api_exception.dart';

/// Maps any thrown error to text that is safe to show in the UI.
String errorMessageFor(Object error) => error is ApiException
    ? error.message
    : 'Something went wrong. Please try again.';
