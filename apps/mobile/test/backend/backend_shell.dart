// Runs Python in the dev stack's API container (specs/011-m06-identity-
// sync/tasks.md T033): what the tests need the server to do that no
// endpoint does, such as ending a player's sessions.
import 'dart:io';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// `backend/`, from `apps/mobile`, where `flutter test` runs.
final _backendDir = Directory('../../backend').absolute.path;

/// Runs [python] through `manage.py shell -c` in the `api` container and
/// returns what it printed. Throws when it fails.
Future<String> backendShell(String python) async {
  final result = await Process.run('docker', [
    'compose',
    '-f',
    'docker/compose.yml',
    '-f',
    'docker/compose.dev.yml',
    'exec',
    '-T',
    'api',
    'python',
    'manage.py',
    'shell',
    '-c',
    python,
  ], workingDirectory: _backendDir);
  if (result.exitCode != 0) {
    throw StateError(
      'backend shell failed (${result.exitCode}): ${result.stderr}',
    );
  }
  return result.stdout as String;
}

/// Ends every live session of [playerId], as the server does when a
/// device's limit is passed.
Future<void> endSessions(String playerId) {
  if (!_uuid.hasMatch(playerId)) {
    throw ArgumentError.value(playerId, 'playerId', 'not a UUID');
  }
  return backendShell('''
from apps.accounts.models import PlayerSession
from apps.accounts.services.sessions import end_session
for s in PlayerSession.objects.filter(player_id="$playerId", status=PlayerSession.Status.ACTIVE):
    end_session(s, PlayerSession.EndReason.LIMIT)
''');
}

/// Adds [bonat] to [playerId]'s wallet, as staff do in the admin (B03's
/// `adjust`), by the staff user `ci` that `seed_backend.py` creates.
Future<void> grantBonat(String playerId, int bonat) {
  if (!_uuid.hasMatch(playerId)) {
    throw ArgumentError.value(playerId, 'playerId', 'not a UUID');
  }
  return backendShell('''
from apps.accounts.models import Player, User
from apps.economy.models import Currency
from apps.economy.services.adjustments import adjust
actor, created = User.objects.get_or_create(username="ci", defaults={"is_staff": True})
if created:
    actor.set_unusable_password()
    actor.save()
adjust(Player.objects.get(pk="$playerId"), Currency.BONAT, $bonat, "app e2e", actor)
''');
}

/// Adds [jenehat] to [playerId]'s wallet, as [grantBonat] adds BONAT
/// (specs/014-m09-lines-vehicles T081: enough for the old microbus).
Future<void> grantJenehat(String playerId, int jenehat) {
  if (!_uuid.hasMatch(playerId)) {
    throw ArgumentError.value(playerId, 'playerId', 'not a UUID');
  }
  return backendShell('''
from apps.accounts.models import Player, User
from apps.economy.models import Currency
from apps.economy.services.adjustments import adjust
actor, created = User.objects.get_or_create(username="ci", defaults={"is_staff": True})
if created:
    actor.set_unusable_password()
    actor.save()
adjust(Player.objects.get(pk="$playerId"), Currency.JENEHAT, $jenehat, "app e2e", actor)
''');
}
