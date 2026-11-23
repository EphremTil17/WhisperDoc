// Each test's seconds are its data, read straight off the reason string.
// ignore_for_file: avoid-late-keyword, no-magic-number
import 'package:flutter_client/services/transport/ban_state_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const defaultBanSeconds = 300;

  late BanStateService bans;

  setUp(() => bans = BanStateService());
  tearDown(() => bans.dispose());

  group('BanStateService parsing', () {
    test('starts unbanned', () {
      expect(bans.isBanned, isFalse);
      expect(bans.cooldownRemaining, 0);
    });

    final reasons = {
      'IP Banned. Cooldown: 120s': 120,
      'cooldown:45': 45,
      'Banned for 60s': 60,
      'Retry in 240s': 240,
      'Too many attempts, wait 90s': 90,
    };
    for (final MapEntry(key: reason, value: seconds) in reasons.entries) {
      test('"$reason" bans for $seconds seconds', () {
        bans.parseBanMessage(reason);

        expect(bans.isBanned, isTrue);
        expect(bans.cooldownRemaining, seconds);
      });
    }

    test('the named cooldown wins over other numbers in the reason', () {
      bans.parseBanMessage('Strike 3s exceeded. Cooldown: 600s');

      expect(bans.cooldownRemaining, 600);
    });

    for (final reason in [null, '', 'Policy violation']) {
      test('"$reason" falls back to the server default ban', () {
        bans.parseBanMessage(reason);

        expect(bans.isBanned, isTrue);
        expect(bans.cooldownRemaining, defaultBanSeconds);
      });
    }

    test('announces the starting cooldown on the stream', () async {
      final first = bans.cooldownStream.first;

      bans.parseBanMessage('Banned for 60s');

      expect(await first, 60);
    });

    test('a new ban replaces the running one', () {
      bans.parseBanMessage('Banned for 600s');
      bans.parseBanMessage('Banned for 30s');

      expect(bans.cooldownRemaining, 30);
    });
  });

  group('BanStateService countdown', () {
    // The countdown reads the wall clock, so these wait a little real time.
    const timeout = Timeout(Duration(seconds: 10));

    test('counts down each second, then lifts the ban', () async {
      final ticks = <int>[];
      // The last part-second still reads 0 while banned; only expiry lifts it.
      final lifted = bans.cooldownStream.firstWhere((s) {
        ticks.add(s);

        return s == 0 && !bans.isBanned;
      });

      bans.parseBanMessage('Retry in 2s');
      await lifted;

      expect(ticks.first, 2);
      expect(ticks.length, greaterThan(2));
      for (var i = 1; i < ticks.length; i++) {
        expect(ticks[i], lessThanOrEqualTo(ticks[i - 1]));
      }
      expect(bans.isBanned, isFalse);
      expect(bans.cooldownRemaining, 0);
    }, timeout: timeout);

    test('stays banned while the cooldown runs', () async {
      bans.parseBanMessage('Banned for 30s');

      final tick = await bans.cooldownStream.first;

      expect(tick, inInclusiveRange(28, 30));
      expect(bans.isBanned, isTrue);
      expect(bans.cooldownRemaining, tick);
    }, timeout: timeout);
  });
}
