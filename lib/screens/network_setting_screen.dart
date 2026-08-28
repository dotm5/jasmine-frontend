import 'package:flutter/material.dart';
import 'package:jasmine/configs/network_api_host.dart';
import 'package:jasmine/configs/network_cdn_host.dart';
import 'package:jasmine/configs/proxy.dart';
import 'package:jasmine/screens/init_screen.dart';

import 'components/right_click_pop.dart';
import 'downloads_screen.dart';

class NetworkSettingScreen extends StatelessWidget {
  const NetworkSettingScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("网络设置"),
        actions: [
          IconButton(
            tooltip: '下载管理',
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (BuildContext context) {
                    return const DownloadsScreen();
                  },
                ),
              );
            },
            icon: const Icon(Icons.download),
          ),
          IconButton(
            tooltip: '应用设置并重新连接',
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (BuildContext context) {
                    return const InitScreen();
                  },
                ),
              );
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('内容线路用于列表、搜索和详情；图片线路用于封面和正文。选择后自动保存，点击右上角重新连接。'),
            ),
          ),
          apiHostSetting(),
          cdnHostSetting(),
          proxySetting(),
        ],
      ),
    );
  }
}
