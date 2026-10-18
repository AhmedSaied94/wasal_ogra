// Constants and an interface only: nothing for coverage to count.
abstract interface class Store {
  String? read(String key);
}

abstract final class Sizes {
  static const double small = 4;
  static const double large = 16;
}
