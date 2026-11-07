class Translations {
  final Map<String, dynamic>? _translations;
  final Map<String?, dynamic> _nestedKeysCache;

  Translations(Map<String, dynamic>? translations)
      : _translations =
            translations == null ? null : Map<String, dynamic>.unmodifiable(translations.map((key, value) => MapEntry(key, _copy(value)))),
        _nestedKeysCache = {};

  Translations.copy(Translations source)
      : _translations = source._translations,
        _nestedKeysCache = {};

  static dynamic _copy(dynamic value) {
    if (value is Map) return Map<dynamic, dynamic>.unmodifiable(value.map((key, item) => MapEntry(key, _copy(item))));
    if (value is List) return List<dynamic>.unmodifiable(value.map(_copy));
    return value;
  }

  String? get(String key) {
    String? returnValue;

    /// Try to look it up as a nested key
    if (isNestedKey(key)) {
      returnValue = getNested(key);
    }

    /// If we failed to find the key as a nested key, then fall back
    /// to looking it up like normal.
    final directValue = _translations?[key];
    returnValue ??= directValue is String ? directValue : null;

    return returnValue;
  }

  String? getNested(String key) {
    if (isNestedCached(key)) return _nestedKeysCache[key];

    final keys = key.split('.');
    final kHead = keys.first;

    var value = _translations?[kHead];

    // print(value);

    for (var i = 1; i < keys.length; i++) {
      if (value is! Map) return null;
      value = value[keys[i]];
    }

    /// If we found the value, cache it. If the value is null then
    /// we're not going to cache it, and returning null instead.
    if (value is String) {
      cacheNestedKey(key, value);
      return value;
    }

    return null;
  }

  // bool has(String key) => isNestedKey(key)
  //     ? getNested(key) != null
  //     : _translations.containsKey(key);

  bool isNestedCached(String key) => _nestedKeysCache.containsKey(key);

  void cacheNestedKey(String key, String value) {
    if (!isNestedKey(key)) {
      throw Exception('Cannot cache a key that is not nested.');
    }

    _nestedKeysCache[key] = value;
  }

  bool isNestedKey(String key) => !(_translations?.containsKey(key) ?? false) && key.contains('.');
}
