import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:jasmine/basic/commons.dart';
import 'package:jasmine/basic/log.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/configs/login.dart';
import 'local_build.dart';

enum DailySignStatus { unavailable, unchecked, checking, signed, error }

DailySignStatus dailySignStatus = DailySignStatus.unchecked;

final dailySignEvent = Event();

void _setDailySignStatus(DailySignStatus status) {
  dailySignStatus = status;
  dailySignEvent.broadcast();
}

String dailySignStatusLabel() {
  switch (dailySignStatus) {
    case DailySignStatus.unavailable:
      return "当前线路暂不支持签到";
    case DailySignStatus.checking:
      return "签到中…";
    case DailySignStatus.signed:
      return "已签到";
    case DailySignStatus.error:
      return "签到失败，点击重试";
    case DailySignStatus.unchecked:
    default:
      return "每日签到";
  }
}

Future<void> checkDailySignStatus(
  BuildContext context, {
  bool toast = false,
}) async {
  if (!dailyEndpointAvailable) {
    _setDailySignStatus(DailySignStatus.unavailable);
    if (toast) defaultToast(context, "当前线路暂不支持签到，请尝试切换内容线路");
    return;
  }
  if (loginStatus != LoginStatus.loginSuccess) {
    _setDailySignStatus(DailySignStatus.unchecked);
    return;
  }
  _setDailySignStatus(DailySignStatus.checking);
  try {
    final msg = await methods.daily(selfInfo.uid);
    if (toast) {
      defaultToast(context, msg.isNotEmpty ? msg : "已签到");
    }
    _setDailySignStatus(DailySignStatus.signed);
  } catch (e, st) {
    debugPrient("$e\n$st");
    if (toast) {
      defaultToast(context, "$e");
    }
    _setDailySignStatus(DailySignStatus.error);
  }
}
