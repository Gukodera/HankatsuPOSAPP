import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pos_api.dart';
import 'pos_header.dart';
import 'brand_logo.dart';
import 'filter_chip.dart';
import 'list_controls.dart';
import 'checkout_sheet.dart';
import 'inventory_page.dart';
import 'orders_page.dart';
import 'analytics_page.dart';
import 'shift_page.dart';
import 'receipt.dart';
import 'today_highlights.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: const String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'https://qnxjyepckqdusksurrbo.supabase.co',
    ),
    publishableKey: const String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: 'sb_publishable_KVnCg_ICcFLg4aO0f3EPRA_qGNh6F7r',
    ),
  );
  runApp(const HankatsuApp());
}

class HankatsuApp extends StatelessWidget {
  const HankatsuApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Hankatsu POS',
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFFFF7F8),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFFE32646),
        secondary: Color(0xFF191519),
        surface: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    ),
    home: StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (_, snapshot) {
        final user = Supabase.instance.client.auth.currentUser;
        return user == null
            ? const LoginPage()
            : AccessGate(key: ValueKey(user.id), userId: user.id);
      },
    ),
  );
}

class AccessGate extends StatefulWidget {
  final String userId;
  const AccessGate({super.key, required this.userId});
  @override
  State<AccessGate> createState() => _AccessGateState();
}

