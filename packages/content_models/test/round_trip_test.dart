// The app models read every valid example and write it back in canonical form
// (FR-009), and the canonical form matches the shared vectors.
import 'dart:convert';
import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:test/test.dart';

final _examples = Directory('../../content/examples');

Object? _read(File file) => jsonDecode(file.readAsStringSync());

Map<String, dynamic> _toJson(Object model) =>
    (model as dynamic).toJson() as Map<String, dynamic>;

void main() {
  final valid =
      Directory('${_examples.path}/valid')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('every part has a root parser and a valid example', () {
    final parts = {
      for (final file in valid)
        file.parent.uri.pathSegments.reversed.elementAt(1),
    };
    expect(parts, rootFromJson.keys.toSet());
    expect(schemaSetVersion, '1.0');
  });

  for (final file in valid) {
    final part = file.parent.uri.pathSegments.reversed.elementAt(1);
    final name = file.uri.pathSegments.last;
    test('$part/$name round-trips canonically', () {
      final input = _read(file)! as Map<String, dynamic>;
      final model = rootFromJson[part]!(input);
      final output = _toJson(model);
      expect(canonicalJson(output), canonicalJson(input));
      final again = rootFromJson[part]!(
        jsonDecode(jsonEncode(output)) as Map<String, dynamic>,
      );
      expect(again, model);
      expect(again.hashCode, model.hashCode);
    });
  }

  // M10's fields (specs/015-m10-apartment-story, contracts/content-fields.md): the sample and the
  // valid examples carry every one, and the models read each.
  group('the story fields (M10)', () {
    Map<String, dynamic> read(String path) =>
        _read(File('${_examples.path}/$path'))! as Map<String, dynamic>;

    test('a chapter reads its goal art, lines, tagline and story trip', () {
      final chapter = Chapter.fromJson(read('sample/chapters/ch1_first_job.json'));
      expect(chapter.goalArt, 'goal_shabka');
      expect(chapter.goalLine?.speaker, StoryCharacter.moallem);
      expect(chapter.goalLine?.text.arEg, isNotEmpty);
      expect(chapter.tagline?.arEg, isNotEmpty);
      final info = chapter.storyTripInfo;
      expect(info, isNotNull);
      expect(info!.title.arEg, isNotEmpty);
      expect(info.condition?.arEg, isNotEmpty);
      expect(info.failReason?.arEg, isNotEmpty);
      final rid = info.riders.single;
      expect(rid.character, StoryCharacter.moallem);
      expect(rid.seat, 'A_l');
      expect(rid.comments?.shortChange, 'story.moallem.short_change');
      expect(rid.comments?.fight, 'story.moallem.fight');
      expect(rid.comments?.impatient, isNull);
    });

    test('a scene reads its title', () {
      final chapter = Chapter.fromJson(read('sample/chapters/ch2_her_father.json'));
      final scene = chapter.scenes.single;
      expect(scene.sceneId, 'father_visit');
      expect(scene.title.arEg, isNotEmpty);
      expect(scene.plays, isNull);
      expect(Chapter.fromJson(read('sample/chapters/ch1_first_job.json')).scenes
          .map((s) => s.title.arEg), everyElement(isNotEmpty));
    });

    test('an item reads its slot, its comment and its variants\' comments', () {
      final item = Item.fromJson(read('sample/items/salon.nish.json'));
      expect(item.slot.x, 89);
      expect(item.slot.y, 40);
      expect(item.slot.w, 180);
      expect(item.slot.h, 150);
      expect(item.comment?.arEg, isNotEmpty);
      expect(item.variants.map((v) => v.comment?.arEg), everyElement(isNotNull));
      final sitara = Item.fromJson(read('sample/items/salon.sitara.json'));
      expect(sitara.variants.single.comment?.arEg, isNotEmpty);
      expect(item.slot, isNot(sitara.slot));
    });

    test('a room reads its art and its done line', () {
      final room = Room.fromJson(read('sample/rooms/salon.json'));
      expect(room.art, 'salon');
      expect(room.doneLine?.arEg, isNotEmpty);
    });

    test('a family request reads its asker', () {
      final request = FamilyRequest.fromJson(
        read('sample/family_requests/req_nish_crystal.json'),
      );
      expect(request.character, StoryCharacter.brideMother);
    });

    test('the valid examples carry the required fields too', () {
      final info = Chapter.fromJson(
        read('valid/chapter/chapter_with_story_trip_info.json'),
      );
      expect(info.storyTripInfo?.riders, isNotEmpty);
      final item = Item.fromJson(read('valid/item/item_with_slot.json'));
      expect(item.slot.w, greaterThanOrEqualTo(24));
      final request = FamilyRequest.fromJson(
        read('valid/family_request/req_nish_crystal.json'),
      );
      expect(request.character, StoryCharacter.brideMother);
      expect(StoryCharacter.values, hasLength(6));
    });
  });

  test('unknown fields are ignored (FR-008)', () {    final file = File('${_examples.path}/valid/trip/line_gamaa.12.json');
    final input = _read(file)! as Map<String, dynamic>;
    final newer = jsonDecode(jsonEncode(input)) as Map<String, dynamic>;
    newer['future_field'] = 1;
    (newer['passengers'] as List<dynamic>).first['future_field'] = {
      'nested': [1, 2],
    };
    final model = TripDefinition.fromJson(newer);
    expect(canonicalJson(model.toJson()), canonicalJson(input));
    expect(model, TripDefinition.fromJson(input));
  });

  test('optional fields are left out, never written as null', () {
    final file = File('${_examples.path}/valid/trip/line_gamaa.12.json');
    final trip = TripDefinition.fromJson(_read(file)! as Map<String, dynamic>);
    expect(trip.passengers.first.boardStationId, isNull);
    final passenger =
        (trip.toJson()['passengers'] as List<dynamic>).first
            as Map<String, dynamic>;
    expect(passenger.containsKey('board_station_id'), isFalse);
  });

  test('a property that is not an identifier keeps its name', () {
    final text = LocalizedText.fromJson({'ar-EG': 'x'});
    expect(text.arEg, 'x');
    expect(text.toJson(), {'ar-EG': 'x'});
  });

  group('canonicalJson', () {
    final vectors =
        _read(File('${_examples.path}/canonical-vectors.json'))!
            as List<dynamic>;
    for (final vector in vectors.cast<Map<String, dynamic>>()) {
      test(vector['name'], () {
        expect(canonicalJson(vector['input']), vector['canonical']);
      });
    }

    test('refuses null, doubles, non-string keys and other values', () {
      expect(() => canonicalJson(null), throwsArgumentError);
      expect(() => canonicalJson({'a': 1.5}), throwsArgumentError);
      expect(
        () => canonicalJson([
          {'a': null},
        ]),
        throwsArgumentError,
      );
      expect(() => canonicalJson({1: 'a'}), throwsArgumentError);
      expect(() => canonicalJson({'a': DateTime(2026)}), throwsArgumentError);
    });

    test('refuses integers outside ±(2^53 - 1), as the loader does', () {
      const safe = 9007199254740991;
      expect(canonicalJson([safe, -safe]), '[$safe,-$safe]');
      expect(() => canonicalJson({'a': safe + 1}), throwsArgumentError);
      expect(() => canonicalJson({'a': -safe - 1}), throwsArgumentError);
    });

    test('refuses lone surrogates, and keeps surrogate pairs', () {
      expect(canonicalJson({'a': '\u{1F600}'}), '{"a":"\u{1F600}"}');
      expect(() => canonicalJson({'a': 'x\uD800'}), throwsArgumentError);
      expect(() => canonicalJson({'a': '\uDC00y'}), throwsArgumentError);
      expect(() => canonicalJson({'\uD83D': 1}), throwsArgumentError);
    });
  });
}
