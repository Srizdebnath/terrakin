import 'package:flutter_test/flutter_test.dart';
import 'package:terrakin/core/economy.dart';

void main() {
  BigInt mon(String s) {
    final parts = s.split('.');
    final frac = (parts.length > 1 ? parts[1] : '').padRight(18, '0');
    return BigInt.parse(parts[0]) * BigInt.from(10).pow(18) + BigInt.parse(frac);
  }

  test('MON formatting from wei', () {
    expect(fmtMon(mon('0.1')), '0.1 MON');
    expect(fmtMon(mon('0.0005')), '0.0005 MON');
    expect(fmtMon(mon('2.5')), '2.5 MON');
    expect(fmtMon(mon('1')), '1 MON');
    expect(fmtMon(BigInt.zero), '0 MON');
    expect(fmtMon(mon('0.02512')), '0.0251 MON');
  });
}
