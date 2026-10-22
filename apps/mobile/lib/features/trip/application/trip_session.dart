import 'package:content_models/content_models.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';

/// The trip on screen (data-model.md "TripSession"): created when it opens,
/// gone when it ends.
final class TripSession {
  TripSession({
    required this.startTxn,
    required this.contentVersion,
    required this.seed,
    required this.facts,
    required this.engine,
  });

  /// The economy's start id, also the record's key.
  final TxnId startTxn;
  final int contentVersion;
  final int seed;
  final TripFacts facts;

  /// The one engine.
  final TripEngine engine;

  TripDefinition get definition => facts.definition;
  String get tripId => definition.tripId;
  TripParams get params => facts.params;
}
