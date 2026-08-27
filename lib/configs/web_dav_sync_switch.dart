import 'package:flutter/material.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';
import 'local_build.dart';

const _propertyName = "webDavSyncSwitch";
late bool _webDavSyncSwitch;

Future<void> initWebDavSyncSwitch() async {
  _webDavSyncSwitch = (await methods.loadProperty(_propertyName)) == "true";
}

bool currentWebDavSyncSwitch() {
  return _webDavSyncSwitch;
}

Future<void> _chooseWebDavSyncSwitch(BuildContext context) async {
  String? result = await chooseListDialog<String>(context,
      title: "开开启时自动同步历史记录到WebDAV", values: ["是", "否"]);
  if (result != null) {
    var target = result == "是";
    await methods.saveProperty(_propertyName, "$target");
    _webDavSyncSwitch = target;
  }
}

Widget webDavSyncSwitchSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        title: Text(
          "开启时自动同步历史记录到WebDAV",
          style: TextStyle(
            color: !localFeaturesEnabled ? Colors.grey : null,
          ),
        ),
        subtitle: Text(
          _webDavSyncSwitch ? "是" : "否",
          style: TextStyle(
            color: !localFeaturesEnabled ? Colors.grey : null,
          ),
        ),
        onTap: () async {
          if (!localFeaturesEnabled) {
            return;
          }
          await _chooseWebDavSyncSwitch(context);
          setState(() {});
        },
      );
    },
  );
}
