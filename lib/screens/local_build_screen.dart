import 'package:flutter/material.dart';

class LocalBuildScreen extends StatelessWidget {
  const LocalBuildScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('本地构建')),
      body: const ListViewBody(),
    );
  }
}

class ListViewBody extends StatelessWidget {
  const ListViewBody({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: const [
      Text('Jasmine + Jenny', style: TextStyle(fontSize: 24)),
      SizedBox(height: 16),
      Text(
        '界面保留 Jasmine，原生后端来自 Jenny；网络协议、图片分块和 PDF 实现参考固定版本的 jmcomic-downloader。',
      ),
      SizedBox(height: 12),
      Text('本地分页、下载、导出和同步功能独立于原作者的会员服务。本构建不显示或兑换会员资格。'),
      SizedBox(height: 12),
      Text('每日签到、收藏夹重命名已按 Release 协议接入并进行离线测试；线上账号和设备功能仍需实际验证。'),
      SizedBox(height: 12),
      Text('源码来源、版本和许可说明见项目 native/sources.lock.json 与 native/README.md。'),
    ],
  );
}
