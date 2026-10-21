/// An app version, `MAJOR.MINOR.PATCH` with an optional `+BUILD`
/// (content/schemas `ClientVersion`, research R2). Packs name a minimum
/// version without a build; the app compares its own against it.
final class ClientVersion implements Comparable<ClientVersion> {
  const ClientVersion(this.major, this.minor, this.patch, {this.build});

  /// The version in [text], or null when it isn't `N.N.N` or `N.N.N+N`.
  static ClientVersion? parse(String text) {
    final match = _pattern.firstMatch(text);
    if (match == null) return null;
    final build = match[4];
    return ClientVersion(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      build: build == null ? null : int.parse(build),
    );
  }

  static final _pattern = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$');

  final int major;
  final int minor;
  final int patch;

  /// The store build number. Comparison ignores it.
  final int? build;

  /// Compares `MAJOR.MINOR.PATCH` only.
  @override
  int compareTo(ClientVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  /// Whether this version meets [minimum], ignoring builds.
  bool atLeast(ClientVersion minimum) => compareTo(minimum) >= 0;

  /// Equal when `MAJOR.MINOR.PATCH` are, as [compareTo] says.
  @override
  bool operator ==(Object other) =>
      other is ClientVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch${build == null ? '' : '+$build'}';
}
