// The story characters' art (specs/015-m10-apartment-story, T032): every
// value maps to a name `CharacterAvatar.looks` knows.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/domain/story_characters.dart';
import 'package:wassal/core/theme/components/characters.dart';

void main() {
  test('every story character maps to an art slug', () {
    expect(StoryCharacter.values, hasLength(6));
    for (final character in StoryCharacter.values) {
      expect(storyCharacterArt(character), isNotEmpty, reason: '$character');
    }
  });

  test('every slug has a `looks` entry, so the avatar draws Rive', () {
    for (final character in StoryCharacter.values) {
      expect(
        CharacterAvatar.looks,
        contains(storyCharacterArt(character)),
        reason: '$character',
      );
    }
  });

  test('the slugs are the content\'s wire names', () {
    expect(
      {
        for (final character in StoryCharacter.values)
          storyCharacterArt(character),
      },
      {'usta', 'salma', 'bride_father', 'bride_mother', 'moallem', 'belya'},
    );
  });
}
