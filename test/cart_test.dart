import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hankatsu/pos_api.dart';

void main() {
  test('Refreshing product instances does not duplicate a cart line', () {
    final cart = Cart();
    cart.add(Product('1', 'Katsu', 'Meals', 10000, 5));
    cart.add(Product('1', 'Katsu', 'Meals', 10000, 5));
    cart.add(Product('1', 'Katsu', 'Meals', 10000, 5));
    expect(cart.lines.length, 1);
    expect(cart.units, 3);
    expect(cart.total, 30000);
  });
  test('Changed price and stock need explicit reconciliation', () {
    final cart = Cart();
    cart.add(Product('1', 'Katsu', 'Meals', 10000, 5));
    cart.add(Product('1', 'Katsu', 'Meals', 10000, 5));
    final updated = [Product('1', 'Katsu', 'Meals', 11000, 1)];
    expect(cart.issues(updated), isNotEmpty);
    expect(cart.total, 20000);
    cart.reconcile(updated);
    expect(cart.total, 11000);
    expect(cart.units, 1);
  });
  test('Cash parsing rejects negative, nonfinite and excess precision', () {
    expect(parseMinor('12.05'), 1205);
    expect(parseMinor('NaN'), isNull);
    expect(parseMinor('-1'), isNull);
    expect(parseMinor('1.005'), isNull);
  });
  test(
    'Pending checkout survives reload and is separated by account',
    () async {
      SharedPreferences.setMockInitialValues({});
      final cart = Cart()..add(Product('1', 'Meal', 'Meals', 100, 4));
      final store = DraftStore('cashier-a');
      await store.write(cart, {
        'request_id': 'same-request',
        'cash_minor': 100,
      });
      final data = await store.read();
      expect(data['pending']['request_id'], 'same-request');
      expect(data['cart'].length, 1);
      expect(await DraftStore('cashier-b').read(), isEmpty);
    },
  );
}
