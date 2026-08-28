import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:jasmine/basic/commons.dart';
import 'package:jasmine/basic/methods.dart';

const _propertyName = "pager_column_number";
late int _pagerColumnNumber;

int get pagerColumnNumber => _pagerColumnNumber;
final pageColumnEvent = Event();

Future initPagerColumnCount() async {
  String numStr = await methods.loadProperty(_propertyName);
  _pagerColumnNumber = (int.tryParse(numStr) ?? 0).clamp(0, 10);
}

Future choosePagerColumnCount(BuildContext context) async {
  final choose = await chooseMapDialog<int>(
    context,
    title: "每行漫画数",
    values: {'自动适应窗口': 0, for (var i = 1; i <= 10; i++) '$i 列': i},
  );
  if (choose != null) {
    await methods.saveProperty(_propertyName, choose.toString());
    _pagerColumnNumber = choose;
    pageColumnEvent.broadcast();
  }
}
