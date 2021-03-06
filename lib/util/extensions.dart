extension ListExtension<T> on List<T?> {
  List<T> filterNotNull() {
    return this.where((e) => e != null).toList() as List<T>;
  }
}

extension StreamExtension<T> on Stream<T> {
  Stream<T?> toNullable() {
    return this.map<T?>((e) => e);
  }
}

extension FutureExtension<T> on Future<T> {
  Future<T?> toNullable() {
    return this.then<T?>((e) => e);
  }
}

extension MapExtension<K, V> on Map<K, V?> {
  Map<K, V> filterNotNull<K, V>() {
    this.removeWhere((_, v) => v == null);
    return this as Map<K, V>;
  }
}

extension RangeExtension on int {
  /// Excluding max
  List<int> to(int maxInclusive) =>
      [for (int i = this; i <= maxInclusive; i++) i];
}

extension NumberStrings on int {
  String toNumberWord({useZero = false}) {
    switch (this) {
      case 0:
        return useZero ? "zero" : "no";
      case 1:
        return "one";
      case 2:
        return "two";
      case 3:
        return "three";
      default:
        return this.toString();
    }
  }
}

extension StringTransform on String {
  String capitalize() {
    return this[0].toUpperCase() + this.substring(1);
  }
}
