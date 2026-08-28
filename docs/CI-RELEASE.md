# 自动测试与 Android 发布

## 触发方式

- 前端 `master` 推送和 PR：Flutter 单元/组件测试、Python 工具测试、静态分析。
- 前端 `master` 推送：测试通过后构建 Android ARM64，自动创建 `ci-<commit>` 预发布。
- 前端 `v*` 标签：执行相同检查后创建正式 Release。Actions 的 Android Release 也可手动运行。
- 后端 `main` 推送和 PR：Rust 单元测试、SQLite 冒烟、工具测试和 ARM64 编译。
- 后端 `main` 推送成功：创建私有 `backend-<commit>` 预发布；`backend-v*` 标签创建正式发布。

发布先后顺序为后端提交与推送 → 前端更新 `native/` gitlink → 前端提交与推送。
前端构建严格使用 gitlink 指定的后端提交，不跟随移动的 `main`。已有 Release 不覆盖；
重新发布请使用新提交或新标签。

## 发布内容

公开前端 Release 附带 ARM64 APK、`SHA256SUMS.txt`、`build-manifest.json` 和 `licenses.zip`。
清单记录前后端提交、库摘要、签名证书、测试覆盖及 Actions 运行地址。
私有后端 Release 附带独立二进制 bundle 和 SHA-256 校验。

当前固定 Flutter 3.29.3、Rust 1.97.1、NDK 26.3.11579264、Android SDK 35、JDK 21。
CI runner 是临时 Linux 环境；现有 Windows 本地构建入口不变。

## 密钥与公开范围

- `BACKEND_DEPLOY_KEY`：专属于后端仓库的只读 SSH 部署密钥，仅受信任的发布任务检出后端时使用。
- `ANDROID_SIGNING_KEY_BASE64`、`ANDROID_SIGNING_STORE_PASSWORD`、`ANDROID_SIGNING_KEY_PASSWORD`：稳定签名材料。
- 公共 `ci/android-signing.sha256` 固定证书摘要，校验不一致即停止发布。当前签名与既有 Local APK 相同，支持保留数据覆盖安装；与上游原版签名不同。
- PR 测试不读取私有后端，不接触部署或签名密钥。发布仅允许本仓库的 `master` 或 `v*` 标签。
- 私有后端源码与构建缓存不上传公开 artifact。公开发布任务的 Rust 编译及跨语言测试日志不输出，避免错误诊断包含私有源码；失败可在私有后端 CI 或本地复现。
- 上传产物使用明确白名单，发布权限仅授予独立 publish job；不保存个人 gh 令牌到仓库 secrets。
- 如需轮换密钥，在仓库设置更新 secrets，并同步证书摘要。更换签名会影响旧安装的直接升级，请先规划数据迁移。

原有 OHOS 工作流保留但禁用，本轮不承诺尚未验证的多平台产物。

## 验收范围

CI 的 API 覆盖使用 loopback HTTP、合成账号/页图和新建 SQLite，包含真实 Dart → Rust 路径。
签名、JNI 库一致性、16 KiB 对齐和 Android 自适应 manifest 均在发布前核验。
这些检查不代表真实账号、远端 API/CDN 或实机阅读已验收。

参考：[GitHub 部署密钥](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys)、
[工作流权限](https://docs.github.com/en/actions/concepts/security/github_token)。
