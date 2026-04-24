import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Zellia'**
  String get appTitle;

  /// No description provided for @appBrand.
  ///
  /// In en, this message translates to:
  /// **'Zellia'**
  String get appBrand;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get loginTitle;

  /// No description provided for @usernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usernameLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @loginButton.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get loginButton;

  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign in failed ({code})'**
  String loginFailed(int code);

  /// No description provided for @invalidResponse.
  ///
  /// In en, this message translates to:
  /// **'Invalid response'**
  String get invalidResponse;

  /// No description provided for @todayTitle.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get todayTitle;

  /// No description provided for @logoutTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get logoutTooltip;

  /// No description provided for @medicationSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Medication'**
  String get medicationSectionTitle;

  /// No description provided for @medicationPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'This section will connect GET /medications/today, check-ins, and swipe-to-stop.'**
  String get medicationPlaceholder;

  /// No description provided for @medicationToggleFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update check-in status'**
  String get medicationToggleFailed;

  /// No description provided for @stopMedicationTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop medication'**
  String get stopMedicationTitle;

  /// No description provided for @stopMedicationConfirm.
  ///
  /// In en, this message translates to:
  /// **'Stop {name}? It will be removed from today\'s list.'**
  String stopMedicationConfirm(String name);

  /// No description provided for @stopMedicationAction.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stopMedicationAction;

  /// No description provided for @stopMedicationFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to stop medication'**
  String get stopMedicationFailed;

  /// No description provided for @noMedicationToday.
  ///
  /// In en, this message translates to:
  /// **'No medication tasks for today'**
  String get noMedicationToday;

  /// No description provided for @addMedicationTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Medication'**
  String get addMedicationTitle;

  /// No description provided for @medicationNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Medication name'**
  String get medicationNameLabel;

  /// No description provided for @medicationDosageLabel.
  ///
  /// In en, this message translates to:
  /// **'Dosage'**
  String get medicationDosageLabel;

  /// No description provided for @startDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get startDateLabel;

  /// No description provided for @endDateLabel.
  ///
  /// In en, this message translates to:
  /// **'End date'**
  String get endDateLabel;

  /// No description provided for @addTimeButton.
  ///
  /// In en, this message translates to:
  /// **'Add Time'**
  String get addTimeButton;

  /// No description provided for @medicationFormInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please fill name, dosage and at least one time.'**
  String get medicationFormInvalid;

  /// No description provided for @vitalsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Vitals'**
  String get vitalsSectionTitle;

  /// No description provided for @bloodPressureTitle.
  ///
  /// In en, this message translates to:
  /// **'Blood Pressure'**
  String get bloodPressureTitle;

  /// No description provided for @bloodSugarTitle.
  ///
  /// In en, this message translates to:
  /// **'Blood Sugar'**
  String get bloodSugarTitle;

  /// No description provided for @recordBloodPressure.
  ///
  /// In en, this message translates to:
  /// **'Record Blood Pressure'**
  String get recordBloodPressure;

  /// No description provided for @recordBloodSugar.
  ///
  /// In en, this message translates to:
  /// **'Record Blood Sugar'**
  String get recordBloodSugar;

  /// No description provided for @bpRecordTitle.
  ///
  /// In en, this message translates to:
  /// **'Blood Pressure Entry'**
  String get bpRecordTitle;

  /// No description provided for @bpHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Blood Pressure History'**
  String get bpHistoryTitle;

  /// No description provided for @bpSystolicLabel.
  ///
  /// In en, this message translates to:
  /// **'Systolic (mmHg)'**
  String get bpSystolicLabel;

  /// No description provided for @bpDiastolicLabel.
  ///
  /// In en, this message translates to:
  /// **'Diastolic (mmHg)'**
  String get bpDiastolicLabel;

  /// No description provided for @bpHeartRateLabel.
  ///
  /// In en, this message translates to:
  /// **'Heart Rate (bpm, optional)'**
  String get bpHeartRateLabel;

  /// No description provided for @bpHeartRateSkipOption.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get bpHeartRateSkipOption;

  /// No description provided for @bsRecordTitle.
  ///
  /// In en, this message translates to:
  /// **'Blood Sugar Entry'**
  String get bsRecordTitle;

  /// No description provided for @bsHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Blood Sugar History'**
  String get bsHistoryTitle;

  /// No description provided for @bsLevelLabel.
  ///
  /// In en, this message translates to:
  /// **'Blood Sugar (mmol/L)'**
  String get bsLevelLabel;

  /// No description provided for @bsConditionFasting.
  ///
  /// In en, this message translates to:
  /// **'Fasting'**
  String get bsConditionFasting;

  /// No description provided for @bsConditionPostMeal1h.
  ///
  /// In en, this message translates to:
  /// **'Post-meal 1h'**
  String get bsConditionPostMeal1h;

  /// No description provided for @bsConditionPostMeal2h.
  ///
  /// In en, this message translates to:
  /// **'Post-meal 2h'**
  String get bsConditionPostMeal2h;

  /// No description provided for @bsConditionBedtime.
  ///
  /// In en, this message translates to:
  /// **'Before bed'**
  String get bsConditionBedtime;

  /// No description provided for @measureDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get measureDateLabel;

  /// No description provided for @saveLabel.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveLabel;

  /// No description provided for @savingLabel.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get savingLabel;

  /// No description provided for @cancelLabel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelLabel;

  /// No description provided for @vitalsInvalidNumber.
  ///
  /// In en, this message translates to:
  /// **'Please enter valid numbers.'**
  String get vitalsInvalidNumber;

  /// No description provided for @lastRecordLabel.
  ///
  /// In en, this message translates to:
  /// **'Last record'**
  String get lastRecordLabel;

  /// No description provided for @noRecordsYet.
  ///
  /// In en, this message translates to:
  /// **'No records yet'**
  String get noRecordsYet;

  /// No description provided for @noRecordsToday.
  ///
  /// In en, this message translates to:
  /// **'No records for today'**
  String get noRecordsToday;

  /// No description provided for @vitalsLoadError.
  ///
  /// In en, this message translates to:
  /// **'Failed to load vitals history'**
  String get vitalsLoadError;

  /// No description provided for @deleteLabel.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteLabel;

  /// No description provided for @deleteFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete failed. Please try again later.'**
  String get deleteFailedMessage;

  /// No description provided for @familyTitle.
  ///
  /// In en, this message translates to:
  /// **'Family Account Linking'**
  String get familyTitle;

  /// No description provided for @familyRoleElder.
  ///
  /// In en, this message translates to:
  /// **'Let my family care for me'**
  String get familyRoleElder;

  /// No description provided for @familyRoleCaregiver.
  ///
  /// In en, this message translates to:
  /// **'I want to care for my family'**
  String get familyRoleCaregiver;

  /// No description provided for @familyMyInviteCode.
  ///
  /// In en, this message translates to:
  /// **'My invite code: {code}'**
  String familyMyInviteCode(String code);

  /// No description provided for @familyCopyInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Copy invite code'**
  String get familyCopyInviteCode;

  /// No description provided for @familyPendingRequests.
  ///
  /// In en, this message translates to:
  /// **'Pending requests'**
  String get familyPendingRequests;

  /// No description provided for @familyNoPendingRequests.
  ///
  /// In en, this message translates to:
  /// **'No pending requests'**
  String get familyNoPendingRequests;

  /// No description provided for @familyCaregiverAccount.
  ///
  /// In en, this message translates to:
  /// **'Caregiver account: {username}'**
  String familyCaregiverAccount(String username);

  /// No description provided for @familyReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get familyReject;

  /// No description provided for @familyApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get familyApprove;

  /// No description provided for @familyInviteCodeInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Enter family invite code'**
  String get familyInviteCodeInputLabel;

  /// No description provided for @familyApplyLink.
  ///
  /// In en, this message translates to:
  /// **'Request link'**
  String get familyApplyLink;

  /// No description provided for @familyApprovedElders.
  ///
  /// In en, this message translates to:
  /// **'Family I follow'**
  String get familyApprovedElders;

  /// No description provided for @familyNoApprovedElders.
  ///
  /// In en, this message translates to:
  /// **'No linked elders yet'**
  String get familyNoApprovedElders;

  /// No description provided for @familyViewElderData.
  ///
  /// In en, this message translates to:
  /// **'View {username}\'s data'**
  String familyViewElderData(String username);

  /// No description provided for @familySwitchBackToMine.
  ///
  /// In en, this message translates to:
  /// **'Switch back to my data'**
  String get familySwitchBackToMine;

  /// No description provided for @familyApplySubmitted.
  ///
  /// In en, this message translates to:
  /// **'Request submitted, waiting for elder approval'**
  String get familyApplySubmitted;

  /// No description provided for @familySubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Submit failed: {error}'**
  String familySubmitFailed(String error);

  /// No description provided for @familyDecisionFailed.
  ///
  /// In en, this message translates to:
  /// **'Action failed: {error}'**
  String familyDecisionFailed(String error);

  /// No description provided for @familySwitchedToElderData.
  ///
  /// In en, this message translates to:
  /// **'Switched to viewing {username}\'s health data'**
  String familySwitchedToElderData(String username);

  /// No description provided for @familySwitchedBackToMine.
  ///
  /// In en, this message translates to:
  /// **'Switched back to my own data'**
  String get familySwitchedBackToMine;

  /// No description provided for @familyInviteCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Invite code copied'**
  String get familyInviteCodeCopied;

  /// No description provided for @defaultElderName.
  ///
  /// In en, this message translates to:
  /// **'Elder'**
  String get defaultElderName;

  /// No description provided for @viewingElderHealthData.
  ///
  /// In en, this message translates to:
  /// **'Viewing: {username}\'s health data'**
  String viewingElderHealthData(String username);

  /// No description provided for @medicationCheckedAt.
  ///
  /// In en, this message translates to:
  /// **'Checked at {time}'**
  String medicationCheckedAt(String time);

  /// No description provided for @readOnlyModeHint.
  ///
  /// In en, this message translates to:
  /// **'Read-only elder view: adding/checking/deleting is disabled'**
  String get readOnlyModeHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
