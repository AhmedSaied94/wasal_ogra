// The "leave this field as it is" marker of the package-internal update
// helpers, so they can also set a nullable field to null.
const Object keep = _Keep();

final class _Keep {
  const _Keep();
}

/// [value] unless it is [keep], else [current].
T kept<T>(Object? value, T current) =>
    identical(value, keep) ? current : value as T;
