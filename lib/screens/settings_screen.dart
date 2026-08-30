import 'package:jasmine/screens/components/expressive_page_transitions.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/configs/app_font_size.dart';
import 'package:jasmine/configs/app_orientation.dart';
import 'package:jasmine/configs/drag_region_lock.dart';
import 'package:jasmine/configs/gesture_speed.dart';
import 'package:jasmine/configs/network_api_host.dart';
import 'package:jasmine/configs/network_cdn_host.dart';
import 'package:jasmine/configs/reader_zoom_scale.dart';
import 'package:jasmine/screens/downloads_exports_screen2.dart';

import '../basic/commons.dart';
import '../basic/web_dav_sync.dart';
import '../configs/Authentication.dart';
import '../configs/android_display_mode.dart';
import '../configs/always_enter_browser.dart';
import '../configs/categories_sort.dart';
import '../configs/comic_seal.dart';
import '../configs/display_jmcode.dart';
import '../configs/download_and_export_to.dart';
import '../configs/esc_to_pop.dart';
import '../configs/disable_recommend_content.dart';
import '../configs/export_rename.dart';
import '../configs/ignore_upgrade_pop.dart';
import '../configs/ignore_view_log.dart';
import '../configs/local_build.dart';
import '../configs/login.dart';
import '../configs/no_animation.dart';
import '../configs/proxy.dart';
import '../configs/search_title_words.dart';
import '../configs/surface_appearance.dart';
import '../configs/theme.dart';
import '../configs/two_page_direction.dart';
import '../configs/using_right_click_pop.dart';
import '../configs/versions.dart';
import '../configs/volume_key_control.dart';
import '../configs/web_dav_password.dart';
import '../configs/web_dav_sync_switch.dart';
import '../configs/web_dav_url.dart';
import '../configs/web_dav_username.dart';
import '../configs/passed.dart' as passed_config;
import 'components/right_click_pop.dart';
import 'components/responsive_settings_body.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _SettingsState();
  }
}

class _SettingsState extends State<SettingsScreen> {
  bool _startupImageExists = false;

  @override
  void initState() {
    super.initState();
    _loadStartupImageState();
  }

  Future<void> _loadStartupImageState() async {
    try {
      final startupImagePath = await methods.getStartupImagePath();
      if (!mounted) {
        return;
      }
      setState(() {
        _startupImageExists = startupImagePath.isNotEmpty;
      });
    } catch (_) {}
  }

  Future<String> _renderPngBase64WithinScreen(
    Uint8List imageBytes,
    Size screenSize,
  ) async {
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frameInfo = await codec.getNextFrame();
    final srcImage = frameInfo.image;
    final srcWidth = srcImage.width.toDouble();
    final srcHeight = srcImage.height.toDouble();

    final scale = math.min(
      math.min(screenSize.width / srcWidth, screenSize.height / srcHeight),
      1.0,
    );
    final targetWidth = math.max(1, (srcWidth * scale).round());
    final targetHeight = math.max(1, (srcHeight * scale).round());

    final resizedCodec = await ui.instantiateImageCodec(
      imageBytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final resizedFrame = await resizedCodec.getNextFrame();
    final pngData = await resizedFrame.image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (pngData == null) {
      throw StateError("图片编码失败");
    }
    return base64Encode(pngData.buffer.asUint8List());
  }

  Future<void> _pickAndSaveStartupImage(BuildContext context) async {
    try {
      Uint8List? imageBytes;
      if (Platform.isAndroid || Platform.isIOS) {
        final picker = ImagePicker();
        final picked = await picker.pickImage(source: ImageSource.gallery);
        if (picked == null) {
          return;
        }
        imageBytes = await picked.readAsBytes();
      } else {
        final picked = await FilePicker.platform.pickFiles(
          dialogTitle: "选择启动图",
          type: FileType.custom,
          allowedExtensions: ["png", "jpg", "jpeg", "bmp", "webp"],
        );
        if (picked == null || picked.files.isEmpty) {
          return;
        }
        final file = picked.files.first;
        if (file.bytes != null) {
          imageBytes = file.bytes!;
        } else if (file.path != null) {
          imageBytes = await File(file.path!).readAsBytes();
        }
      }

      if (imageBytes == null) {
        defaultToast(context, "未读取到图片");
        return;
      }

      final size = MediaQuery.of(context).size;
      final base64Data = await _renderPngBase64WithinScreen(imageBytes, size);
      await methods.saveStartupImage(base64Data);
      defaultToast(context, _startupImageExists ? "替换启动图成功" : "设置启动图成功");
      await _loadStartupImageState();
    } catch (e) {
      defaultToast(context, "设置启动图失败 : $e");
      print("设置启动图失败 : $e");
    }
  }

  Future<void> _deleteStartupImage(BuildContext context) async {
    if (!await confirmDialog(context, "删除启动图", "确定删除当前启动图吗?")) {
      return;
    }
    try {
      await methods.deleteStartupImage();
      defaultToast(context, "删除启动图成功");
      await _loadStartupImageState();
    } catch (e) {
      defaultToast(context, "删除启动图失败 : $e");
    }
  }

  Future<void> _resetBrowser(BuildContext context) async {
    if (!await confirmDialog(context, "重置浏览器", "确定删除浏览器启动标记吗? 下次启动将重新进入浏览器。")) {
      return;
    }
    try {
      await passed_config.clearPassed();
      defaultToast(context, "重置浏览器成功");
    } catch (e) {
      defaultToast(context, "重置浏览器失败 : $e");
    }
  }

  Widget _startupImageSettingTile(BuildContext context) {
    return ListTile(
      onTap: () async {
        await _pickAndSaveStartupImage(context);
      },
      title: Text(_startupImageExists ? "替换启动图" : "设置启动图"),
    );
  }

  Widget _deleteStartupImageTile(BuildContext context) {
    return ListTile(
      onTap: () async {
        await _deleteStartupImage(context);
      },
      title: const Text("删除启动图"),
    );
  }

  Widget _resetBrowserTile(BuildContext context) {
    return ListTile(
      onTap: () async {
        await _resetBrowser(context);
      },
      title: const Text("重置浏览器"),
    );
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget _section(
    String title,
    String subtitle,
    IconData icon,
    List<Widget> children,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey(title),
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: children,
      ),
    );
  }

