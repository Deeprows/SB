import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/ad_scheduler.dart';
import '../services/install_id.dart';
import '../services/remote_config.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';
import 'browser_screen.dart' show openExternally;
import 'paystack_checkout_screen.dart';

/// Builds the WhatsApp link for people who pay manually. The person's ID is
/// added to the message so the new subscription can be switched on for the
/// right phone. Returns null while no WhatsApp address is set.
Uri? buildWhatsappUri(String baseUrl, String message, String installId) {
  final base = baseUrl.trim();
  if (base.isEmpty) return null;
  final uri = Uri.tryParse(base);
  if (uri == null) return null;
  return uri.replace(queryParameters: {
    ...uri.queryParameters,
    'text': '$message\n\nMy ID: $installId',
  });
}

/// Free or Premium. Used as the start page ([onContinue] set) and, from the
/// menu or the ad page, as a normal page that closes with the back button.
class PlansScreen extends StatefulWidget {
  final VoidCallback? onContinue;
  const PlansScreen({super.key, this.onContinue});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  final _sub = SubscriptionService.instance;
  final _email = TextEditingController();

  PlanInfo _plan = PlanInfo.fallback();
  String _installId = '';
  bool _auto = false;
  bool _yearly = false;
  String _method = 'card'; // card | ussd | bank_transfer | any
  bool _busy = false;
  String? _error;

  bool get _startup => widget.onContinue != null;

  @override
  void initState() {
    super.initState();
    AdScheduler.instance.hold(); // no ad pop-up while choosing / paying
    _sub.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    _sub.removeListener(_changed);
    AdScheduler.instance.release();
    _email.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final id = await InstallId.get();
    final mail = await _sub.savedEmail();
    if (!mounted) return;
    setState(() {
      _installId = id;
      if (_email.text.isEmpty) _email.text = mail;
    });
    final plan = await _sub.loadPlan();
    unawaited(_sub.refresh(force: true));
    if (mounted) setState(() => _plan = plan);
  }

