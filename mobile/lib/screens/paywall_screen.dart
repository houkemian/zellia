import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../services/api_service.dart';
import '../services/revenuecat_service.dart';

const _kPrimary = Color(0xFF5EC397);
const _kPrimaryDark = Color(0xFF3FAE82);
const _kSurface = Color(0xFFF4FBF7);
const _kStroke = Color(0xFFBFDFD1);
const _kTextStrong = Color(0xFF214438);
const _kTextMuted = Color(0xFF5E8274);
const _kCheckGreen = Color(0xFF0E6A55);

/// PRO subscription paywall: slogan, checklist, RevenueCat packages, purchase overlay.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, required this.api});

  final ApiService api;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  Offerings? _offerings;
  bool _loadingOfferings = true;
  String? _offeringsError;
  bool _purchaseOverlay = false;

  @override
  void initState() {
    super.initState();
    setState(() {
      _loadingOfferings = true;
      _offeringsError = null;
    });
    Future.microtask(() async {
      try {
        if (!RevenueCatService.instance.isConfigured) {
          await RevenueCatService.instance.init();
        }
        final offerings = await RevenueCatService.instance.getOfferings();
        if (!mounted) return;
        setState(() => _offerings = offerings);
      } catch (e) {
        if (!mounted) return;
        setState(() => _offeringsError = e.toString());
      } finally {
        if (mounted) setState(() => _loadingOfferings = false);
      }
    });
  }

  String _t(String zh, String en) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    return code.startsWith('zh') ? zh : en;
  }

  List<Package> _sortedPackages() {
    final list = List<Package>.from(
      _offerings?.current?.availablePackages ?? const <Package>[],
    );
    int order(Package p) {
      final t = p.packageType;
      if (t == PackageType.monthly) return 0;
      if (t == PackageType.annual) return 1;
      if (t == PackageType.weekly) return -1;
      if (t == PackageType.sixMonth) return 2;
      if (t == PackageType.threeMonth) return 3;
      if (t == PackageType.twoMonth) return 4;
      if (t == PackageType.lifetime) return 99;
      return 50;
    }

    list.sort((a, b) => order(a).compareTo(order(b)));
    return list;
  }

  String _packagePeriodLabel(Package p) {
    final t = p.packageType;
    if (t == PackageType.monthly) return _t('月度订阅', 'Monthly');
    if (t == PackageType.annual) return _t('年度订阅', 'Annual');
    if (t == PackageType.weekly) return _t('周订阅', 'Weekly');
    if (t == PackageType.sixMonth) return _t('半年订阅', '6 months');
    if (t == PackageType.threeMonth) return _t('季度订阅', '3 months');
    if (t == PackageType.twoMonth) return _t('两月订阅', '2 months');
    if (t == PackageType.lifetime) return _t('终身买断', 'Lifetime');
    return p.identifier;
  }

  Future<void> _showAlert(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: _kTextStrong,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(
            fontSize: 18,
            height: 1.4,
            color: _kTextMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: _kPrimaryDark,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(_t('知道了', 'OK'), style: const TextStyle(fontSize: 17)),
          ),
        ],
      ),
    );
  }

  bool _isNetworkish(Object e) {
    final s = e.toString().toLowerCase();
    return e is SocketException ||
        e is TimeoutException ||
        s.contains('network') ||
        s.contains('timeout') ||
        s.contains('timed out') ||
        s.contains('connection');
  }

  Future<void> _onPurchase(Package package) async {
    setState(() => _purchaseOverlay = true);
    try {
      await RevenueCatService.instance
          .purchasePackage(package)
          .timeout(const Duration(seconds: 120));
      try {
        await widget.api.getCurrentUserProfile();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PlatformException catch (e) {
      if (!mounted) return;
      final mapped = RevenueCatService.mapPurchaseError(e);
      if (mapped == PurchaseFlowError.cancelled) {
        await _showAlert(
          _t('已取消', 'Cancelled'),
          _t('您已取消本次购买，如需 PRO 可随时再来。', 'You cancelled the purchase.'),
        );
      } else if (mapped == PurchaseFlowError.network) {
        await _showAlert(
          _t('网络异常', 'Network error'),
          _t(
            '无法连接商店或网络超时，请检查网络后重试。',
            'Could not reach the store. Check your connection and try again.',
          ),
        );
      } else if (mapped == PurchaseFlowError.store) {
        await _showAlert(
          _t('商店暂不可用', 'Store issue'),
          _t(
            '应用商店暂时无法完成操作，请稍后再试。',
            'The store could not complete the action. Try again later.',
          ),
        );
      } else {
        await _showAlert(
          _t('购买未完成', 'Purchase incomplete'),
          (e.message?.trim().isNotEmpty == true)
              ? e.message!.trim()
              : _t('请稍后再试。', 'Please try again later.'),
        );
      }
    } on TimeoutException {
      if (!mounted) return;
      await _showAlert(
        _t('请求超时', 'Request timed out'),
        _t(
          '支付处理超时，请检查网络后重试；若已扣款请稍后在订阅管理中确认。',
          'The request timed out. Check your network and try again.',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (_isNetworkish(e)) {
        await _showAlert(
          _t('网络异常', 'Network error'),
          _t(
            '网络不稳定或超时，请稍后再试。',
            'The network is unstable or timed out. Try again.',
          ),
        );
      } else {
        await _showAlert(
          _t('购买失败', 'Purchase failed'),
          e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _purchaseOverlay = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final packages = _sortedPackages();

    return Scaffold(
      backgroundColor: _kSurface,
      appBar: AppBar(
        title: Text(
          _t('岁月安 PRO', 'Zellia PRO'),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 21),
        ),
        backgroundColor: _kSurface,
        foregroundColor: _kTextStrong,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
            children: [
              Text(
                _t('守护家人健康，解锁 PRO 专业版', 'Care for family health — unlock PRO'),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: _kTextStrong,
                  height: 1.22,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _t(
                  '极简界面、浅绿护眼、大字号高对比度，专为长辈与家人设计。',
                  'Minimal layout, soft greens, large high-contrast type for elders and families.',
                ),
                style: const TextStyle(
                  fontSize: 17,
                  height: 1.45,
                  color: _kTextMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 22),
              _ProChecklistCard(t: _t),
              const SizedBox(height: 26),
              Text(
                _t('选择订阅', 'Choose subscription'),
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: _kTextStrong,
                ),
              ),
              const SizedBox(height: 10),
              if (_loadingOfferings)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        strokeWidth: 3.5,
                        color: _kPrimaryDark,
                      ),
                    ),
                  ),
                )
              else if (_offeringsError != null)
                Text(
                  _t('无法加载价格：$_offeringsError', 'Could not load prices: $_offeringsError'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFB00020),
                    height: 1.35,
                  ),
                )
              else if (packages.isEmpty)
                Text(
                  _t(
                    '暂未配置订阅商品。请在 RevenueCat 与商店后台完成 Offering 与商品价格。',
                    'No packages yet. Configure offerings and products in RevenueCat and the store.',
                  ),
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1.4,
                    color: _kTextMuted,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                ...packages.map((pkg) {
                  final period = _packagePeriodLabel(pkg);
                  final title = pkg.storeProduct.title.trim().isEmpty
                      ? period
                      : pkg.storeProduct.title.trim();
                  final price = pkg.storeProduct.priceString;
                  final subtitle = '$period · $price';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FilledButton(
                      onPressed: _purchaseOverlay ? null : () => _onPurchase(pkg),
                      style: FilledButton.styleFrom(
                        backgroundColor: _kPrimaryDark,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _kPrimary.withOpacity(0.45),
                        elevation: 2,
                        shadowColor: const Color(0x5545A97F),
                        padding: const EdgeInsets.symmetric(
                          vertical: 18,
                          horizontal: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFE8FFF4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 14),
              Text(
                _t(
                  '价格以应用商店展示为准。购买即表示同意商店条款；可在系统订阅管理中管理或取消续订。',
                  'Prices are set by the store. Purchases are subject to store terms.',
                ),
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: _kTextMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (_purchaseOverlay) _PurchaseLoadingOverlay(t: _t),
        ],
      ),
    );
  }
}

class _PurchaseLoadingOverlay extends StatelessWidget {
  const _PurchaseLoadingOverlay({required this.t});

  final String Function(String zh, String en) t;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.38),
          ),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kStroke, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      color: _kPrimaryDark,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    t('正在处理支付…', 'Processing payment…'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _kTextStrong,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t('请稍候，勿关闭本页', 'Please wait, do not leave this page'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _kTextMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProChecklistCard extends StatelessWidget {
  const _ProChecklistCard({required this.t});

  final String Function(String zh, String en) t;

  @override
  Widget build(BuildContext context) {
    final items = <_CheckItem>[
      _CheckItem(
        title: t('多成员实时同步', 'Multi-member live sync'),
        subtitle: t('全家共同守护长辈。', 'The whole family cares for elders together.'),
      ),
      _CheckItem(
        title: t('无限历史记录', 'Unlimited history'),
        subtitle: t(
          '永久保留血压、用药趋势。',
          'Keep BP and medication trends over the long term.',
        ),
      ),
      _CheckItem(
        title: t('高级异常预警', 'Advanced anomaly alerts'),
        subtitle: t(
          '检测到数值异常时自动推送。',
          'Automatic push when readings look abnormal.',
        ),
      ),
      _CheckItem(
        title: t('一键就医 PDF 报表', 'One-tap clinical PDF'),
        subtitle: t(
          '免去手工整理，医生看得准。',
          'No manual prep — clear for your doctor.',
        ),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kStroke, width: 1.4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F7EF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF9EDCC4)),
                ),
                child: Text(
                  'PRO',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: _kCheckGreen,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t('专业版包含', 'PRO includes'),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: _kTextStrong,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...items.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _ChecklistRow(item: e),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckItem {
  const _CheckItem({required this.title, required this.subtitle});

  final String title;
  final String subtitle;
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.item});

  final _CheckItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.check_circle_rounded,
          color: _kCheckGreen,
          size: 30,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                  color: _kTextStrong,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.subtitle,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: _kTextMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
