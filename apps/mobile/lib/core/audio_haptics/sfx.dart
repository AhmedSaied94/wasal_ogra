/// The trip's sound effects (specs/008-m02-trip-screen, contracts/trip-view.md
/// "Stand-in effects"), each with its file under `assets/audio/sfx/`.
enum Sfx {
  coin('coin'),
  notePass('note_pass'),
  call('call'),
  horn('horn'),
  fight('fight'),
  thanks('thanks'),
  wrong('wrong'),
  bump('bump'),
  alert('alert');

  const Sfx(this.file);

  /// The file name without its `.wav`.
  final String file;

  /// The asset path under `assets/`.
  String get assetPath => 'audio/sfx/$file.wav';
}

/// Plays short effects with low latency. [play] never waits and never
/// throws: a missing effect is silence.
abstract interface class SfxPlayer {
  Future<void> load();

  void play(Sfx sfx);

  Future<void> dispose();
}
