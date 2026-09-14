import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/format/maldives_time.dart';

/// §Phase 9a's timezone convention, on the client side.
///
/// The backend has the same boundary cases in `test/maldives-time.test.ts`;
/// these exist separately because the *presentation* is where getting it
/// wrong is visible — a slot filed under the wrong heading on a provider's
/// own calendar.
void main() {
  group('presenting in Maldives time', () {
    test('shifts by a constant five hours, in January and in July alike', () {
      expect(maldivesClock(DateTime.parse('2027-01-15T04:00:00Z')), '09:00');
      expect(maldivesClock(DateTime.parse('2027-07-15T04:00:00Z')), '09:00');
    });

    test('never depends on the device timezone', () {
      // The same instant expressed two ways. A screen that reached for
      // `toLocal()` would answer differently on a phone left on another
      // timezone — and the server, which is the one deciding what is
      // bookable, would disagree with what the provider is looking at.
      final asUtc = DateTime.parse('2026-09-15T08:00:00Z');
      final asOffset = DateTime.parse('2026-09-15T13:00:00+05:00');
      expect(maldivesClock(asUtc), maldivesClock(asOffset));
      expect(maldivesDateKey(asUtc), maldivesDateKey(asOffset));
    });

    test('files a late-evening Malé time under the day the provider means', () {
      // 02:00 in Malé is 21:00Z the previous day. Grouping by UTC date would
      // put this on 30 September.
      expect(
        maldivesDateKey(DateTime.parse('2026-09-30T21:00:00Z')),
        '2026-10-01',
      );
      expect(
        maldivesDateKey(DateTime.parse('2026-10-01T16:00:00Z')),
        '2026-10-01',
      );
    });

    test('opens a Maldives day at 19:00Z the evening before', () {
      expect(
        maldivesDayStart('2026-10-01').toIso8601String(),
        '2026-09-30T19:00:00.000Z',
      );
    });

    test('reads the weekday from the Maldives day, not the UTC one', () {
      // 23:00 Malé on Sunday 4 October is 18:00Z the same day.
      expect(
        maldivesWeekdayShort(DateTime.parse('2026-10-04T18:00:00Z')),
        'Sun',
      );
      // 01:00 Malé on Monday 5 October is 20:00Z on the Sunday.
      expect(
        maldivesWeekdayShort(DateTime.parse('2026-10-04T20:00:00Z')),
        'Mon',
      );
    });

    test('names today and tomorrow relative to a given now', () {
      final now = DateTime.parse('2026-09-14T03:00:00Z');
      expect(
        maldivesDayLabel(DateTime.parse('2026-09-14T08:00:00Z'), now),
        'Today',
      );
      expect(
        maldivesDayLabel(DateTime.parse('2026-09-15T04:00:00Z'), now),
        'Tomorrow',
      );
      expect(
        maldivesDayLabel(DateTime.parse('2026-09-17T04:00:00Z'), now),
        'Thu 17 Sep',
      );
    });
  });

  group('rule labels', () {
    test('reads a contiguous run as a range and anything else as a list', () {
      expect(weekdayRangeLabel([1, 2, 3, 4]), 'Mon–Thu');
      expect(weekdayRangeLabel([1]), 'Mon');
      expect(weekdayRangeLabel([1, 3, 5]), 'Mon, Wed, Fri');
      // Unsorted input is the same rule — the editor hands back a set.
      expect(weekdayRangeLabel([4, 2, 3, 1]), 'Mon–Thu');
    });

    test('states a visit length the way a provider would say it', () {
      expect(visitLengthLabel(60), '1 hour');
      expect(visitLengthLabel(120), '2 hours');
      expect(visitLengthLabel(90), '90 min');
    });
  });
}
