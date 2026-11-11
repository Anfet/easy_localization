/// Thrown when no localization root is found for the given context, or when a missing scope is accessed.
class LocalizationNotFoundException implements Exception {
  const LocalizationNotFoundException();

  @override
  String toString() => 'Localization not found for current context';
}

/// A newer command replaced an operation before its data was committed.
class LocalizationOperationSupersededException implements Exception {
  const LocalizationOperationSupersededException();

  @override
  String toString() => 'LocalizationOperationSupersededException: a newer localization command replaced this operation';
}
