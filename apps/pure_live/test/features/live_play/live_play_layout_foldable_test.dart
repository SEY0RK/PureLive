// The stacked picture's shape and an unfolded foldable's split
// (docs/A-界面设计/A07-直播间界面/A07.5-宽屏左右分栏 c9, A07.2): the pure
// decisions behind `_phone` and `roomPageLayout`, without a widget tree.

import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/features/live_play/logic/room_layout.dart';

void main() {
  group('phonePictureHeight', () {
    test('a 9:16 source fills the width and stops at 60 % of the page', () {
      expect(phonePictureHeight(width: 393, height: 796, aspectRatio: 9 / 16), closeTo(477.6, 0.01));
      expect(phonePictureHeight(width: 393, height: 200, aspectRatio: 9 / 16), 120);
    });

    test('a landscape source keeps 5.6.5s 16:9 box', () {
      expect(phonePictureHeight(width: 393, height: 796), closeTo(221.06, 0.01));
      expect(phonePictureHeight(width: 393, height: 796, aspectRatio: 16 / 9), closeTo(221.06, 0.01));
    });

    test('4:3 and 21:9 take their own shape', () {
      expect(phonePictureHeight(width: 393, height: 796, aspectRatio: 4 / 3), closeTo(294.75, 0.01));
      expect(phonePictureHeight(width: 393, height: 796, aspectRatio: 21 / 9), closeTo(168.43, 0.01));
    });

    test('bad bounds and ratios fall back without throwing', () {
      for (final bad in <double>[0, -1, double.nan, double.infinity]) {
        expect(
          phonePictureHeight(width: 393, height: 796, aspectRatio: bad),
          closeTo(221.06, 0.01),
          reason: '$bad',
        );
      }
      expect(phonePictureHeight(width: 0, height: 796, aspectRatio: 9 / 16), 0);
      expect(phonePictureHeight(width: double.infinity, height: 796), 0);
      expect(phonePictureHeight(width: 393, height: 0, aspectRatio: 9 / 16), 0);
      expect(
        phonePictureHeight(width: 393, height: double.infinity, aspectRatio: 9 / 16),
        closeTo(698.67, 0.01),
      );
    });
  });

  group('foldable windows', () {
    const flatFold = DisplayFeature(
      type: DisplayFeatureType.fold,
      state: DisplayFeatureState.postureFlat,
      bounds: Rect.fromLTWH(365, 0, 0, 773),
    );
    const halfHinge = DisplayFeature(
      type: DisplayFeatureType.hinge,
      state: DisplayFeatureState.postureHalfOpened,
      bounds: Rect.fromLTWH(360, 0, 40, 900),
    );
    const cutout = DisplayFeature(
      type: DisplayFeatureType.cutout,
      state: DisplayFeatureState.unknown,
      bounds: Rect.fromLTWH(0, 0, 30, 20),
    );

    test('a flat fold and a half-open hinge count; a cut-out does not', () {
      expect(unfoldedFoldable(const []), isFalse);
      expect(unfoldedFoldable(const [cutout]), isFalse);
      expect(unfoldedFoldable(const [flatFold]), isTrue);
      expect(unfoldedFoldable(const [halfHinge]), isTrue);
    });

    test('a nearly square phone window counts even without a feature', () {
      expect(foldableWindow(size: const Size(730, 773), features: const [], mobile: true), isTrue);
      expect(foldableWindow(size: const Size(720, 1000), features: const [], mobile: true), isFalse);
      expect(foldableWindow(size: const Size(800, 1280), features: const [], mobile: true), isFalse);
      expect(foldableWindow(size: const Size(599, 900), features: const [], mobile: true), isFalse);
      expect(foldableWindow(size: const Size(730, 773), features: const [], mobile: false), isFalse);
      expect(foldableWindow(size: const Size(730, 773), features: const [flatFold], mobile: false), isTrue);
    });
  });

  group('roomPageLayout', () {
    test('an unfolded foldable splits from 600 for a portrait stream', () {
      expect(
        roomPageLayout(width: 730, height: 773, portraitPanel: false, unfoldedFoldable: true, portraitStream: true),
        RoomPageLayout.wide,
      );
      expect(
        roomPageLayout(width: 730, height: 773, portraitPanel: false, unfoldedFoldable: true),
        RoomPageLayout.phone,
        reason: 'a 16:9 source keeps the stack, where it is larger',
      );
      expect(
        roomPageLayout(width: 730, height: 773, portraitPanel: false, portraitStream: true),
        RoomPageLayout.phone,
        reason: 'no foldable: the 840 rule',
      );
      expect(
        roomPageLayout(width: 600, height: 900, portraitPanel: false, unfoldedFoldable: true, portraitStream: true),
        RoomPageLayout.wide,
      );
      expect(
        roomPageLayout(width: 599, height: 900, portraitPanel: false, unfoldedFoldable: true, portraitStream: true),
        RoomPageLayout.phone,
      );
    });

    test('the split wins over the three-stop panel on an unfolded foldable', () {
      expect(
        roomPageLayout(width: 730, height: 773, portraitPanel: true, unfoldedFoldable: true, portraitStream: true),
        RoomPageLayout.wide,
      );
    });

    test('the old size classes are unchanged', () {
      expect(roomPageLayout(width: 720, height: 1000, portraitPanel: false), RoomPageLayout.phone);
      expect(roomPageLayout(width: 840, height: 800, portraitPanel: false), RoomPageLayout.wide);
      expect(roomPageLayout(width: 839, height: 1000, portraitPanel: false), RoomPageLayout.phone);
      expect(
        roomPageLayout(width: 852, height: 393, portraitPanel: false, unfoldedFoldable: true, portraitStream: true),
        RoomPageLayout.landscape,
        reason: 'a short window stays landscape',
      );
      expect(
        roomPageLayout(
          width: 852,
          height: 393,
          portraitPanel: false,
          mobile: false,
          unfoldedFoldable: true,
          portraitStream: true,
        ),
        RoomPageLayout.wide,
      );
    });
  });
}
