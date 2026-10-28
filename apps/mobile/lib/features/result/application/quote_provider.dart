// The result's quote (specs/013-m08-home-result, research R14): the trip's
// replay runs on another isolate, so the screen never waits on it; the card
// fades in when it arrives.
import 'dart:isolate';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/result/domain/quote.dart';
import 'package:wassal/features/result/domain/result_args.dart';

part 'quote_provider.g.dart';

/// Picks a record's quote.
typedef QuoteRunner = Future<Quote?> Function(ReplayRecord record);

/// On another isolate; tests pick in place.
@Riverpod(keepAlive: true)
QuoteRunner quoteRunner(Ref ref) =>
    (record) => Isolate.run(() => pickQuote(record));

/// [args]' quote, kept with its start.
@riverpod
Future<Quote?> resultQuote(Ref ref, ResultArgs args) =>
    ref.watch(quoteRunnerProvider)(args.replay);
