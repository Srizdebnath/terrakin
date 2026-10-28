import 'package:flutter_test/flutter_test.dart';
import 'package:terrakin/core/trade_rules.dart';

void main() {
  test('both phones derive the same seed and shifts', () {
    final a = tradeSeed('aa11', 'bb22', 'kinA', 'kinB');
    final b = tradeSeed('bb22', 'aa11', 'kinB', 'kinA');
    expect(a, b);
    expect(rollTradeShift(a, 'kinA'), rollTradeShift(b, 'kinA'));
    expect(rollTradeShift(a, 'kinA'), isNot(rollTradeShift(a, 'kinB')));
  });

  test('shifts go both ways and stay within the swing', () {
    var up = 0, down = 0;
    for (var i = 0; i < 2000; i++) {
      for (final f in rollTradeShift(i * 7919, 'k$i')) {
        expect(f, inInclusiveRange(1 - tradeSwing, 1 + tradeSwing));
        if (f > 1) up++;
        if (f < 1) down++;
      }
    }
    expect(up, greaterThan(3000));
    expect(down, greaterThan(3000));
  });

  test('repeated trades stay within the floor and ceiling', () {
    var mods = [1.0, 1.0, 1.0, 1.0];
    for (var i = 0; i < 500; i++) {
      mods = applyShift(mods, rollTradeShift(i, 'same'));
      for (final m in mods) {
        expect(m, inInclusiveRange(modFloor, modCeil));
      }
    }
  });

  test('range check allows a little GPS slack, capped at 5 m', () {
    expect(withinTradeRange(8, 4, 4), isTrue);
    expect(withinTradeRange(9.5, 4, 4), isTrue); // 8 + 2 m slack
    expect(withinTradeRange(10.5, 4, 4), isFalse);
    expect(withinTradeRange(13, 50, 50), isTrue); // slack capped at 5 m
    expect(withinTradeRange(13.5, 50, 50), isFalse);
  });
}
