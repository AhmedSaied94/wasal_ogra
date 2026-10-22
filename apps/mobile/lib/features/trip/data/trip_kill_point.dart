/// The moments a kill must leave a trip recoverable from
/// (contracts/trip-controller.md "Test seams"). Tests throw from an
/// `onKillPoint` callback at each one. The store's points fall between its
/// writes; the controller's between an economy call and what follows it.
enum TripKillPoint {
  /// The record is written; `startTrip` hasn't run (the store's point).
  recordCreated,

  /// The start applied; the engine hasn't started.
  startApplied,

  /// A command row and the record's clock are written.
  commandAppended,

  /// Inside the booster's transaction: the command row is written, its
  /// intent isn't. The transaction rolls back.
  boosterCommandRow,

  /// The booster's command and intent are written; `useBooster` hasn't run.
  boosterUseWritten,

  /// The revive is paid; `Revive` isn't applied.
  reviveBought,

  /// The clock is saved at a pause.
  clockSaved,

  /// The result is recorded; the record isn't deleted.
  resultRecorded,

  /// The record and everything with it are deleted.
  recordDeleted,
}
