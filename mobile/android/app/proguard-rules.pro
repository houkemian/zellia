# RevenueCat can optionally read Google Advertising ID when the ads identifier library is present.
# We intentionally exclude that library so Google Play does not detect Advertising ID usage.
-dontwarn com.google.android.gms.ads.identifier.AdvertisingIdClient
-dontwarn com.google.android.gms.ads.identifier.AdvertisingIdClient$Info
