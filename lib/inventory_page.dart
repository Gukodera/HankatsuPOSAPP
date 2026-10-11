import 'dart:async';
import 'package:flutter/material.dart';
import 'pos_api.dart';
import 'pos_header.dart';
import 'filter_chip.dart';
import 'list_controls.dart';

class InventoryPage extends StatefulWidget {
  final PosApi api;
  final VoidCallback onChanged;
  const InventoryPage({super.key, required this.api, required this.onChanged});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  List<Product> products = [];
  int page = 0, generation = 0;
  String query = '', filter = 'All';
  String? error;
  bool loading = true;
  Timer? debounce;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    final token = ++generation;
    setState(() => loading = true);
    try {
      final rows = await widget.api.call('catalog', {
        'query': query,
        'availability': filter,
        'offset': page * 10,
        'limit': 10,
      });
      if (mounted && token == generation) {
        setState(() {
          products = List<Json>.from(rows).map(Product.fromJson).toList();
          error = null;
        });
      }
    } catch (e) {
      if (mounted && token == generation) {
        setState(() => error = errorMessage(e));
      }
    } finally {
      if (mounted && token == generation) setState(() => loading = false);
    }
  }

  void notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Semantics(liveRegion: true, child: Text(message)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> edit([Product? product, int? delta]) async {
    final name = TextEditingController(text: product?.name),
        price = TextEditingController(
          text: product == null
              ? ''
              : (product.priceMinor / 100).toStringAsFixed(2),
        ),
        quantity = TextEditingController(
          text: product == null
              ? '0'
              : delta == null
              ? '${product.stock}'
              : '1',
        ),
        note = TextEditingController();
    final receiving = delta != null && delta > 0;
    final removing = delta != null && delta < 0;
    String category = product?.category ?? 'Meals';
    String reason = receiving
        ? 'Received stock'
        : removing
        ? 'Waste'
        : 'Stock count';
    bool busy = false;
    String? failure;
    final key = requestId();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => PopScope(
          canPop: !busy,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              24 + MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  product == null
                      ? 'New product'
                      : receiving
                      ? 'Receive ${product.name}'
                      : removing
                      ? 'Remove ${product.name}'
                      : 'Count / correct ${product.name}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                if (product == null) ...[
                  TextField(
                    controller: name,
                    enabled: !busy,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Product name',
                    ),
                  ),
                  TextField(
                    controller: price,
                    enabled: !busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Price (₱)'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    items: [
                      for (final c in [
                        'Meals',
                        'Snacks',
                        'Drinks',
                        'Coffee',
                        'Alcohol',
                      ])
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: busy ? null : (v) => update(() => category = v!),
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                ] else ...[
                  Text('Current quantity: ${product.stock}'),
                  Text(
                    receiving
                        ? 'Record a delivery or newly prepared stock.'
                        : removing
                        ? 'Record spoiled, damaged or discarded items, or correct excess stock.'
                        : 'Enter the physical count, or fix an incorrect recorded total.',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: reason,
                    items: [
                      for (final r in [
                        if (receiving) 'Received stock',
                        if (removing) 'Waste',
                        if (!receiving && !removing) 'Stock count',
                        if (!receiving) 'Correction',
                      ])
                        DropdownMenuItem(value: r, child: Text(r)),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => update(() {
                            reason = v!;
                            failure = null;
                          }),
                    decoration: const InputDecoration(
                      labelText: 'Adjustment reason',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: quantity,
                  onChanged: (_) => update(() => failure = null),
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: product == null
                        ? 'Opening quantity'
                        : receiving
                        ? 'Units received'
                        : removing
                        ? 'Units removed'
                        : 'Actual / corrected total',
                    helperText: product == null
                        ? null
                        : 'Resulting stock: ${receiving
                              ? product.stock + (int.tryParse(quantity.text) ?? 0)
                              : removing
                              ? product.stock - (int.tryParse(quantity.text) ?? 0)
                              : int.tryParse(quantity.text) ?? 0} units',
                  ),
                ),
                if (product != null)
                  TextField(
                    controller: note,
                    enabled: !busy,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Note / delivery reference',
                    ),
                  ),
                if (failure != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      failure!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final entered = int.tryParse(quantity.text.trim());
                          final qty = entered == null
                              ? null
                              : product == null || delta == null
                              ? entered
                              : receiving
                              ? product.stock + entered
                              : product.stock - entered;
                          final minor = parseMinor(price.text);
                          if (qty == null ||
                              (delta != null &&
                                  (entered == null || entered <= 0)) ||
                              (product != null && qty == product.stock) ||
                              qty < 0 ||
                              qty > 1000000 ||
                              (product == null &&
                                  (name.text.trim().isEmpty ||
                                      minor == null))) {
                            update(
                              () => failure = product == null
                                  ? 'Enter a name, valid price and whole nonnegative quantity.'
                                  : 'Enter a whole quantity that changes stock. Resulting stock must be between 0 and 1,000,000.',
                            );
                            return;
                          }
                          update(() => busy = true);
                          try {
                            if (!await confirmAction(
                              ctx,
                              title: product == null
                                  ? 'Create product?'
                                  : 'Confirm stock adjustment',
                              message: product == null
                                  ? '${name.text.trim()}\n${moneyMinor(minor!)} • $qty units'
                                  : '${product.name}\n${product.stock} → $qty\n$reason\n${note.text}',
                              confirmLabel: 'Save',
                            )) {
                              return;
                            }
                            await widget.api.call(
                              product == null
                                  ? 'create_product'
                                  : 'adjust_stock',
                              product == null
                                  ? {
                                      'request_id': key,
                                      'name': name.text.trim(),
                                      'category': category,
                                      'price_minor': minor,
                                      'stock': qty,
                                    }
                                  : {
                                      'request_id': key,
                                      'product_id': product.id,
                                      'expected_stock': product.stock,
                                      'quantity': qty,
                                      'reason': reason,
                                      'note': note.text.trim(),
                                    },
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            notice(
                              product == null
                                  ? 'Product added with $qty units.'
                                  : 'Stock adjusted to $qty units.',
                            );
                            widget.onChanged();
                          } catch (e) {
                            if (ctx.mounted) {
                              update(() => failure = errorMessage(e));
                            }
                          } finally {
                            if (ctx.mounted) update(() => busy = false);
                          }
                        },
                  child: Text(
                    busy
                        ? 'Saving…'
                        : product == null
                        ? 'Create product'
                        : receiving
                        ? 'Receive stock'
                        : removing
                        ? 'Remove stock'
                        : 'Save count / correction',
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    name.dispose();
    price.dispose();
    quantity.dispose();
    note.dispose();
    await load();
  }

  Future<void> history(Product product) async {
    List<Json> records = [];
    int? before;
    bool busy = false;
    String? failure;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .8,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '${product.name} movements',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              for (final m in records)
                ListTile(
                  title: Text(
                    '${m['before_qty']} → ${m['after_qty']} • ${m['reason']}',
                  ),
                  subtitle: Text(
                    '${m['actor_name']}\n${m['created_at']}\n${m['note'] ?? ''}',
                  ),
                ),
              if (failure != null) Text(failure!),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        update(() => busy = true);
                        try {
                          final rows = List<Json>.from(
                            await widget.api.call('stock_history', {
                              'product_id': product.id,
                              'before_id': ?before,
                            }),
                          );
                          if (ctx.mounted) {
                            update(() {
                              records.addAll(rows);
                              if (rows.isNotEmpty) before = rows.last['id'];
                              failure = rows.isEmpty
                                  ? 'No more movements.'
                                  : null;
                            });
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            update(() => failure = errorMessage(e));
                          }
                        } finally {
                          if (ctx.mounted) update(() => busy = false);
                        }
                      },
                child: Text(
                  busy
                      ? 'Loading…'
                      : records.isEmpty
                      ? 'Load history'
                      : 'Load older movements',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: load,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PosHeader(
          title: 'Inventory',
          subtitle: 'Every adjustment has a reason and an owner.',
          icon: Icons.inventory_2_outlined,
          actions: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Refresh stock',
                onPressed: load,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'New product',
                onPressed: () => edit(),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          onChanged: (v) {
            query = v;
            page = 0;
            debounce?.cancel();
            debounce = Timer(const Duration(milliseconds: 300), load);
          },
          decoration: const InputDecoration(
            labelText: 'Search products',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final value in ['All', 'Low stock', 'Sold out'])
              PosFilterChip(
                label: value,
                selected: filter == value,
                onSelected: (_) {
                  setState(() {
                    filter = value;
                    page = 0;
                  });
                  load();
                },
              ),
          ],
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (!loading && products.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No matching products.'),
          ),
        for (final p in products)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text('${p.stock} available • ${moneyMinor(p.priceMinor)}'),
                  Wrap(
                    spacing: 6,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => edit(p, 1),
                        icon: const Icon(Icons.add),
                        label: const Text('Receive stock'),
                      ),
                      OutlinedButton.icon(
                        onPressed: p.stock == 0 ? null : () => edit(p, -1),
                        icon: const Icon(Icons.remove),
                        label: const Text('Remove stock'),
                      ),
                      TextButton(
                        onPressed: () => edit(p),
                        child: const Text('Count / correct'),
                      ),
                      TextButton(
                        onPressed: () => history(p),
                        child: const Text('History'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: page == 0
                  ? null
                  : () {
                      setState(() => page--);
                      load();
                    },
              icon: const Icon(Icons.chevron_left),
            ),
            Text('Page ${page + 1} • 10 per page'),
            IconButton(
              onPressed: products.length < 10
                  ? null
                  : () {
                      setState(() => page++);
                      load();
                    },
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    ),
  );
}
