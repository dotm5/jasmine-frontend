import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:jasmine/basic/commons.dart';
import 'package:jasmine/basic/log.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/configs/login.dart';
import 'local_build.dart';

enum DailySignStatus {
  unavailable,
  unchecked,
  checking,
  signed,
  error,
}

DailySignStatus dailySignStatus = DailySignStatus.unchecked;

final dailySignEvent = Event();

void _setDailySignStatus(DailySignStatus status) {
  dailySignStatus = status;
  dailySignEvent.broadcast();
}

String dailySignStatusLabel() {
  switch (dailySignStatus) {
    case DailySignStatus.unavailable:
      return "签到待接入";
    case DailySignStatus.checking:
      return "检测中...";
    case DailySignStatus.signed:
      return "已打卡";
    case DailySignStatus.error:
      return "打卡失败";
    case DailySignStatus.unchecked:
    default:
      return "未检测打卡";
  }
}

Future<void> checkDailySignStatus(BuildContext context,
    {bool toast = false}) async {
  if (!dailyEndpointAvailable) {
    _setDailySignStatus(DailySignStatus.unavailable);
    if (toast) defaultToast(context, "所选上游尚无每日签到的协议实现");
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
      defaultToast(context, msg.isNotEmpty ? msg : "已打卡");
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