  void _continue() {
    if (_startup) {
      widget.onContinue!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------------------------------------------------------------- actions

  Future<void> _subscribe() async {
    if (_busy) return;
    final mail = _email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(mail)) {
      setState(() => _error = 'Enter a valid e-mail address (for your receipt)');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final start = await _sub.startCheckout(
        email: mail,
        recurring: _auto && _canAuto,
        period: _yearly ? 'year' : 'month',
        channels: _channels,
      );
      if (!mounted) return;
      final doneUrl =
          '${AppConfig.feedBase.trim().replaceAll(RegExp(r'/+$'), '')}/sub/done';
      await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => PaystackCheckoutScreen(
          url: start.url,
          doneUrlPrefix: doneUrl,
        ),
      ));
      if (!mounted) return;
      // Closed or finished: ask the Worker either way.
      final result = await _sub.confirm(start.reference);
      if (!mounted) return;
      switch (result) {
        case PaymentResult.active:
          await _showAccessCode(start.reference, mail);
        case PaymentResult.pending:
          _toast('Your payment is still being confirmed. It switches on '
              'by itself in a few minutes.');
        case PaymentResult.failed:
          _toast('No payment was received.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Auto-renew exists only for cards and only when a plan code is set.
  bool get _canAuto =>
      _method == 'card' && (_yearly ? _plan.recurringYear : _plan.recurring);

  List<String> get _channels => switch (_method) {
        'card' => const ['card'],
        'ussd' => const ['ussd'],
        'bank_transfer' => const ['bank_transfer'],
        _ => const [],
      };

  String get _shownPrice => _yearly ? _plan.yearPriceDisplay : _plan.priceDisplay;
  String? get _shownLocal => _yearly ? _plan.yearLocalDisplay : _plan.localDisplay;
  String get _perLabel => _yearly ? 'year' : 'month';

  Future<void> _whatsapp() async {
    final uri = buildWhatsappUri(
        AppConfig.whatsappUrl, AppConfig.whatsappMessage, _installId);
    if (uri == null) {
      _toast('WhatsApp payment will be available soon.');
      return;
    }
    if (!await openExternally(uri.toString()) && mounted) {
      _toast('Could not open WhatsApp');
    }
  }

  Future<void> _restore() async {
    final mail = TextEditingController(text: _email.text);
    final ref = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Ui.panel,
        title: const Text('Restore Premium'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Paid on another phone? Enter the e-mail you paid with and the '
              'payment reference from your Paystack receipt.',
              style: TextStyle(color: Ui.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: mail,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail'),
            ),
            TextField(
              controller: ref,
              decoration: const InputDecoration(labelText: 'Payment reference'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore')),
        ],
      ),
    );
    final email = mail.text.trim();
    final reference = ref.text.trim();
    mail.dispose();
    ref.dispose();
    if (go != true || !mounted) return;
    setState(() => _busy = true);
    final err = await _sub.restore(email: email, reference: reference);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(err ?? 'Premium restored. Thank you! 💗');
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final premium = _sub.isPremium;
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: _startup
          ? null
          : AppBar(
              backgroundColor: Ui.bg,
              title: const Text('Plans',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
              children: [
                if (_startup) ...[
                  Image.asset('assets/splash/splash.png',
                      height: 84, fit: BoxFit.contain),
                  const SizedBox(height: 6),
                ],
                Text(
                  premium ? 'You are Premium' : 'Choose your plan',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 14),
                if (premium) _activeCard(),
                _premiumCard(premium),
                const SizedBox(height: 12),
                if (!premium) _freeCard() else _continueButton('Continue'),
                const SizedBox(height: 14),
                _manualCard(),
                const SizedBox(height: 6),
                Center(
                  child: TextButton(
                    onPressed: _busy ? null : _restore,
                    child: Text('Restore purchase',
                        style: TextStyle(color: Ui.muted)),
                  ),
                ),
                _idLine(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _box({required Widget child, bool highlight = false}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Ui.panel,
          gradient: highlight
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Ui.red.withValues(alpha: .16), Ui.panel, Ui.panel],
                  stops: const [0, .55, 1],
                )
              : null,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
              color: highlight ? Ui.red.withValues(alpha: .5) : Ui.line,
              width: highlight ? 1.3 : 1),
        ),
        child: child,
      );

  Widget _activeCard() {
    final d = _sub.expiresAt;
    final date = d == null
        ? ''
        : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _box(
        child: Row(children: [
          Icon(Icons.verified_rounded, color: Ui.green, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Premium is active',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text('No ads until $date',
                    style: TextStyle(color: Ui.muted, fontSize: 13)),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _premiumCard(bool premium) {
    Widget feature(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Icon(Icons.check_circle_rounded, size: 18, color: Ui.green),
            const SizedBox(width: 8),
            Expanded(
                child: Text(t,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600))),
          ]),
        );

    return _box(
      highlight: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [Ui.red, Ui.redSoft]),
              ),
              child: const Icon(Icons.workspace_premium_rounded,
                  color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Premium',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Ui.red.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text('NO ADS',
                  style: TextStyle(
                      color: Ui.redSoft,
                      fontSize: 11,
                      fontWeight: FontWeight.w900)),
            ),
          ]),
          const SizedBox(height: 12),
          _periodToggle(),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(_shownPrice,
                  style: const TextStyle(
                      fontSize: 32, fontWeight: FontWeight.w900)),
              Text('  / $_perLabel',
                  style: TextStyle(color: Ui.muted, fontSize: 14)),
            ],
          ),
          if (_shownLocal != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('≈ $_shownLocal / $_perLabel in your currency',
                  style: TextStyle(
                      color: Ui.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 12),
          feature('No pop-ups'),
          feature('Stream without interruptions'),
          feature('Pay with card, USSD or bank transfer'),
          feature('Monthly or yearly (save with yearly)'),
          const SizedBox(height: 8),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: 'Your e-mail (for the receipt)',
              prefixIcon: const Icon(Icons.mail_outline_rounded),
              errorText: _error,
              errorMaxLines: 3,
            ),
          ),
          if (_canAuto)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _auto,
              onChanged: _busy ? null : (v) => setState(() => _auto = v),
              title: Text('Renew automatically every $_perLabel',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              subtitle: Text('Card only. Otherwise pay again each $_perLabel.',
                  style: TextStyle(color: Ui.muted, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          _paystackStrip(),
          const SizedBox(height: 10),
          _methodPicker(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: LinearGradient(colors: [Ui.red, Ui.redSoft]),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(26),
                  onTap: (_busy || !_plan.available) ? null : _subscribe,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white))
                          : Text(
                              premium
                                  ? 'Add 1 more $_perLabel'
                                  : 'Pay  •  $_shownPrice/$_perLabel',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
                'Pay securely with Paystack. Premium turns on automatically '
                'and your receipt is sent to your e-mail.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.3)),
          ),
          if (!_plan.available)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Online payment is not available right now. '
                  'Use WhatsApp below.',
                  style: TextStyle(color: Ui.muted, fontSize: 12.5)),
            ),
        ],
      ),
    );
  }

  Widget _periodToggle() {
    Widget tab(String label, bool yearly, {String? badge}) {
      final on = _yearly == yearly;
      return Expanded(
        child: GestureDetector(
          onTap: _busy ? null : () => setState(() => _yearly = yearly),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: on ? Ui.red.withValues(alpha: .22) : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: on ? Ui.red : Colors.transparent, width: 1.2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: on ? FontWeight.w900 : FontWeight.w700,
                        color: on ? null : Ui.muted)),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Ui.green.withValues(alpha: .2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(badge,
                        style: TextStyle(
                            color: Ui.green,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900)),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final save = _plan.yearSavingPercent;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Ui.bg.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: Ui.line),
      ),
      child: Row(children: [
        tab('Monthly', false),
        tab('Yearly', true, badge: save > 0 ? 'SAVE $save%' : null),
      ]),
    );
  }

  Widget _methodPicker() {
    Widget chip(String id, IconData icon, String label) {
      final on = _method == id;
      return ChoiceChip(
        avatar: Icon(icon, size: 16, color: on ? Colors.white : Ui.muted),
        label: Text(label),
        selected: on,
        showCheckmark: false,
        selectedColor: Ui.red,
        backgroundColor: Ui.bg.withValues(alpha: .5),
        side: BorderSide(color: on ? Ui.red : Ui.line),
        labelStyle: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: on ? Colors.white : null),
        onSelected: _busy ? null : (_) => setState(() => _method = id),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pay with',
            style: TextStyle(
                color: Ui.muted, fontSize: 12.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          chip('card', Icons.credit_card_rounded, 'Card'),
          chip('ussd', Icons.dialpad_rounded, 'USSD'),
          chip('bank_transfer', Icons.account_balance_rounded, 'Bank transfer'),
          chip('any', Icons.apps_rounded, 'All options'),
        ]),
      ],
    );
  }

  /// Shows that checkout is run by Paystack (card, bank transfer, USSD).
  Widget _paystackStrip() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Ui.bg.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Ui.line),
        ),
        child: Row(children: [
          Icon(Icons.lock_rounded, size: 18, color: Ui.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: 'Secured by ',
                    style: TextStyle(color: Ui.muted, fontSize: 12.5)),
                const TextSpan(
                    text: 'Paystack',
                    style: TextStyle(
                        color: Color(0xFF00C3F7),
                        fontSize: 14,
                        fontWeight: FontWeight.w900)),
              ]),
            ),
          ),
          Text('Card • USSD • Transfer',
              style: TextStyle(
                  color: Ui.muted, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );

  /// Shown once a payment succeeds: the payment reference is the access
  /// code (works with "Restore purchase" on any phone).
  Future<void> _showAccessCode(String reference, String email) async {
    if (reference.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Ui.panel,
        title: const Text('Payment received 🎉'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Premium is on. Your access code:',
                style: TextStyle(color: Ui.muted, fontSize: 13)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Ui.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Ui.line),
              ),
              child: SelectableText(reference,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 10),
            Text(
                'Your receipt was sent to $email. Keep this code: use '
                '"Restore purchase" with it if you change phone.',
                style: TextStyle(color: Ui.muted, fontSize: 12.5, height: 1.3)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: reference));
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) _toast('Access code copied');
              },
              child: const Text('Copy')),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  }

  Widget _freeCard() {
    final m = RemoteConfig.instance.adIntervalMinutes;
    return _box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Free',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            'Everything is open. A short “Support” page shows every $m '
            'minutes of use.',
            style: TextStyle(color: Ui.muted, fontSize: 13.5, height: 1.25),
          ),
          const SizedBox(height: 12),
          _continueButton(_startup ? 'Continue with ads' : 'Maybe later'),
        ],
      ),
    );
  }

  Widget _continueButton(String label) => SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _busy ? null : _continue,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 13),
            side: BorderSide(color: Ui.line),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 15.5, fontWeight: FontWeight.w800)),
        ),
      );

  Widget _manualCard() => _box(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Can't pay online?",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'Chat with us on WhatsApp and pay manually. We switch Premium '
              'on for you.',
              style: TextStyle(color: Ui.muted, fontSize: 13, height: 1.25),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _whatsapp,
                icon: Icon(Icons.chat_rounded, color: Ui.green),
                label: const Text('Pay manually on WhatsApp',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: Ui.green.withValues(alpha: .7)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _idLine() {
    if (_installId.isEmpty) return const SizedBox.shrink();
    return Center(
      child: InkWell(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: _installId));
          if (mounted) _toast('ID copied');
        },
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Text(
              'Your ID: ${_installId.length > 8 ? _installId.substring(0, 8) : _installId}…  (tap to copy)',
              style: TextStyle(color: Ui.dim, fontSize: 11.5)),
        ),
      ),
    );
  }
}
