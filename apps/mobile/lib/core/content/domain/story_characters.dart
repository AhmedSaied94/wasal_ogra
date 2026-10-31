// The story characters' art (specs/015-m10-apartment-story, contracts/
// apartment.md "The goal view"): the slug `CharacterAvatar.looks` and ARB
// `sceneSpeaker` name, from the content's `StoryCharacter`. One switch, so a
// new character fails the compiler here and in the tests.
import 'package:content_models/content_models.dart';

/// The art slug for [character], as `CharacterAvatar.looks` and
/// `sceneSpeaker` spell it (the content's own wire names).
String storyCharacterArt(StoryCharacter character) => switch (character) {
  StoryCharacter.usta => 'usta',
  StoryCharacter.salma => 'salma',
  StoryCharacter.brideFather => 'bride_father',
  StoryCharacter.brideMother => 'bride_mother',
  StoryCharacter.moallem => 'moallem',
  StoryCharacter.belya => 'belya',
};
