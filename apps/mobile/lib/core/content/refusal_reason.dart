/// Why a pack, a manifest or a download was refused, as stored in
/// `state.json` events (specs/006-m04-content-loader/contracts/loading.md
/// "Reason codes"). The wire codes are snake_case and never change.
library;

enum RefusalReason {
  manifestFailed('manifest_failed'),
  entryIgnored('entry_ignored'),
  tooLarge('too_large'),
  downloadFailed('download_failed'),
  sizeMismatch('size_mismatch'),
  sha256Mismatch('sha256_mismatch'),
  checksumFailed('checksum_failed'),
  decompressTooLarge('decompress_too_large'),
  unreadable('unreadable'),
  wrongIdentity('wrong_identity'),
  schemaUnsupported('schema_unsupported'),
  storageError('storage_error'),
  storedCheckFailed('stored_check_failed'),
  bundledCheckFailed('bundled_check_failed');

  const RefusalReason(this.wire);

  final String wire;

  /// Size and checksum failures count as attempts; the third makes the
  /// version unusable (research R14).
  bool get isAttempt => this == sizeMismatch || this == sha256Mismatch;
}

/// More about a [RefusalReason]: what failed in a request, or why a
/// manifest entry was ignored.
enum RefusalDetail {
  unreachable('unreachable'),
  status('status'),
  tooLarge('too_large'),
  unreadable('unreadable'),
  redirect('redirect'),
  insecureUrl('insecure_url'),
  minClientVersion('min_client_version'),
  unusable('unusable'),
  timeout('timeout');

  const RefusalDetail(this.wire);

  final String wire;
}
