// Preload hygiene (specs/018-m11-ads, research R16). These are SDK hygiene,
// not balancing numbers, so they are named constants rather than tunables
// (constitution VIII covers balancing).

/// A loaded ad older than this is dropped and reloaded: Google's rewarded
/// and interstitial ads expire after an hour.
const adExpiryMs = 55 * 60 * 1000;

/// The waits after a failed load, before the next try at an allowed
/// moment: the first failure, the second, then every one after.
const adBackoffMs = [30 * 1000, 60 * 1000, 120 * 1000];

/// The wait after [failures] failed loads in a row (1 or more).
int backoffAfter(int failures) =>
    adBackoffMs[(failures < 1 ? 1 : failures).clamp(1, adBackoffMs.length) - 1];
