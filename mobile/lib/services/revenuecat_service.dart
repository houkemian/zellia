import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Asset JSON: [assets/config/revenuecat.json] — keys `google_public_api_key` / `apple_public_api_key`.
/// See [assets/config/revenuecat.example.json] for shape. File values take priority over dart-define.
const String _kRevenueCatConfigAsset = 'assets/config/revenuecat.json';

const String kRevenueCatGoogleApiKey = String.fromEnvironment(
  'REVENUECAT_GOOGLE_API_KEY',
  defaultValue: '',
);

const String kRevenueCatAppleApiKey = String.fromEnvironment(
  'REVENUECAT_APPLE_API_KEY',
  defaultValue: '',
);

/// Entitlement identifier configured in RevenueCat (must match dashboard).
const String kProEntitlementId = 'pro';

/// RevenueCat / Google Play subscriptions for Zellia PRO.
class RevenueCatService {
  RevenueCatService._();

  static final RevenueCatService instance = RevenueCatService._();

  bool _configured = false;
  static String? _googleKeyFromAsset;
  static String? _appleKeyFromAsset;
  static bool _assetKeysAttempted = false;

  bool get isConfigured => _configured;

  static Future<void> _loadKeysFromAssetOnce() async {
    if (_assetKeysAttempted) return;
    _assetKeysAttempted = true;
    try {
      final raw = await rootBundle.loadString(_kRevenueCatConfigAsset);
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final g = map['google_public_api_key'];
      final a = map['apple_public_api_key'];
      if (g is String && g.trim().isNotEmpty) {
        _googleKeyFromAsset = g.trim();
      }
      if (a is String && a.trim().isNotEmpty) {
        _appleKeyFromAsset = a.trim();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RevenueCat] Could not load $_kRevenueCatConfigAsset: $e');
      }
    }
  }

  static String _resolveGoogleApiKey() {
    final fromFile = (_googleKeyFromAsset ?? '').trim();
    if (fromFile.isNotEmpty) return fromFile;
    return kRevenueCatGoogleApiKey.trim();
  }

  static String _resolveAppleApiKey() {
    final fromFile = (_appleKeyFromAsset ?? '').trim();
    if (fromFile.isNotEmpty) return fromFile;
    return kRevenueCatAppleApiKey.trim();
  }

  Future<void> init() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      if (kDebugMode) {
        debugPrint('[RevenueCat] Skipping configure: unsupported platform');
      }
      return;
    }
    await _loadKeysFromAssetOnce();
    final apiKey = Platform.isAndroid
        ? _resolveGoogleApiKey()
        : _resolveAppleApiKey();
    if (apiKey.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[RevenueCat] Skipping configure: empty API key for this platform',
        );
      }
      return;
    }
    if (_configured) return;

    if (kDebugMode) {
      await Purchases.setLogLevel(LogLevel.debug);
    }

    final configuration = PurchasesConfiguration(apiKey);
    await Purchases.configure(configuration);
    _configured = true;
  }

  /// [userId] must match backend `users.id` (same string RevenueCat sends as `app_user_id`).
  Future<void> login(String userId) async {
    if (!_configured) await init();
    if (!_configured) {
      throw StateError('RevenueCat is not configured (missing API key).');
    }
    final trimmed = userId.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('userId must not be empty');
    }
    await Purchases.logIn(trimmed);
  }

  Future<CustomerInfo> logout() async {
    if (!_configured) {
      return await Purchases.getCustomerInfo();
    }
    return Purchases.logOut();
  }

  Future<Offerings?> getOfferings() async {
    if (!_configured) await init();
    if (!_configured) return null;
    return Purchases.getOfferings();
  }

  Future<CustomerInfo> purchasePackage(Package package) async {
    if (!_configured) await init();
    if (!_configured) {
      throw StateError('RevenueCat is not configured (missing API key).');
    }
    final result = await Purchases.purchasePackage(package);
    return result.customerInfo;
  }

  /// Active `pro` entitlement from cached customer info.
  Future<bool> checkPremiumStatus() async {
    if (!_configured) await init();
    if (!_configured) return false;
    final info = await Purchases.getCustomerInfo();
    return _hasProEntitlement(info);
  }

  bool _hasProEntitlement(CustomerInfo info) {
    final ent = info.entitlements.all[kProEntitlementId];
    return ent?.isActive == true;
  }

  /// Maps [PlatformException] from Purchases to a user-facing message key / flag.
  static PurchaseFlowError? mapPurchaseError(Object error) {
    if (error is PlatformException) {
      final code = PurchasesErrorHelper.getErrorCode(error);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return PurchaseFlowError.cancelled;
      }
      if (code == PurchasesErrorCode.networkError) {
        return PurchaseFlowError.network;
      }
      if (code == PurchasesErrorCode.storeProblemError) {
        return PurchaseFlowError.store;
      }
      return PurchaseFlowError.other;
    }
    return PurchaseFlowError.other;
  }
}

enum PurchaseFlowError { cancelled, network, store, other }
