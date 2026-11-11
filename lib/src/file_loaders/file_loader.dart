/// Abstract file loader interface to allow different implementations
/// for Flutter runtime (using rootBundle) and CLI file access.
abstract class FileLoader {
  Future<String> loadString(String path);
}
