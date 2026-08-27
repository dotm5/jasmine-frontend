# 工作区边界

- 本任务工作目录是本仓库根目录。禁止在上级目录或兄弟项目中创建克隆、下载、临时脚本、日志和构建输出。
- 新增及从上级迁回的完整参考仓库统一放在 `.tmp/upstreams/`；发布样本与审计中间文件放在 `.tmp/`；工具链与下载分块放在 `.toolchains/`。
- `native/upstream/` 是参与源码构建的固定上游快照，不是可以随意清理的临时克隆。
- 编译输出使用现有 `native/target/`、`build/`、`dist/`。本项目脚本通过 `scripts/workspace-paths.ps1` 将进程 TEMP/TMP 和 Android 用户目录设在仓库内。
- 不在仓库外创建用于 ASCII 路径的 junction/源码副本。Windows 构建优先使用已有短路径，否则使用经过检查的临时盘符映射，并在 finally 中撤销。
- 既有系统工具、共享用户缓存和其他项目不作整体搬迁或清理。新增的本任务参考仓库必须使用上述项目内路径。
- 准备工具先检查现有安装；已存在的 Flutter/SDK/NDK/Gradle 直接复用。JDK/Rust/Python 通过 `.toolchains/toolchain-paths.json` 绑定已有程序路径，不复制安装副本，不重复运行安装器。
- JDK 校验包含 java、javac、jlink、jmod、jar 和 java.base.jmod；只有 java/javac 的 IDE 运行时不算完整 Android 构建 JDK。当前完整 JDK 已位于 `.toolchains/jdk21`，后续直接复用。
- 本地构建先调用 `scripts/local-env.ps1` 的 `Enter-LocalToolEnvironment`。Cargo/Pub/Gradle/Android/Python 缓存、HOME/USERPROFILE/AppData 只在当前构建进程中指向项目目录，不写用户/系统环境变量或注册表 PATH。
- 只读使用原有共享依赖缓存；按锁文件通过 `seed_local_caches.py` 复用选定依赖，不复制凭据或全局配置。禁止自动 `rustup install` / `rustup target add` 或全局 pip 安装；缺项先识别，已有项不重装。
- 移动/清理前确认绝对路径、所有权及重解析点；保留用户已有修改，不覆盖、不重置、不批量暂存。
