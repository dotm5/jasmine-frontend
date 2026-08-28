# 前后端分仓使用说明

## 仓库与可见性

| 仓库 | 可见性 | 分支 | 职责 |
| --- | --- | --- | --- |
| [dotm5/jasmine-frontend](https://github.com/dotm5/jasmine-frontend) | 公开，Fork 自 ComicSparks/jasmine | `master` | Flutter UI、平台适配、构建入口、公开测试 |
| [dotm5/jmbackend](https://github.com/dotm5/jmbackend) | 私有，独立仓库 | `main` | Rust 实现、固定上游快照、JSON 契约、后端产物包 |

前端通过 `.gitmodules` 中的 `native/` 子模块关联后端。Git 保存的是后端仓库地址和
具体 commit，不复制后端文件进公开历史，也不自动追随后端最新分支。
仓库地址与 commit ID 是公开关联信息；读取源码仍由后端仓库权限控制。

```text
公开前端                                      私有后端
lib/screens、lib/configs                       jmbackend、jmcomic-rs、upstream
lib/basic/methods.dart                         bridge-contract.json
       ↓                                      scripts/build-android.ps1
lib/backend/                                             ↓
  BackendClient / BackendTransport             backend-manifest.json + librust.so
       ↓                                                 ↓
MethodChannel → JNI              ←             构建时验证并接入产物包
```

分仓不改变运行形态：仍是一个 APK，Rust 库在应用进程中工作，没有新增服务器。
页面业务方法保留；相册、设备路径和生物认证留在前端平台层。
`Methods(backend: BackendClient(...))` 支持注入传输，默认仍走 MethodChannel/JNI。

## 获取源码

普通前端克隆不需要后端访问权限，也不要默认递归克隆私有子模块：

```powershell
git clone https://github.com/dotm5/jasmine-frontend.git
```

以下命令都在前端仓库根目录运行。已获后端读取权限的维护者，可使用自己的 GitHub
Git 凭据初始化固定版本：

```powershell
git submodule update --init -- native
git submodule status native
```

未获得后端权限时，保留前端克隆，使用后端维护者交付的产物包即可。
不要把个人 token 写入 `.gitmodules`、仓库 URL、源码或构建日志。

## 工具与目录

复用已有 Flutter、完整 JDK、Android SDK/NDK、Python；源码构建后端时另需已有 Rust
及 Android target。环境入口为 `scripts/configure-local-env.ps1` 和
`scripts/local-env.ps1`，机器路径记录在不提交的 `.toolchains/toolchain-paths.json`。
构建脚本只设置进程环境，不改用户或系统 PATH。

- `.toolchains/`：工具绑定、依赖缓存与下载分块。
- `.tmp/`：临时文件、测试数据和本地审计；完整参考克隆放 `.tmp/upstreams/`。
- `native/upstream/`：后端构建使用的固定源码快照，随私有后端提交。
- `native/target/`、`build/`、`dist/`：构建输出，不提交 Git。

已配置的机器直接使用现有环境，不重复安装。首次配置时按脚本参数绑定已有工具。
GitHub 登录和 Git 推送在普通终端中执行；构建专用进程会隔离 HOME，不向其复制登录凭据。

## 后端独立构建

已初始化子模块并配置工具时：

```powershell
pwsh -NoLogo -NoProfile -NonInteractive -File scripts/build-backend.ps1 `
  -OutputDirectory dist/my-backend-bundle -Offline
```

`-OutputDirectory` 使用尚不存在的目录。此入口只编译后端，不启动 Flutter/Gradle。
后端仓库本身也可独立克隆和构建，见其
[README](https://github.com/dotm5/jmbackend/blob/main/README.md)。
前端的 wrapper 只是复用当前工具、缓存和 ASCII 路径视图。

## 前端只消费后端产物

将维护者交付的产物包放到本仓库 `dist/my-backend-bundle/`，然后运行：

```powershell
pwsh -NoLogo -NoProfile -NonInteractive -File scripts/build-android.ps1 `
  -BackendBundle dist/my-backend-bundle
```

此模式不调用 Cargo/Rust，不读取 `native/` 源码及锁文件。它验证产物清单、库摘要、
ARM64 ELF/JNI、JSON 协议版本及前端方法目录，再运行前端测试、接入库并构建 APK。
前端仍需要 Flutter/JDK/Android SDK/NDK；NDK 也用于 Flutter 插件。
摘要检查验证包内一致性，不替代可信交付或发布者签名。

未传 `-BackendBundle` 时，一键构建先编译子模块后端，再把产物交给前端。
`-SkipTests` 只跳过对应测试，接口、库和 APK 检查仍执行。
当前 Android 本地测试包使用独立应用 ID 和调试签名；正式发行另需配置自己的发布签名。

## 更新后端版本指针

后端的开发提交先在私有仓库完成测试并推送，再更新前端。
将已经审查且已推送的后端 commit ID 赋给 `$BackendCommit`，然后执行：

```powershell
git -C native fetch origin main
# 先确认 native 工作区干净；固定到已审查的 commit，而不是盲目追随 main
git -C native switch --detach $BackendCommit

# 先做接口与集成回归
pwsh -NoLogo -NoProfile -NonInteractive -File scripts/test-api-contracts.ps1

git diff --submodule=log -- native
git add -- native
git diff --cached --stat
git diff --cached --submodule=log
git commit -m "Advance backend to validated contract implementation"
git push origin master
```

`$BackendCommit` 必须已存在于私有远程，以便其他维护者获取该版本。
不要把 `native/` 变回普通源码目录，也不要将 Rust 文件逐个添加到前端索引。
更新前端上游与更新后端指针是两件独立的事，分别审查、验证和提交。

## 接口与 CI 边界

接口规则见后端 [CONTRACT.md](https://github.com/dotm5/jmbackend/blob/main/CONTRACT.md)。
JSON 请求和响应保持字符串 envelope；`bridge-contract.json` 由后端 dispatcher 生成，
产物包携带该契约。前端包构建无需读取私有 Rust 实现。
方法注册和合成响应测试不等于真实账号、线上阅读或下载验收。

本 Fork 使用独立的前后端 CI 与 Android Release 工作流，具体触发方式及产物见
[自动发布说明](CI-RELEASE.md)。公开 PR 仅跑前端测试；受信任的发布任务用专用只读部署密钥
检出 gitlink 固定的后端版本。签名材料保存在 Actions secrets，不存入 Git。
本地个人 `gh` 令牌没有写入 Actions secrets，私有源码与构建日志不作为公开 artifact 上传。

后端“独立”指源码、构建和版本边界，不表示全量原创。Jenny、jmcomic-downloader 等
来源及条件保留在私有仓库的 `UPSTREAM-NOTICES.md` 和 `upstream/` 中。
前端继续保留上游声明，不因仓库公开而替换其使用条件。
