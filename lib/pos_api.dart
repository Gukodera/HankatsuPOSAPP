import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef Json = Map<String, dynamic>;
String requestId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
String moneyMinor(int value) => '₱${(value / 100).toStringAsFixed(2)}';
int? parseMinor(String value) {
  if (!RegExp(r'^\d{1,8}(\.\d{1,2})?$').hasMatch(value.trim())) return null;
  final p = value.trim().split('.');
  return int.parse(p[0]) * 100 +
      (p.length == 2 ? int.parse(p[1].padRight(2, '0')) : 0);
}

String errorMessage(Object error) {
  if (error is StateError) return error.message.toString();
  if (error is PostgrestException) {
    if (error.code == 'PGRST202') {
      return 'Database upgrade required. Apply the operational POS migration first.';
    }
    if (error.code == '42501') return error.message;
    if (error.code == 'P0001') return error.message;
    return 'The database rejected this change. Refresh and review the details (${error.code ?? 'unknown'}).';
  }
  if (error is AuthException) {
    return 'Your session needs attention. Sign in again before continuing.';
  }
  return 'Could not confirm the server result. Check your connection. Pending checkout is kept for recovery.';
}

class PosApi {
  Future<dynamic> call(String action, [Json args = const {}]) => Supabase
      .instance
      .client
      .rpc('pos_api', params: {'action': action, 'args': args});
}

class Product {
  final String id, name, category;
  final int priceMinor, stock;
  Product(this.id, this.name, this.category, this.priceMinor, this.stock);
  factory Product.fromJson(Json p) => Product(
    p['id'].toString(),
    p['name'] as String,
    p['category'] as String,
    ((p['price'] as num) * 100).round(),
    (p['stock'] as num).toInt(),
  );
}

class CartLine {
  final String id;
  String name;
  int unitMinor, quantity;
  CartLine(this.id, this.name, this.unitMinor, this.quantity);
  Json toJson() => {
    'product_id': id,
    'name': name,
    'unit_minor': unitMinor,
    'qty': quantity,
  };
  factory CartLine.fromJson(Json p) => CartLine(
    p['product_id'] as String,
    p['name'] as String,
    p['unit_minor'] as int,
    p['qty'] as int,
  );
}

class Cart {
  final Map<String, CartLine> lines = {};
  int get total => lines.values.fold(0, (a, l) => a + l.unitMinor * l.quantity);
  int get units => lines.values.fold(0, (a, l) => a + l.quantity);
  void add(Product product) {
    final quantity = lines[product.id]?.quantity ?? 0;
    if (quantity >= product.stock) throw StateError('Available stock reached');
    lines
        .putIfAbsent(
          product.id,
          () => CartLine(product.id, product.name, product.priceMinor, 0),
        )
        .quantity++;
  }

  void decrement(String id) {
    final line = lines[id];
    if (line == null) return;
    if (--line.quantity <= 0) lines.remove(id);
  }

  List<String> issues(List<Product> products) {
    final current = {for (final p in products) p.id: p};
    return [
      for (final line in lines.values)
        if (current[line.id] == null)
          '${line.name} is unavailable'
        else if (current[line.id]!.stock < line.quantity)
          '${line.name}: only ${current[line.id]!.stock} available'
        else if (current[line.id]!.priceMinor != line.unitMinor)
          '${line.name}: price changed to ${moneyMinor(current[line.id]!.priceMinor)}',
    ];
  }

  void reconcile(List<Product> products) {
    final current = {for (final p in products) p.id: p};
    for (final id in lines.keys.toList()) {
      final p = current[id];
      if (p == null || p.stock == 0) {
        lines.remove(id);
        continue;
      }
      final line = lines[id]!;
      line.name = p.name;
      line.unitMinor = p.priceMinor;
      line.quantity = min(line.quantity, p.stock);
    }
  }
}

class DraftStore {
  final String userId;
  DraftStore(this.userId);
  String get key => 'hankatsu.v2.$userId';
  Future<Json> read() async {
    final value = (await SharedPreferences.getInstance()).getString(key);
    if (value == null) return {};
    return Map<String, dynamic>.from(jsonDecode(value) as Map);
  }

  Future<void> write(Cart cart, Json? pending) async {
    final ok = await (await SharedPreferences.getInstance()).setString(
      key,
      jsonEncode({
        'cart': cart.lines.values.map((l) => l.toJson()).toList(),
        'pending': pending,
      }),
    );
    if (!ok) throw StateError('Could not persist checkout');
  }
}
