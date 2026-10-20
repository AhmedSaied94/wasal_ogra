// Speech (rules.md §12): the only place that draws from the PRNG.
import '../capabilities.dart';
import '../events.dart';
import '../prng.dart';
import 'transition.dart';

/// Passenger [passenger] says [slot]. [amount] and [station] fill the slot's
/// placeholders, and are left out for a slot that doesn't declare them.
void say(
  Transition tx,
  int passenger,
  SpeechSlot slot, {
  int? amount,
  String? station,
}) {
  final (variant, next) = Xorshift32(tx.prng).next();
  tx.prng = next.state;
  final spec = tx.course.spec(passenger);
  tx.emit(
    PassengerSpeaks(
      tx.tMs,
      passengerId: spec.passengerId,
      slot: slot,
      speechKey: spec.speechKeys?[slot.wire] ?? slot.defaultKey,
      variant: variant,
      amountPiasters: slot.hasAmount ? amount : null,
      stationId: slot.hasStation ? station : null,
    ),
  );
}
