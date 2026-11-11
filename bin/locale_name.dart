/// A JSON locale filename parsed for loader keys and linked paths.
class LocaleName {
  final String language;
  final String? script;
  final String? region;

  const LocaleName(this.language, this.script, this.region);

  String get key => [language, ?script, ?region].join('_');

  static LocaleName? parse(String name) {
    final match = RegExp(r'^([a-zA-Z]{2,3})(?:[-_]([a-zA-Z]{4}))?(?:[-_]([a-zA-Z]{2}|[0-9]{3}))?$').firstMatch(name);
    if (match == null) return null;
    final language = (match[1] ?? '').toLowerCase();
    final script = match[2];
    final region = match[3];
    return LocaleName(language, script == null ? null : '${script[0].toUpperCase()}${script.substring(1).toLowerCase()}', region?.toUpperCase());
  }
}