  Widget buildScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        child: ResponsiveSettingsBody(
          children: [
            _section('网络连接', '内容线路、图片线路与代理', Icons.wifi_outlined, [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text('内容线路用于列表、搜索和详情；图片线路用于封面和正文。'),
              ),
              apiHostSetting(),
              cdnHostSetting(),
              proxySetting(),
            ]),
            _section('账号与收藏', '收藏夹管理、退出登录', Icons.manage_accounts_outlined, [
              createFavoriteFolderItemTile(context),
              renameFavoriteFolderItemTile(context),
              deleteFavoriteFolderItemTile(context),
              const Divider(),
              ListTile(
                title: const Text('退出登录'),
                subtitle: const Text('清除保存的账号信息并关闭应用'),
                onTap: () async {
                  if (await confirmDialog(
                    context,
                    '退出登录',
                    '将清除保存的账号信息并关闭应用，确定继续吗？',
                  )) {
                    await methods.logout();
                    exit(0);
                  }
                },
              ),
            ]),
            _section('阅读体验', '翻页、手势与图片缩放', Icons.menu_book_outlined, [
              volumeKeyControlSetting(),
              noAnimationSetting(),
              gestureSpeedSetting(),
              dragRegionLockSetting(),
              readerZoomMinScaleSetting(),
              readerZoomMaxScaleSetting(),
              readerZoomDoubleTapScaleSetting(),
              twoGalleryDirectionSetting(context),
            ]),
            _section('外观与显示', '色彩主题、界面材质、字号与屏幕方向', Icons.palette_outlined, [
              themeSetting(context),
              surfaceStyleSetting(context),
              glassTransmissionSetting(),
              ...fontSizeAdjustSettings(),
              appOrientationWidget(),
              androidDisplayModeSetting(),
              categoriesSortSetting(context),
              displayJmcodeSetting(),
            ]),
            _section('下载与导出', '保存位置、文件命名与导出', Icons.download_outlined, [
              exportRenameSetting(),
              downloadAndExportToSetting(),
              ListTile(
                onTap:
                    () => Navigator.of(context).push(
                      AppPageRoute(
                        builder: (c) => const DownloadsExportScreen2(),
                      ),
                    ),
                title: const Text('导出已下载内容'),
                subtitle: const Text('支持导出尚未全部下载完成的漫画'),
                trailing: const Icon(Icons.chevron_right),
              ),
            ]),
            _section('数据同步', '通过 WebDAV 备份与同步', Icons.sync_outlined, [
              webDavSyncSwitchSetting(),
              webDavUrlSetting(),
              webDavUserNameSetting(),
              webDavPasswordSetting(),
              webDavSyncClick(context),
              webDavSyncUploadClick(context),
              webDavSyncDownloadClick(context),
            ]),
            _section('隐私与内容', '浏览记录、内容过滤与应用锁', Icons.shield_outlined, [
              ignoreVewLogSetting(),
              authenticationSetting(),
              disableRecommendContentSetting(),
              comicSealCategorySetting(),
              comicSealTitleWordsSetting(),
              searchTitleWordsSetting(),
            ]),
            _section('启动与其他', '启动图、更新提醒与快捷操作', Icons.tune_outlined, [
              alwaysEnterBrowserSetting(),
              _resetBrowserTile(context),
              _startupImageSettingTile(context),
              if (_startupImageExists) _deleteStartupImageTile(context),
              if (localFeaturesEnabled) ...[
                autoUpdateCheckSetting(),
                ignoreUpgradePopSetting(),
              ],
              usingRightClickPopSetting(),
              escToPopSetting(),
            ]),
          ],
        ),
      ),
    );
  }
}
