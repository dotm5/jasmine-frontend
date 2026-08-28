import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:jasmine/basic/methods.dart';

import 'network_host.dart';

late String _cdnHost;

// Keep the current Rust/downloader IMAGE_DOMAIN as the persisted default;
// JMcomic3's default remains an additional candidate below.
const _defaultCdnHost = 'cdn-msp2.jmapiproxy2.cc';

String get currentCdnHostName => _cdnHost;

String normalizeCdnHostCandidate(Object? raw, {String fallback = ''}) {
  return normalizeNetworkHostCandidate(raw, fallback: fallback);
}

const _base64List = [
  "Y2RuLW1zcDMuam1kYW5qb25wcm94eS52aXA=",
  "Y2RuLW1zcDMuam1hcGlub2RldWR6bi5uZXQ=",
  "Y2RuLW1zcC5qbWFwaXByb3h5My5uZXQ=",
  "Y2RuLW1zcDIuam1hcGlub2RldWR6bi5uZXQ=",
  "Y2RuLW1zcDIuam1hcGlwcm94eTEuY2M=",
  "Y2RuLW1zcDIuam1hcGlwcm94eTIuY2M=",
  "Y2RuLW1zcC5qbWFwaW5vZGV1ZHpuLm5ldA==",
  "Y2RuLW1zcC5qbWFwaXByb3h5MS5jYw==",
  "Y2RuLW1zcC5qbWFwaXByb3h5Mi5jYw==",
];

const _additionalFallbackCdnHosts = <String>[
  // JMcomic3 network_cdn_host.dart defaultCdnHost.
  'cdn-msp3.jmapiproxy1.cc',
];

var _cdnList = <String>[];

Future<void> initCdnHost() async {
  _cdnList = <String>[];
  _mergeCdnList(<Object?>[
    _defaultCdnHost,
    ..._additionalFallbackCdnHosts,
    ..._base64List.map((e) => utf8.decode(base64.decode(e))),
  ]);
  try {
    final config = await methods.appConfig();
    final hosts = config['cdnHosts'];
    if (hosts is Iterable) {
      _mergeCdnList(hosts.cast<Object?>());
    }
  } catch (_) {
    // The local fallback remains usable when capability discovery is absent.
  }
  final rawLoaded = await methods.loadCdnHost();
  _cdnHost = normalizeCdnHostCandidate(rawLoaded, fallback: _defaultCdnHost);
  _mergeCdnList(<Object?>[_cdnHost]);
  if (rawLoaded.trim() != _cdnHost) {
    await methods.saveCdnHost(_cdnHost);
  }
}

void _mergeCdnList(Iterable<Object?> items) {
  _cdnList = mergeNetworkHostCandidates(<Object?>[..._cdnList, ...items]);
}

Future chooseCdnHost(BuildContext context) async {
  final choose = await chooseCdnDialog(context);
  if (choose != null) {
    final normalized = normalizeCdnHostCandidate(
      choose,
      fallback: _defaultCdnHost,
    );
    await methods.saveCdnHost(normalized);
    _cdnHost = normalized;
    _mergeCdnList(<Object?>[_cdnHost]);
  }
}

Widget cdnHostSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        onTap: () async {
          await chooseCdnHost(context);
          if (context.mounted) setState(() {});
        },
        title: const Text("图片线路"),
        trailing: const Icon(Icons.chevron_right),
        subtitle: Text(_cdnHost),
      );
    },
  );
}

Future<T?> chooseCdnDialog<T>(BuildContext buildContext) async {
  return await showDialog<T>(
    context: buildContext,
    builder: (BuildContext context) {
      return SimpleDialog(
        title: const Text("图片线路"),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text('测速仅供参考，请以实际加载结果为准。'),
          ),
          ..._cdnList.map(
            (e) => SimpleDialogOption(
              child: CdnOptionRow(e, key: Key("CDN:${e}")),
              onPressed: () {
                Navigator.of(context).pop(e);
              },
            ),
          ),
          SimpleDialogOption(
            child: const Text("手动输入"),
            onPressed: () async {
              final value = await _manualInputApiHost(context);
              if (context.mounted && value != null) {
                Navigator.of(context).pop(value);
              }
            },
          ),
          SimpleDialogOption(
            child: const Text("取消"),
            onPressed: () {
              Navigator.of(context).pop(null);
            },
          ),
        ],
      );
    },
  );
}

final TextEditingController _controller = TextEditingController();

Future<String?> _manualInputApiHost(BuildContext context) async {
  _controller.text = _cdnHost;
  return await showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text("输入图片线路地址"),
        content: TextField(
          controller: _controller,
          decoration: const InputDecoration(hintText: "www.example.com"),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop(_controller.text);
            },
            child: const Text("确定"),
          ),
        ],
      );
    },
  );
}

class CdnOptionRow extends StatefulWidget {
  final String value;

  const CdnOptionRow(this.value, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _CdnOptionRowState();
}

class _CdnOptionRowState extends State<CdnOptionRow> {
  late Future<int> _feature;

  @override
  void initState() {
    super.initState();
    _feature = methods.pingCdn(widget.value);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(child: Text(widget.value)),
        const SizedBox(width: 12),
        FutureBuilder(
          future: _feature,
          builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const PingStatus("测速中", Colors.blue);
            }
            if (snapshot.hasError) {
              return const PingStatus("失败", Colors.red);
            }
            int ping = snapshot.requireData;
            if (ping <= 200) {
              return PingStatus("${ping}ms", Colors.green);
            }
            if (ping <= 500) {
              return PingStatus("${ping}ms", Colors.amber.shade800);
            }
            return PingStatus("${ping}ms", Colors.orange);
          },
        ),
      ],
    );
  }
}

class PingStatus extends StatelessWidget {
  final String title;
  final Color color;

  const PingStatus(this.title, this.color, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('\u2022', style: TextStyle(color: color)),
        Text(" $title"),
      ],
    );
  }
}