class _AccessGateState extends State<AccessGate> {
  final api = PosApi();
  Json? staff;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = Json.from(await api.call('context'));
      if (mounted) {
        setState(() {
          staff = result;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) => staff != null
      ? Shell(api: api, staff: staff!, userId: widget.userId)
      : Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (error == null)
                    const CircularProgressIndicator()
                  else ...[
                    Text(error!),
                    TextButton(
                      onPressed: load,
                      child: const Text('Retry setup'),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (await confirmAction(
                          context,
                          title: 'Sign out?',
                          message: 'Return to the login page?',
                          confirmLabel: 'Sign out',
                        )) {
                          await Supabase.instance.client.auth.signOut();
                        }
                      },
                      child: const Text('Sign out'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
}

class Shell extends StatefulWidget {
  final PosApi api;
  final Json staff;
  final String userId;
  const Shell({
    super.key,
    required this.api,
    required this.staff,
    required this.userId,
  });
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  final cart = Cart();
  List<Product> products = [];
  Json? pending, lastReceipt;
  String? error;
  bool loading = true, working = false, ready = false;
  int tab = 0, menuPage = 0;
  int highlightsRefresh = 0;
  String query = '', category = 'All', availability = 'All';
  late final store = DraftStore(widget.userId);
  Future<void> writes = Future.value();
  final search = TextEditingController();
  final menuScroll = ScrollController();
  bool get admin => widget.staff['role'] == 'admin';
  bool get cashier => admin || widget.staff['role'] == 'cashier';
  late final List<Widget> pages;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    pages = [
      if (cashier) const SizedBox(),
      if (admin || !cashier)
        OrdersPage(api: widget.api, role: widget.staff['role']),
      if (admin) InventoryPage(api: widget.api, onChanged: loadProducts),
      if (cashier) AnalyticsPage(api: widget.api, staff: widget.staff),
      if (cashier) ShiftPage(api: widget.api, admin: admin),
    ];
    restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    search.dispose();
    menuScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) loadProducts();
  }

  Future<void> restore() async {
    try {
      final draft = await store.read();
      for (final row in List<Json>.from(draft['cart'] ?? [])) {
        final line = CartLine.fromJson(row);
        cart.lines[line.id] = line;
      }
      pending = draft['pending'] == null ? null : Json.from(draft['pending']);
      if (mounted) setState(() => ready = true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'Could not restore the local draft. Restart before taking another payment.',
        );
      }
    }
    await loadProducts();
  }

  Future<void> persist() {
    writes = writes.catchError((_) {}).then((_) => store.write(cart, pending));
    return writes;
  }

  Future<void> loadProducts() async {
    if (!cashier) {
      if (mounted) setState(() => loading = false);
      return;
    }
    try {
      final loaded = <Product>[];
      for (var offset = 0; ;) {
        final rows = List<Json>.from(
          await widget.api.call('catalog', {'limit': 500, 'offset': offset}),
        );
        if (rows.isEmpty) break;
        loaded.addAll(rows.map(Product.fromJson));
        offset += rows.length;
      }
      if (mounted) {
        setState(() {
          products = loaded;
          highlightsRefresh++;
          if (ready) error = null;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = errorMessage(e);
          loading = false;
        });
      }
    }
  }

  void tell(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Semantics(liveRegion: true, child: Text(message)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> editCart(void Function() edit) async {
    if (pending != null || working || !ready) return;
    setState(edit);
    try {
      await persist();
    } catch (_) {
      tell('Draft could not be saved. Do not close the app.');
    }
  }

  Future<void> accept(Json result) async {
    // Keep recovery information in memory until clearing it is durable.
    writes = writes.catchError((_) {}).then((_) => store.write(Cart(), null));
    await writes;
    lastReceipt = result;
    pending = null;
    cart.lines.clear();
    if (mounted) setState(() {});
    await loadProducts();
  }

  Future<bool> pay(Json payment) async {
    if (pending != null) {
      throw StateError('Resolve the pending transaction first');
    }
    pending = {
      ...payment,
      'request_id': requestId(),
      'lines': cart.lines.values
          .map(
            (l) => {
              'product_id': l.id,
              'qty': l.quantity,
              'unit_minor': l.unitMinor,
            },
          )
          .toList(),
    };
    // The persistent request must be written before it can reach the database.
    try {
      await persist();
    } catch (_) {
      pending = null;
      throw StateError('Local storage failed. No payment request was sent.');
    }
    if (mounted) setState(() => working = true);
    try {
      final result = Json.from(await widget.api.call('checkout', pending!));
      await accept(result);
      return true;
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') {
        pending = null;
        await persist();
        throw StateError(e.message);
      }
      rethrow;
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<bool> recover() async {
    if (pending == null) return false;
    setState(() => working = true);
    try {
      final saved = await widget.api.call('lookup_checkout', {
        'request_id': pending!['request_id'],
      });
      final result = saved ?? await widget.api.call('checkout', pending!);
      await accept(Json.from(result));
      return true;
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') {
        pending = null;
        await persist();
        throw StateError(e.message);
      }
      rethrow;
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> checkout() async {
    await loadProducts();
    if (!mounted || error != null) return;
    final issues = cart.issues(products);
    if (issues.isNotEmpty) {
      if (await confirmAction(
        context,
        title: 'Review cart changes',
        message: issues.join('\n'),
        confirmLabel: 'Update cart',
      )) {
        await editCart(() => cart.reconcile(products));
      }
      return;
    }
    if (cart.lines.isEmpty) return;
    final shift = await widget.api.call('shift');
    if (shift == null) {
      tell('Open a cash shift before accepting payment.');
      setState(() => tab = pages.length - 1);
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      builder: (_) => CheckoutSheet(
        total: cart.total / 100,
        onPayment: pay,
        onRecover: recover,
      ),
    );
    if (mounted && lastReceipt != null) {
      final result = lastReceipt!;
      lastReceipt = null;
      await showReceipt(context, result, celebrate: true);
    }
  }

  Future<void> cartSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .75,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Review order',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final line in cart.lines.values.toList())
                      ListTile(
                        title: Text(line.name),
                        subtitle: Text('${moneyMinor(line.unitMinor)} each'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: pending != null
                                  ? null
                                  : () async {
                                      await editCart(
                                        () => cart.decrement(line.id),
                                      );
                                      if (ctx.mounted) update(() {});
                                    },
                              icon: const Icon(Icons.remove),
                            ),
                            Text('${line.quantity}'),
                            IconButton(
                              onPressed: pending != null
                                  ? null
                                  : () async {
                                      final p = products
                                          .where((p) => p.id == line.id)
                                          .firstOrNull;
                                      if (p != null) {
                                        try {
                                          await editCart(() => cart.add(p));
                                        } catch (_) {
                                          tell('Available stock reached');
                                        }
                                      }
                                      if (ctx.mounted) update(() {});
                                    },
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Total ${moneyMinor(cart.total)}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> logout() async {
    if (working) return;
    if (await confirmAction(
      context,
      title: 'Sign out?',
      message: pending != null
          ? 'A checkout is unresolved. It will be kept for this account to recover after signing in.'
          : cart.units > 0
          ? 'Your ${cart.units}-item draft will be kept for this account.'
          : 'End this session?',
      confirmLabel: 'Sign out',
    )) {
      try {
        if (ready) await persist();
        await Supabase.instance.client.auth.signOut();
      } catch (e) {
        tell(errorMessage(e));
      }
    }
  }

  Widget menu() {
    final filtered = products
        .where(
          (p) =>
              (category == 'All' || p.category == category) &&
              p.name.toLowerCase().contains(query.toLowerCase()) &&
              (availability == 'All' ||
                  (availability == 'Available' ? p.stock > 0 : p.stock == 0)),
        )
        .toList();
    final slice = PageSlice(filtered, menuPage);
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: loadProducts,
            child: CustomScrollView(
              controller: menuScroll,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PosHeader(
                          title: 'Menu',
                          subtitle:
                              '${widget.staff['name']} • ${products.length} products',
                          icon: Icons.restaurant_menu,
                          actions: IconButton(
                            tooltip: 'Refresh menu',
                            onPressed: loadProducts,
                            icon: const Icon(Icons.refresh),
                          ),
                        ),
                        if (loading) const LinearProgressIndicator(),
                        if (error != null) Text(error!),
                        const SizedBox(height: 12),
                        TodayHighlights(
                          api: widget.api,
                          refresh: highlightsRefresh,
                        ),
                        if (pending != null)
                          Card(
                            color: const Color(0xFFFCE2E8),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  const Text(
                                    'Checkout result needs checking. Your request is saved; do not create another payment for this order.',
                                  ),
                                  FilledButton(
                                    onPressed: working
                                        ? null
                                        : () async {
                                            try {
                                              if (await recover() && mounted) {
                                                await showReceipt(
                                                  context,
                                                  lastReceipt!,
                                                  celebrate: true,
                                                );
                                                lastReceipt = null;
                                              }
                                            } catch (e) {
                                              tell(
                                                e is StateError
                                                    ? e.message.toString()
                                                    : errorMessage(e),
                                              );
                                            }
                                          },
                                    child: Text(
                                      working
                                          ? 'Checking…'
                                          : 'Check / safely retry checkout',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (cart.issues(products).isNotEmpty && pending == null)
                          Text(
                            '${cart.issues(products).length} cart changes need review at checkout.',
                            style: const TextStyle(color: Colors.red),
                          ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: search,
                          onChanged: (v) => setState(() {
                            query = v;
                            menuPage = 0;
                          }),
                          decoration: const InputDecoration(
                            labelText: 'Search menu',
                            prefixIcon: Icon(Icons.search),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final c in [
                              'All',
                              ...products.map((p) => p.category).toSet(),
                            ])
                              PosFilterChip(
                                label: c,
                                selected: category == c,
                                onSelected: (_) => setState(() {
                                  category = c;
                                  menuPage = 0;
                                }),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final a in ['All', 'Available', 'Sold out'])
                              PosFilterChip(
                                label: a,
                                selected: availability == a,
                                onSelected: (_) => setState(() {
                                  availability = a;
                                  menuPage = 0;
                                }),
                              ),
                          ],
                        ),
                        PaginationBar(
                          count: filtered.length,
                          page: slice.page,
                          onChanged: (p) => setState(() => menuPage = p),
                        ),
                      ],
                    ),
                  ),
                ),
                if (filtered.isEmpty && !loading)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No products match these filters.'),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: MediaQuery.sizeOf(context).width < 360
                          ? 1
                          : MediaQuery.sizeOf(context).width > 800
                          ? 4
                          : 2,
                      mainAxisExtent: 220,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate((ctx, index) {
                      final p = slice.rows[index];
                      final qty = cart.lines[p.id]?.quantity ?? 0;
                      return Card(
                        color: qty > 0 ? const Color(0xFFFCE2E8) : Colors.white,
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.category,
                                style: const TextStyle(
                                  color: Color(0xFFE32646),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child: Text(
                                  p.name,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Text(
                                moneyMinor(p.priceMinor),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text('${p.stock} available'),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    tooltip: 'Remove one',
                                    onPressed: qty == 0 || pending != null
                                        ? null
                                        : () => editCart(
                                            () => cart.decrement(p.id),
                                          ),
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                  ),
                                  Text('$qty'),
                                  IconButton(
                                    tooltip: 'Add one',
                                    onPressed:
                                        p.stock <= qty ||
                                            pending != null ||
                                            !ready
                                        ? null
                                        : () async {
                                            try {
                                              await editCart(() => cart.add(p));
                                            } catch (_) {
                                              tell('Available stock reached');
                                            }
                                          },
                                    icon: const Icon(
                                      Icons.add_circle,
                                      color: Color(0xFFE32646),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }, childCount: slice.rows.length),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (cart.units > 0)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: cartSheet,
                      child: Text('$unitsLabel • ${moneyMinor(cart.total)}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: pending != null || working || !ready
                        ? null
                        : () async {
                            try {
                              await checkout();
                            } catch (e) {
                              tell(errorMessage(e));
                            }
                          },
                    child: const Text('Checkout'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String get unitsLabel => '${cart.units} items';
  @override
  Widget build(BuildContext context) {
    final labels = [
      if (cashier) ('Menu', Icons.restaurant_menu),
      if (admin || !cashier) ('Orders', Icons.room_service_outlined),
      if (admin) ('Stock', Icons.inventory_2_outlined),
      if (cashier) ('Reports', Icons.insights),
      if (cashier) ('Cash', Icons.point_of_sale),
    ];
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 42,
        title: Text(
          '${widget.staff['role'].toString().toUpperCase()} • Asia/Manila',
          style: const TextStyle(fontSize: 12),
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: working ? null : logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: tab,
          children: [
            for (var i = 0; i < pages.length; i++)
              TickerMode(
                enabled: i == tab,
                child: i == 0 && cashier ? menu() : pages[i],
              ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFE32646),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? Colors.white
                  : const Color(0xFF82757B),
            ),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w500,
              color: states.contains(WidgetState.selected)
                  ? const Color(0xFFE32646)
                  : const Color(0xFF82757B),
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: [
            for (final p in labels)
              NavigationDestination(icon: Icon(p.$2), label: p.$1),
          ],
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false;
  // Older login states retained by hot reload may not have this field yet.
  bool? _obscurePassword;
  bool get obscurePassword => _obscurePassword ?? true;
  set obscurePassword(bool value) => _obscurePassword = value;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email.text.trim(),
        password: password.text,
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is AuthException ? e.message : errorMessage(e),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFFF7F8),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: BrandLogo(size: 200)),
                const SizedBox(height: 8),
                const Text(
                  'HANKATSU POS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF191519),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'GOOD FOOD. GREAT SERVICE.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF82757B),
                    fontSize: 10,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFF0DFE3)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0C191519),
                        blurRadius: 28,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Start your shift',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF191519),
                              letterSpacing: -0.6,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Sign in to your staff account to continue.',
                            style: TextStyle(
                              color: Color(0xFF82757B),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextField(
                            controller: email,
                            enabled: !busy,
                            autocorrect: false,
                            textInputAction: TextInputAction.next,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: _loginInput(
                              'Email',
                              Icons.mail_outline,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: password,
                            enabled: !busy,
                            obscureText: obscurePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onSubmitted: (_) => login(),
                            decoration:
                                _loginInput(
                                  'Password',
                                  Icons.lock_outline,
                                ).copyWith(
                                  suffixIcon: IconButton(
                                    tooltip: obscurePassword
                                        ? 'Show password'
                                        : 'Hide password',
                                    onPressed: busy
                                        ? null
                                        : () => setState(
                                            () => obscurePassword =
                                                !obscurePassword,
                                          ),
                                    icon: Icon(
                                      obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      size: 20,
                                    ),
                                  ),
                                ),
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  error!,
                                  style: const TextStyle(
                                    color: Color(0xFFB51D38),
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 24),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFE32646),
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: busy ? null : login,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (busy) ...[
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Text(
                                  busy ? 'Signing in…' : 'Sign in',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (!busy) ...[
                                  const SizedBox(width: 10),
                                  const Icon(Icons.arrow_forward, size: 18),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Made for good food and smooth shifts.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF82757B), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  InputDecoration _loginInput(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 20, color: const Color(0xFF82757B)),
    filled: true,
    fillColor: const Color(0xFFFFF7F8),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFF0DFE3)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE32646), width: 2),
    ),
  );
}
