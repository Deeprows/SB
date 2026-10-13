import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/app_theme.dart';

/// Paystack's secure checkout inside the app. When Paystack sends the person
/// back to our "payment finished" address the window closes by itself.
///
/// Pops `true` when the finished page was reached, `false` when the person
/// closed the window first. Either way the caller still asks the Worker
/// whether the payment went through (someone may have paid and then closed).
class PaystackCheckoutScreen extends StatefulWidget {
  final String url;

  /// Address prefix that means "payment finished" (the Worker's /sub/done).
  final String doneUrlPrefix;

  const PaystackCheckoutScreen({
    super.key,
    required this.url,
    required this.doneUrlPrefix,
  });

  @override
  State<PaystackCheckoutScreen> createState() => _PaystackCheckoutScreenState();
}

class _PaystackCheckoutScreenState extends State<PaystackCheckoutScreen> {
  late final WebViewController _wc;
  bool _loading = true;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Ui.bg)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) {
          if (r.url.startsWith(widget.doneUrlPrefix)) {
            _finish();
            return NavigationDecision.prevent;
          }
          final scheme = Uri.tryParse(r.url)?.scheme.toLowerCase() ?? '';
          // Card / transfer / USSD pages are all web pages.
          if (scheme == 'http' || scheme == 'https' || scheme == 'about') {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.panel,
        title: const Text('Secure payment',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Row(children: [
              Icon(Icons.lock_rounded, size: 15, color: Ui.green),
              const SizedBox(width: 4),
              Text('Paystack',
                  style: TextStyle(color: Ui.muted, fontSize: 12.5)),
            ]),
          ),
        ],
        bottom: _loading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                    minHeight: 2, color: Ui.red, backgroundColor: Ui.line),
              )
            : null,
      ),
      body: WebViewWidget(controller: _wc),
    );
  }
}
