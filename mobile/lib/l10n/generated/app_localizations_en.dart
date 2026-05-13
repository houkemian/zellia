// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Zellia';

  @override
  String get appBrand => 'Zellia';

  @override
  String get loading => 'Loading...';

  @override
  String get loginTitle => 'Sign In';

  @override
  String get usernameLabel => 'Username';

  @override
  String get passwordLabel => 'Password';

  @override
  String get loginButton => 'Sign In';

  @override
  String loginFailed(int code) {
    return 'Sign in failed ($code)';
  }

  @override
  String get invalidResponse => 'Invalid response';

  @override
  String get todayTitle => 'Today';

  @override
  String get logoutTooltip => 'Sign out';

  @override
  String get medicationSectionTitle => 'Medication';

  @override
  String get medicationPlaceholder =>
      'This section will connect GET /medications/today, check-ins, and swipe-to-stop.';

  @override
  String get medicationToggleFailed => 'Failed to update check-in status';

  @override
  String get stopMedicationTitle => 'Stop medication';

  @override
  String stopMedicationConfirm(String name) {
    return 'Stop $name? It will be removed from today\'s list.';
  }

  @override
  String get stopMedicationAction => 'Stop';

  @override
  String get stopMedicationFailed => 'Failed to stop medication';

  @override
  String get noMedicationToday => 'No medication tasks for today';

  @override
  String get addMedicationTitle => 'Add Medication';

  @override
  String get medicationNameLabel => 'Medication name';

  @override
  String get medicationDosageLabel => 'Dosage';

  @override
  String get startDateLabel => 'Start date';

  @override
  String get endDateLabel => 'End date';

  @override
  String get addTimeButton => 'Add Time';

  @override
  String get medicationFormInvalid =>
      'Please fill name, dosage and at least one time.';

  @override
  String get vitalsSectionTitle => 'Vitals';

  @override
  String get bloodPressureTitle => 'Blood Pressure';

  @override
  String get bloodSugarTitle => 'Blood Sugar';

  @override
  String get recordBloodPressure => 'Record Blood Pressure';

  @override
  String get recordBloodSugar => 'Record Blood Sugar';

  @override
  String get bpRecordTitle => 'Blood Pressure Entry';

  @override
  String get bpHistoryTitle => 'Blood Pressure History';

  @override
  String get bpSystolicLabel => 'Systolic (mmHg)';

  @override
  String get bpDiastolicLabel => 'Diastolic (mmHg)';

  @override
  String get bpHeartRateLabel => 'Heart Rate (bpm, optional)';

  @override
  String get bpHeartRateSkipOption => 'Skip';

  @override
  String get bsRecordTitle => 'Blood Sugar Entry';

  @override
  String get bsHistoryTitle => 'Blood Sugar History';

  @override
  String get bsLevelLabel => 'Blood Sugar (mmol/L)';

  @override
  String get bsConditionFasting => 'Fasting';

  @override
  String get bsConditionPostMeal1h => 'Post-meal 1h';

  @override
  String get bsConditionPostMeal2h => 'Post-meal 2h';

  @override
  String get bsConditionBedtime => 'Before bed';

  @override
  String get measureDateLabel => 'Date';

  @override
  String get saveLabel => 'Save';

  @override
  String get savingLabel => 'Saving...';

  @override
  String get cancelLabel => 'Cancel';

  @override
  String get vitalsInvalidNumber => 'Please enter valid numbers.';

  @override
  String get lastRecordLabel => 'Last record';

  @override
  String get noRecordsYet => 'No records yet';

  @override
  String get noRecordsToday => 'No records for today';

  @override
  String get vitalsLoadError => 'Failed to load vitals history';

  @override
  String get deleteLabel => 'Delete';

  @override
  String get deleteFailedMessage => 'Delete failed. Please try again later.';

  @override
  String get familyTitle => 'Family Account Linking';

  @override
  String get familyRoleElder => 'Let my family care for me';

  @override
  String get familyRoleCaregiver => 'I want to care for my family';

  @override
  String familyMyInviteCode(String code) {
    return 'My invite code: $code';
  }

  @override
  String get familyCopyInviteCode => 'Copy invite code';

  @override
  String get familyPendingRequests => 'Pending requests';

  @override
  String get familyNoPendingRequests => 'No pending requests';

  @override
  String familyCaregiverAccount(String username) {
    return 'Guardian: $username';
  }

  @override
  String get familyReject => 'Reject';

  @override
  String get familyApprove => 'Approve';

  @override
  String get familyInviteCodeInputLabel => 'Enter family invite code';

  @override
  String get familyApplyLink => 'Request link';

  @override
  String get familyApprovedElders => 'Family I follow';

  @override
  String get familyNoApprovedElders => 'No linked elders yet';

  @override
  String familyViewElderData(String username) {
    return 'View $username\'s data';
  }

  @override
  String get familySwitchBackToMine => 'Switch back to my data';

  @override
  String get familyApplySubmitted =>
      'Request submitted, waiting for elder approval';

  @override
  String familySubmitFailed(String error) {
    return 'Submit failed: $error';
  }

  @override
  String familyDecisionFailed(String error) {
    return 'Action failed: $error';
  }

  @override
  String familySwitchedToElderData(String username) {
    return 'Switched to viewing $username\'s health data';
  }

  @override
  String get familySwitchedBackToMine => 'Switched back to my own data';

  @override
  String get familyInviteCodeCopied => 'Invite code copied';

  @override
  String get defaultElderName => 'Elder';

  @override
  String viewingElderHealthData(String username) {
    return 'Viewing: $username\'s health data';
  }

  @override
  String medicationCheckedAt(String time) {
    return 'Checked at $time';
  }

  @override
  String get readOnlyModeHint =>
      'Read-only elder view: adding/checking/deleting is disabled';
}
