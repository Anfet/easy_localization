/// Shared syntax for linked translation keys.
final RegExp linkedKeyMatcher = RegExp(
  r'(?:@(?:\.[a-z]+)?:(?:[\p{L}\p{M}\p{N}_\-|]+(?:\.[\p{L}\p{M}\p{N}_\-|]+)*|\([\p{L}\p{M}\p{N}_\-|.]+\)))',
  unicode: true,
);

/// Matches a link prefix, including its optional formatting modifier.
final RegExp linkedKeyPrefixMatcher = RegExp(r'^@(?:\.([a-z]+))?:');
