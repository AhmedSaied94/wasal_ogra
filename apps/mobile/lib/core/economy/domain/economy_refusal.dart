// Why the economy refused a request (contracts/economy-api.md "Refusal
// codes"). The wire names are stable: screens react to them and M15 reports
// them. They carry no content or personal data (FR-019).

enum EconomyRefusal {
  unknownTrip('unknown_trip'),
  tripUnfinished('trip_unfinished'),
  noFuel('no_fuel'),
  resultExists('result_exists'),
  noTripStart('no_trip_start'),
  tripMismatch('trip_mismatch'),
  starsOutOfBounds('stars_out_of_bounds'),
  earningsOutOfBounds('earnings_out_of_bounds'),
  noTrip('no_trip'),
  noneLeft('none_left'),
  alreadyRevived('already_revived'),
  capReached('cap_reached'),
  noResult('no_result'),
  notDoublable('not_doublable'),
  alreadyDoubled('already_doubled'),
  tankFull('tank_full'),
  notForSale('not_for_sale'),
  catalogMismatch('catalog_mismatch'),
  unknownSku('unknown_sku'),
  unknownVariant('unknown_variant'),
  alreadyOwned('already_owned'),
  insufficientFunds('insufficient_funds'),
  serverOnly('server_only'),

  /// A comeback gift the cached bootstrap doesn't offer, or one already
  /// claimed (specs/011-m06-identity-sync R16).
  notEligible('not_eligible');

  const EconomyRefusal(this.wire);

  final String wire;
}
