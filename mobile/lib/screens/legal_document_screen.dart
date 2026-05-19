import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../constants/legal_urls.dart';

/// In-app browser for Terms of Service or Privacy Policy.
class LegalDocumentScreen extends StatefulWidget {
  const LegalDocumentScreen({
    super.key,
    required this.url,
    required this.title,
  });

  final String url;
  final String title;

  static Future<void> openTerms(BuildContext context, String title) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentScreen(
          url: LegalUrls.termsOfService,
          title: title,
        ),
      ),
    );
  }

  static Future<void> openPrivacy(BuildContext context, String title) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentScreen(
          url: LegalUrls.privacyPolicy,
          title: title,
        ),
      ),
    );
  }

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  late final WebViewController _controller;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
