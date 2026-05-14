// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '岁月安 Zellia';

  @override
  String get appBrand => '岁月安';

  @override
  String get loading => '加载中...';

  @override
  String get loginTitle => '登录';

  @override
  String get usernameLabel => '用户名';

  @override
  String get passwordLabel => '密码';

  @override
  String get loginButton => '登录';

  @override
  String loginFailed(int code) {
    return '登录失败 ($code)';
  }

  @override
  String get invalidResponse => '响应无效';

  @override
  String get todayTitle => '今日';

  @override
  String get logoutTooltip => '退出';

  @override
  String get medicationSectionTitle => '用药';

  @override
  String get medicationPlaceholder => '此处接入 GET /medications/today 与打卡、左滑停药。';

  @override
  String get medicationToggleFailed => '打卡状态更新失败';

  @override
  String get stopMedicationTitle => '停药确认';

  @override
  String stopMedicationConfirm(String name) {
    return '确认停用 $name？停药后会从今日列表移除。';
  }

  @override
  String get stopMedicationAction => '确认停药';

  @override
  String get stopMedicationFailed => '停药失败';

  @override
  String get noMedicationToday => '今天暂无用药待办';

  @override
  String get addMedicationTitle => '新增用药计划';

  @override
  String get medicationNameLabel => '药名';

  @override
  String get medicationDosageLabel => '剂量';

  @override
  String get startDateLabel => '开始日期';

  @override
  String get endDateLabel => '结束日期';

  @override
  String get addTimeButton => '添加时间';

  @override
  String get medicationFormInvalid => '请填写药名、剂量，并至少添加一个时间。';

  @override
  String get vitalsSectionTitle => '体征';

  @override
  String get bloodPressureTitle => '血压';

  @override
  String get bloodSugarTitle => '血糖';

  @override
  String get recordBloodPressure => '记录血压';

  @override
  String get recordBloodSugar => '记录血糖';

  @override
  String get bpRecordTitle => '血压录入';

  @override
  String get bpHistoryTitle => '血压历史记录';

  @override
  String get bpSystolicLabel => '收缩压 (mmHg)';

  @override
  String get bpDiastolicLabel => '舒张压 (mmHg)';

  @override
  String get bpHeartRateLabel => '心率 (bpm，可选)';

  @override
  String get bpHeartRateSkipOption => '不填';

  @override
  String get bsRecordTitle => '血糖录入';

  @override
  String get bsHistoryTitle => '血糖历史记录';

  @override
  String get bsLevelLabel => '血糖值 (mmol/L)';

  @override
  String get bsConditionFasting => '空腹';

  @override
  String get bsConditionPostMeal1h => '餐后1h';

  @override
  String get bsConditionPostMeal2h => '餐后2h';

  @override
  String get bsConditionBedtime => '睡前';

  @override
  String get measureDateLabel => '测量日期';

  @override
  String get saveLabel => '保存';

  @override
  String get savingLabel => '保存中...';

  @override
  String get cancelLabel => '取消';

  @override
  String get vitalsInvalidNumber => '请输入有效数字';

  @override
  String get lastRecordLabel => '上次记录';

  @override
  String get noRecordsYet => '暂无记录';

  @override
  String get noRecordsToday => '今日暂无记录';

  @override
  String get vitalsLoadError => '生命体征加载失败';

  @override
  String get deleteLabel => '删除';

  @override
  String get deleteFailedMessage => '删除失败，请稍后重试';

  @override
  String get familyTitle => '亲情账号关联';

  @override
  String get familyRoleFamily => '让家人守护我';

  @override
  String get familyRoleCaregiver => '我要守护家人';

  @override
  String familyMyInviteCode(String code) {
    return '我的邀请码: $code';
  }

  @override
  String get familyCopyInviteCode => '复制邀请码';

  @override
  String get familyPendingRequests => '待审核申请';

  @override
  String get familyNoPendingRequests => '暂无待审核申请';

  @override
  String familyCaregiverAccount(String username) {
    return '守护人：$username';
  }

  @override
  String get familyReject => '拒绝';

  @override
  String get familyApprove => '同意';

  @override
  String get familyInviteCodeInputLabel => '输入家人的邀请码';

  @override
  String get familyApplyLink => '申请绑定';

  @override
  String get familyApprovedFamily => '我关注的家人';

  @override
  String get familyNoApprovedElders => '暂无已关联长辈';

  @override
  String familyViewElderData(String username) {
    return '查看 $username 的数据';
  }

  @override
  String get familySwitchBackToMine => '切回查看我的数据';

  @override
  String get familyApplySubmitted => '申请已提交，等待家人审核';

  @override
  String familySubmitFailed(String error) {
    return '提交失败: $error';
  }

  @override
  String familyDecisionFailed(String error) {
    return '处理失败: $error';
  }

  @override
  String familySwitchedToFamilyData(String username) {
    return '已切换为查看 $username 的健康数据';
  }

  @override
  String get familySwitchedBackToMine => '已切换回查看自己的数据';

  @override
  String get familyInviteCodeCopied => '邀请码已复制';

  @override
  String get defaultElderName => '长辈';

  @override
  String viewingElderHealthData(String username) {
    return '正在查看: $username 的健康数据';
  }

  @override
  String medicationCheckedAt(String time) {
    return '已打卡 $time';
  }

  @override
  String get readOnlyModeHint => '当前为长辈数据只读模式，不能新增/打卡/删除';
}
