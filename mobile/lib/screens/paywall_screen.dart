import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../services/api_service.dart';
import '../services/revenuecat_service.dart';

// ── palette ────────────────────────────────────────────────────────────────────
const _kPrimary     = Color(0xFF5EC397);
const _kPrimaryDark = Color(0xFF3FAE82);
const _kHeroDeep    = Color(0xFF0D3422);
const _kHeroMid     = Color(0xFF1C6443);
const _kSurface     = Color(0xFFF4FBF7);
const _kStroke      = Color(0xFFBFDFD1);
const _kTextStrong  = Color(0xFF1A3D2E);
const _kTextMuted   = Color(0xFF5E8274);
const _kCheckGreen  = Color(0xFF0E6A55);
const _kGold        = Color(0xFFD4830A);
const _kGoldBg      = Color(0xFFFFF3DC);
const _kGoldBorder  = Color(0xFFE8A020);

// ── main screen ────────────────────────────────────────────────────────────────
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
  Package? _selectedPackage;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    try {
      if (!RevenueCatService.instance.isConfigured) {
        await RevenueCatService.instance.init();
      }
      final offerings = await RevenueCatService.instance.getOfferings();
      if (!mounted) return;
      final packages = _sortedFrom(offerings);
      setState(() {
        _offerings = offerings;
        if (packages.isNotEmpty) {
          _selectedPackage = packages.firstWhere(
            (p) => p.packageType == PackageType.annual,
            orElse: () => packages.first,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _offeringsError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingOfferings = false);
    }
  }

  String _t(String zh, String en) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    return code.startsWith('zh') ? zh : en;
  }

  List<Package> _sortedFrom(Offerings? offerings) {
    final list = List<Package>.from(
      offerings?.current?.availablePackages ?? const <Package>[],
    );
    int order(Package p) {
      final t = p.packageType;
      if (t == PackageType.weekly)     return -1;
      if (t == PackageType.monthly)    return 0;
      if (t == PackageType.annual)     return 1;
      if (t == PackageType.sixMonth)   return 2;
      if (t == PackageType.threeMonth) return 3;
      if (t == PackageType.twoMonth)   return 4;
      if (t == PackageType.lifetime)   return 99;
      return 50;
    }
    list.sort((a, b) => order(a).compareTo(order(b)));
    return list;
  }

  List<Package> _sortedPackages() => _sortedFrom(_offerings);

  String _periodLabel(Package p) {
    final t = p.packageType;
    if (t == PackageType.weekly)     return _t('周订阅', 'Weekly');
    if (t == PackageType.monthly)    return _t('月度', 'Monthly');
    if (t == PackageType.annual)     return _t('年度', 'Annual');
    if (t == PackageType.sixMonth)   return _t('半年', '6 Months');
    if (t == PackageType.threeMonth) return _t('季度', 'Quarterly');
    if (t == PackageType.twoMonth)   return _t('两月', '2 Months');
    if (t == PackageType.lifetime)   return _t('终身', 'Lifetime');
    return p.identifier;
  }

  bool _isBestValue(Package p) => p.packageType == PackageType.annual;

  Future<void> _showAlert(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _kTextStrong,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(
            fontSize: 16,
            height: 1.45,
            color: _kTextMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: _kPrimaryDark,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              _t('知道了', 'Got it'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
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

  Future<void> _onPurchase() async {
    final package = _selectedPackage;
    if (package == null) return;
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
          _t('网络异常', 'Network Error'),
          _t(
            '无法连接商店或网络超时，请检查网络后重试。',
            'Could not reach the store. Check your connection and try again.',
          ),
        );
      } else if (mapped == PurchaseFlowError.store) {
        await _showAlert(
          _t('商店暂不可用', 'Store Issue'),
          _t(
            '应用商店暂时无法完成操作，请稍后再试。',
            'The store could not complete the action. Try again later.',
          ),
        );
      } else {
        await _showAlert(
          _t('购买未完成', 'Purchase Incomplete'),
          (e.message?.trim().isNotEmpty == true)
              ? e.message!.trim()
              : _t('请稍后再试。', 'Please try again later.'),
        );
      }
    } on TimeoutException {
      if (!mounted) return;
      await _showAlert(
        _t('请求超时', 'Request Timed Out'),
        _t(
          '支付处理超时，请检查网络后重试；若已扣款请稍后在订阅管理中确认。',
          'The request timed out. Check your network and try again.',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (_isNetworkish(e)) {
        await _showAlert(
          _t('网络异常', 'Network Error'),
          _t('网络不稳定或超时，请稍后再试。', 'The network is unstable. Try again.'),
        );
      } else {
        await _showAlert(_t('购买失败', 'Purchase Failed'), e.toString());
      }
    } finally {
      if (mounted) setState(() => _purchaseOverlay = false);
    }
  }

  Future<void> _onRestorePurchases() async {
    setState(() => _purchaseOverlay = true);
    try {
      final info = await Purchases.restorePurchases();
      if (!mounted) return;
      if (info.entitlements.active.isNotEmpty) {
        try {
          await widget.api.getCurrentUserProfile();
        } catch (_) {}
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        await _showAlert(
          _t('未找到订阅', 'No Subscription Found'),
          _t(
            '未找到可恢复的有效订阅，请确认购买时使用的账号。',
            'No active subscription to restore. Check the account used for the original purchase.',
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      await _showAlert(_t('恢复失败', 'Restore Failed'), e.toString());
    } finally {
      if (mounted) setState(() => _purchaseOverlay = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final packages   = _sortedPackages();
    final topPad     = MediaQuery.of(context).padding.top;
    final bottomPad  = MediaQuery.of(context).padding.bottom;
    final canPurchase =
        _selectedPackage != null && !_purchaseOverlay && !_loadingOfferings;

    return Scaffold(
      backgroundColor: _kSurface,
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _HeroSection(
                        t: _t,
                        topPad: topPad,
                        onClose: () => Navigator.of(context).pop(),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                        child: _FeaturesSection(t: _t),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                        child: _PackagesSection(
                          t: _t,
                          packages: packages,
                          selectedPackage: _selectedPackage,
                          loading: _loadingOfferings,
                          error: _offeringsError,
                          isBestValue: _isBestValue,
                          periodLabel: _periodLabel,
                          onSelect: (p) => setState(() => _selectedPackage = p),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _BottomCTASection(
                t: _t,
                bottomPad: bottomPad,
                canPurchase: canPurchase,
                loading: _loadingOfferings,
                selectedPackage: _selectedPackage,
                periodLabel: _periodLabel,
                onPurchase: _onPurchase,
                onRestore: _onRestorePurchases,
              ),
            ],
          ),
          if (_purchaseOverlay) _PurchaseLoadingOverlay(t: _t),
        ],
      ),
    );
  }
}

// ── hero section ───────────────────────────────────────────────────────────────
class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.t,
    required this.topPad,
    required this.onClose,
  });

  final String Function(String zh, String en) t;
  final double topPad;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kHeroDeep, _kHeroMid],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      padding: EdgeInsets.fromLTRB(24, topPad + 12, 24, 44),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: onClose,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.12),
              boxShadow: [
                BoxShadow(
                  color: _kPrimary.withOpacity(0.6),
                  blurRadius: 52,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              color: Colors.white,
              size: 50,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            decoration: BoxDecoration(
              color: _kGold,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'PRO',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            t('守护家人健康，全力以赴', 'Care for Family Health, Fully Empowered'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            t(
              '解锁专业版，多成员协同、数据无限、智能预警一键就位',
              'Unlock PRO for family sync, unlimited data & smart health alerts',
            ),
            style: TextStyle(
              color: Colors.white.withOpacity(0.78),
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── features section ───────────────────────────────────────────────────────────
class _FeatureData {
  const _FeatureData({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
}

class _FeaturesSection extends StatelessWidget {
  const _FeaturesSection({required this.t});

  final String Function(String zh, String en) t;

  @override
  Widget build(BuildContext context) {
    final items = [
      _FeatureData(
        icon: Icons.people_alt_rounded,
        iconColor: const Color(0xFF3FAE82),
        iconBg: const Color(0xFFE6F7EF),
        title: t('家庭多成员协同', 'Family Multi-Member Sync'),
        subtitle: t('全家共同守护长辈健康。', 'The whole family cares for elders together.'),
      ),
      _FeatureData(
        icon: Icons.bar_chart_rounded,
        iconColor: const Color(0xFF1A8FA6),
        iconBg: const Color(0xFFDFF5FA),
        title: t('无限历史记录', 'Unlimited History'),
        subtitle: t('永久保留血压、用药长期趋势。', 'Long-term BP and medication tracking.'),
      ),
      _FeatureData(
        icon: Icons.notifications_active_rounded,
        iconColor: const Color(0xFFD4830A),
        iconBg: const Color(0xFFFFF3DC),
        title: t('智能异常预警', 'Smart Anomaly Alerts'),
        subtitle: t('检测异常时自动推送家庭通知。', 'Auto-push when readings look abnormal.'),
      ),
      _FeatureData(
        icon: Icons.picture_as_pdf_rounded,
        iconColor: const Color(0xFF7550C8),
        iconBg: const Color(0xFFF0EBFF),
        title: t('一键就医 PDF 报表', 'One-Tap Clinical PDF'),
        subtitle: t('免去手工整理，医生看得准。', 'Clear report ready for your doctor.'),
      ),
      _FeatureData(
        icon: Icons.view_quilt_rounded,
        iconColor: const Color(0xFF00838F),
        iconBg: const Color(0xFFE0F7FA),
        title: t('桌面与锁屏实时挂件矩阵', 'Desktop & Lock Screen Widget Matrix'),
        subtitle: t(
          '关键用药与健康信息常驻桌面与锁屏，抬眼即见。（即将推出）',
          'Medication and health essentials on your home & lock screen—glanceable anytime. (Coming soon)',
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('PRO 专业版包含', "What's Included in PRO"),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _kTextStrong,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 18,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final i    = entry.key;
              final item = entry.value;
              final isLast = i == items.length - 1;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: item.iconBg,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(item.icon, color: item.iconColor, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: _kTextStrong,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item.subtitle,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: _kTextMuted,
                                  fontWeight: FontWeight.w500,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    const Divider(
                      height: 1,
                      indent: 82,
                      endIndent: 18,
                      color: Color(0xFFEDF5F0),
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ── packages section ───────────────────────────────────────────────────────────
class _PackagesSection extends StatelessWidget {
  const _PackagesSection({
    required this.t,
    required this.packages,
    required this.selectedPackage,
    required this.loading,
    required this.error,
    required this.isBestValue,
    required this.periodLabel,
    required this.onSelect,
  });

  final String Function(String zh, String en) t;
  final List<Package> packages;
  final Package? selectedPackage;
  final bool loading;
  final String? error;
  final bool Function(Package) isBestValue;
  final String Function(Package) periodLabel;
  final ValueChanged<Package> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('选择方案', 'Choose a Plan'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _kTextStrong,
          ),
        ),
        const SizedBox(height: 14),
        if (loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: CircularProgressIndicator(
                color: _kPrimaryDark,
                strokeWidth: 3,
              ),
            ),
          )
        else if (error != null)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F0),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFCDD2)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFB00020),
                  size: 26,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    t(
                      '无法加载价格，请稍后重试。',
                      'Could not load prices. Please try again.',
                    ),
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFFB00020),
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          )
        else if (packages.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              t('暂未配置订阅商品。', 'No subscription packages available yet.'),
              style: const TextStyle(
                fontSize: 15,
                color: _kTextMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          )
        else
          ...packages.map(
            (pkg) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PackageCard(
                t: t,
                package: pkg,
                selected: selectedPackage == pkg,
                isBestValue: isBestValue(pkg),
                periodLabel: periodLabel(pkg),
                onTap: () => onSelect(pkg),
              ),
            ),
          ),
      ],
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.t,
    required this.package,
    required this.selected,
    required this.isBestValue,
    required this.periodLabel,
    required this.onTap,
  });

  final String Function(String zh, String en) t;
  final Package package;
  final bool selected;
  final bool isBestValue;
  final String periodLabel;
  final VoidCallback onTap;

  String? _perMonthHint() {
    if (package.packageType != PackageType.annual) return null;
    final perMonth = package.storeProduct.price / 12;
    return '≈ ${package.storeProduct.currencyCode} ${perMonth.toStringAsFixed(2)} / ${t("月", "mo")}';
  }

  @override
  Widget build(BuildContext context) {
    final hint = _perMonthHint();
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF0FBF5) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? _kPrimaryDark : _kStroke,
            width: selected ? 2.0 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? _kPrimary.withOpacity(0.18)
                  : const Color(0x0A000000),
              blurRadius: selected ? 14 : 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? _kPrimaryDark : Colors.transparent,
                border: Border.all(
                  color: selected ? _kPrimaryDark : const Color(0xFFBBD5CA),
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    periodLabel,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: selected ? _kCheckGreen : _kTextStrong,
                    ),
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      hint,
                      style: const TextStyle(
                        fontSize: 13,
                        color: _kTextMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (isBestValue) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _kGoldBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _kGoldBorder, width: 1),
                    ),
                    child: Text(
                      t('最佳性价比', 'Best Value'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _kGold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                ],
                Text(
                  package.storeProduct.priceString,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: selected ? _kCheckGreen : _kTextStrong,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── bottom CTA section ─────────────────────────────────────────────────────────
class _BottomCTASection extends StatelessWidget {
  const _BottomCTASection({
    required this.t,
    required this.bottomPad,
    required this.canPurchase,
    required this.loading,
    required this.selectedPackage,
    required this.periodLabel,
    required this.onPurchase,
    required this.onRestore,
  });

  final String Function(String zh, String en) t;
  final double bottomPad;
  final bool canPurchase;
  final bool loading;
  final Package? selectedPackage;
  final String Function(Package) periodLabel;
  final VoidCallback onPurchase;
  final VoidCallback onRestore;

  String _buttonLabel() {
    if (loading) return t('加载中…', 'Loading…');
    if (selectedPackage == null) return t('请选择订阅方案', 'Select a plan to continue');
    final period = periodLabel(selectedPackage!);
    final price  = selectedPackage!.storeProduct.priceString;
    return '${t("订阅", "Subscribe")} $period · $price';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 18 + bottomPad),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 58,
            child: GestureDetector(
              onTap: canPurchase ? onPurchase : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  gradient: canPurchase
                      ? const LinearGradient(
                          colors: [_kPrimary, _kPrimaryDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: canPurchase ? null : _kStroke,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: canPurchase
                      ? [
                          BoxShadow(
                            color: _kPrimaryDark.withOpacity(0.38),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    _buttonLabel(),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: canPurchase ? Colors.white : _kTextMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onRestore,
            style: TextButton.styleFrom(
              foregroundColor: _kTextMuted,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              t('恢复购买', 'Restore Purchases'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t(
              '价格以应用商店展示为准。购买即表示同意商店条款；可在系统订阅管理中管理或取消续订。',
              'Prices shown by the store. Subject to store terms. Manage or cancel via system settings.',
            ),
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: _kTextMuted,
              fontWeight: FontWeight.w400,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── purchase loading overlay ───────────────────────────────────────────────────
class _PurchaseLoadingOverlay extends StatelessWidget {
  const _PurchaseLoadingOverlay({required this.t});

  final String Function(String zh, String en) t;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45),
          ),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 32,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 52,
                    height: 52,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      color: _kPrimaryDark,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    t('正在处理支付…', 'Processing payment…'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: _kTextStrong,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t('请稍候，勿关闭本页', 'Please wait, do not leave this page'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
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
