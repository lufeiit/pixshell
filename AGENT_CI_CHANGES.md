# 完善 SSH 代理、连接管理器、快捷命令、设置中心与 WebDAV 同步

## 修改内容

- 修复 macOS 26 下旧版 SSH 算法兼容和 OpenSSH 代理连接问题，避免代理握手后丢失 SSH banner。
- 修复 SFTP 会话关闭时阻塞主线程导致程序无响应的问题，并隐藏首次保存主机指纹的普通警告。
- 支持为每台主机单独选择代理，并完善代理连接超时处理。
- 连接管理器支持窗口尺寸与位置记忆、按名称/IP 排序、手动调整分组和组内主机顺序。
- 连接管理器支持跨分组勾选多台主机并批量打开会话。
- 修复连接管理器列表高度、自适应布局、窗口拖动及禁用按钮在深浅主题下的显示问题。
- 增加 SSH 自动重连和快捷命令内联参数、参数历史记录等功能；参数名支持英文和中文字符。
- 快捷命令支持分组/命令拖动排序、无参数命令双击发送、全局历史和远端命令/路径 Tab 补全。
- 增加 WebDAV 多设备双向同步：启动同步、定时同步、本地修改延迟同步、ETag 并发保护和三方合并。
- 增加 WebDAV 同步日志，记录下载、合并、上传、冲突重试、成功及失败信息，并保留最近 100 条。
- 将常规、终端、代理、密钥、主机指纹、AI、备份和软件更新入口集中到单窗口设置中心。
- 设置窗口、侧栏、内容区及内嵌代理管理页面跟随当前主题颜色。

## 功能与实现文件

### 1. SSH 兼容、代理连接和自动重连

- [`mac/Sources/PixShell/SSH/OpenSSHSession.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-7c5c9c2e8b63cb29af155db5f954b14fe4f9fda7deed6d0fff05f4a284fbd063)：组装 macOS OpenSSH 参数；在需要时启用旧 RSA 算法兼容；接入代理桥；处理连接输出和断开状态。
- [`mac/Sources/PixShell/Proxy/ProxyStdioBridge.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-175f605afd0d30e5ec6f05ac52e1a55cc7a9eca1570d0eaccae77eb1090fc7e3)：为 HTTP、SOCKS4、SOCKS5 代理建立标准输入输出桥，完成代理认证和目标地址握手，再把字节流交给 OpenSSH。
- [`mac/Sources/PixShell/App/AppDelegate+Sessions.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-41d5a31273d9f5f68de2acfd7a625071692c8959c4e46a33b9e3bee104f53e99)：创建 SSH 会话、传递每台主机的代理配置、显示连接状态，并在异常断开后按等待时间自动重连。
- [`mac/Sources/PixShell/Session/TermSession.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-8eaea1d74d0d0c15edfa1020a3b36a35b3e03aa44173ad31d8d6f5625f2eee11)：保存会话重连计数和延迟任务，避免重复重连或关闭标签后继续重连。
- [`mac/Sources/PixShell/SFTP/OpenSSHSFTPSession.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-4a6aee2d07505b882cffe13e135a3b27565925a385ef733355bbb8a2c6096587)：修复 SFTP 进程关闭时在主线程等待造成的界面无响应。
- [`mac/Sources/PixShell/Bridge/AgentMCP.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-a19cafdc5fd3adc7a876d0424630b15c18e662d405f1f0a6c46e3bf45324ec83)：调整 MCP SSH 调用的等待时间，使慢速连接有足够时间完成握手。

### 2. 每台主机独立代理配置

- [`mac/Sources/PixShell/UI/HostEditor.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-b74d1d5c6370410d39ff8161e10186e68a8a2b831aab8e2af9c25c1957b3c77c)：在主机编辑器中提供代理选择，并保存主机对应的 `proxyId`。
- [`mac/Sources/PixShell/App/AppDelegate+Layout.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-682f3897a6e35acc12fbfa6ab2b04c9920b78452877895c9091263d13af0824e)：初始化代理、备份和同步相关管理器，并把主机代理选择传入连接流程。
- [`win/HostEditWindow.xaml`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-77b960c9b3adfb31d1b351d580d4735a2bd09a1f766811e9cdef3efb6c5061f6)：Windows 主机编辑窗口的代理选择界面。
- [`win/MainWindow.xaml.cs`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-5a0e104e6cc15413c98191a1d37a80483f21e792f250598e89b8638ac3f064e9)：Windows 端保存代理配置，并在连接与重连时使用主机选定的代理。

### 3. 连接管理器排序、缩放与批量连接

- [`mac/Sources/PixShell/UI/ConnManager.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-44ec8903fa5ef5651ef75147ce618bb4ece43ecf7e4eedf1aebbb56665255954)：负责窗口尺寸与位置记忆、列表自适应、按名称/IP 排序、分组和主机手动排序、跨分组多选及批量连接。
- [`mac/Sources/PixShell/Store/HostStore.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-269cf9af76f68c2617b1868e412f6608b2fb0f69e3433b1a781586990ea8ace0)：持久化分组/主机排序结果，提供批量替换接口，并通知 WebDAV 同步本地数据已变化。
- [`mac/Sources/PixShell/UI/Components.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-94ae98ae5132256477ed25d9a11143396671aa2a0227ca230f4c75ad9a350ce0)：统一按钮和徽章状态显示，修复禁用按钮在深浅主题下对比度不足，并允许配置状态徽章动态更新。

### 4. 快捷命令内联参数与历史记录

- [`mac/Sources/PixShell/UI/CommandPanel.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-4c0702dc022b4e97f7af86e6428b5d36eb1f924dd0c8fe5b55ac551904c752e3)：启动时选中用户排序中的第一个文件夹，“全部”固定在最后；点击命令或齿轮只更新左列下方的代码和参数，不覆盖右侧编辑器；参数区横向滚动且发送区固定；无参数命令可双击直接发送；右侧编辑器支持全局历史和可用键盘/鼠标选择的 Tab 补全弹层；左右栏可拖动缩放并记忆宽度。
- [`mac/Sources/PixShell/UI/FlowView.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-3e80ebe9fa3eeb87cf3142c491b85077cd7eea101eb74b6bd38a9e9c025f6fa4)：为自动换行的分组和命令容器提供通用拖动换位能力，松开鼠标后回调数据层保存顺序。
- [`mac/Sources/PixShell/App/AppDelegate+CommandBox.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-57cb0ac00f2390c2b69746aaea0233723a095ab09129787f8fa35296b4aa0721)：汇总所有主机的命令历史，并通过当前 SSH 会话查询远端命令名或路径补全候选。
- [`mac/Sources/PixShell/Store/CommandBox.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-2d89ed3e2c91c16a8a0bf5b9834867fd0d6db9759a0100ca57ae62bfe9f49316)：解析和替换 `${参数}` 模板，使用 Unicode 规则同时支持 `${port}`、`${端口}` 和带 URL 等冒号内容的 `${名称:默认值}`。
- [`mac/Sources/PixShell/Store/QuickCommands.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-f4fd9681cc316a77f67619d11fdb8133ad18d15330ac8318da8536c6ba5631c4)：持久化快捷命令、分组顺序和组内命令顺序，提供完整替换和变更通知，供 WebDAV 多设备同步使用。
- [`mac/Sources/PixShell/Store/L10n.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-000490619b6865da5e7ee6f4dcaf946d45478cfa2c3f215ba18e8d0d91c69e3e)：统一“当前会话”和“所有会话”等发送目标文本。
- [`win/CommandPanel.xaml`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-3c42d1a108805c17c3e3ccb93abc8034f8f3e2c451e6a5ce9deba48ef0b0e76e)：Windows 快捷命令参数输入区域。
- [`win/CommandPanel.xaml.cs`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-d986528afe2c12fd3f0ca53c486950a2605752a0459af621d67aae5bbb1cb625)：Windows 参数识别、历史值管理、替换与发送逻辑。
- [`win/Store/CommandBox.cs`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-a71df00337e00111ed08deffb3c572570aaada04f53185abfad6837318e98643)：Windows 端使用相同 Unicode 参数名规则，保持中英文占位符行为一致。

### 5. WebDAV 多设备双向同步

- [`mac/Sources/PixShell/Store/WebDAVSyncCoordinator.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-fa7b53fb782276565ac02f0ee67fe60d541022935405b57b3122a6f941ab33d0)：同步核心；负责启动/定时/本地修改触发、ETag 条件上传、并发重试、三方合并、删除同步、冲突保留本机版本及最近 100 条日志。
- [`mac/Sources/PixShell/Store/BackupBundle.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-e31001f426814b685bf3e65e0b0d80336a50d98dc589ec3fa4f04cfefc2c6e94)：定义可比较的备份数据；提供 WebDAV 原始下载和带 `If-Match`/`If-None-Match` 的条件上传接口。
- [`mac/Sources/PixShell/UI/BackupPanel.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-20e921b9cdf46ed3eb8369211d603c5c014be9888d20bab44aae9bdc7fca61ad)：显示 WebDAV 配置状态、启用开关和同步日志；其他尚未实现的云服务明确显示为“未实现”。
- [`mac/Sources/PixShell/App/AppDelegate+Menu.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-2288ad73e9c38b5ac95e5f2d5fe0645d10f2f348656f649f6d23345d547e17af)：配置 WebDAV URL、用户名、应用密码和同步周期；生成本机备份快照并应用合并后的数据。
- [`mac/Sources/PixShell/main.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-bc7eff26afd06cd61bed21f845cc476cfc1f289e9f2fb8577fc5d93ef53c0fcb)：持有同步协调器，应用启动后开启同步，退出时清理定时器和通知观察者。

同步策略说明：

1. 每台设备保存上次成功同步的基线。
2. 同步时比较“本机、远端、基线”三份数据，从而识别单侧新增、修改和删除。
3. 上传时携带 ETag，避免覆盖另一设备刚上传的新版本。
4. 若 ETag 已变化则重新下载并合并一次；同一记录在两端同时修改时保留本机版本，并在日志中显示冲突数量。
5. SSH 密码、私钥密码和 WebDAV 应用密码仍只保存在本机 Keychain，不写入备份文件。

### 6. 单窗口设置中心与主题外观

- [`mac/Sources/PixShell/UI/SettingsCenter.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-9f96ebaf891bb7512ad3e245396615e2a013a3e2e82160ff1b28be6b02a93059)：创建单实例设置窗口和左侧分类导航；在右侧原地切换常规、终端、代理、密钥、指纹、AI、备份和更新页面；切换主题时同步刷新标题栏、侧栏及内容背景。
- [`mac/Sources/PixShell/UI/ProxyPanel.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-7ba4894127b60993986beba9928908ec836866b9d76f36d9e5cc130044fe58f5)：保留原独立弹层模式，同时增加设置页内嵌模式；内嵌时取消遮罩、固定尺寸、拖动和关闭按钮，随内容区自动伸缩。
- [`mac/Sources/PixShell/UI/KeyManager.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-1bfe9f67eeac321d9f8589708b49ec0d2c129d58bb7c3196c8ba6f2afa435ec9)：允许密钥管理内容临时嵌入设置中心，切换页面后可归还原窗口。
- [`mac/Sources/PixShell/UI/FingerprintManager.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-58c9a6842aa4c8f65522facfedfb4e7dbe8ba32500418e5b1de9ac3f8a147e8d)：允许主机指纹管理内容临时嵌入设置中心。
- [`mac/Sources/PixShell/UI/AiSshBridgeManager.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-ef0365f841f6b509e2ab8363d1785dc8d5666436276a7ab3e78fd00c299834e2)：允许 AI 对接页面临时嵌入设置中心，并统一关闭回调。
- [`mac/Sources/PixShell/App/AppDelegate+MainMenu.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-e496e248d10c559693bfd845343b28cf3a17a2cac18488dc128ea022e6089d0f)：整理主菜单入口，把可配置项目集中到设置中心。
- [`mac/Sources/PixShell/App/AppDelegate+Layout.swift`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-682f3897a6e35acc12fbfa6ab2b04c9920b78452877895c9091263d13af0824e)：软件启动时默认显示命令页；设置、连接管理器等独立窗口以 PixShell 主窗口当前所在屏幕为准定位，改善 macOS 多屏使用体验。

### 7. 本地打包稳定性

- [`mac/scripts/package-mac.sh`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-2153246fe8ce33de060124d2d9913291609157911dac04eb945f10a445ce859c)：本地打包使用稳定签名身份，减少每次重新构建后重复请求钥匙串授权。
- [`mac/scripts/make-dmg.sh`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-4f2466dfb288008d0bcfba5e0159325452cc12314429164e0276a2bd2847bb9b)：调整 DMG 生成与签名流程，保持本地测试包结构一致。

### 8. fork CI 构建与 GitHub Release

- [`.github/workflows/build.yml`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-5c3fa597431eda03ac3339ae6bf7f05e1a50d6fc7333679ec38e21b337cb6721)：只在 fork 的 `agent/ci` 分支推送或手动运行时构建 macOS arm64/x64 与 Windows x64 安装包；构建完成后创建或更新 `v1.7.5` GitHub Release，并覆盖上传同版本产物。同步作者 `main` 不会触发此工作流。
- [`AGENT_CI_CHANGES.md`](https://github.com/lufeiit/pixshell/compare/main...agent/ci#diff-229b2b48b227a8a15be6e2972c9b114e7e72740ca7ab804151932fc4110ad2f4)：即本说明，按功能列出 `agent/ci` 相对 `main` 的实现文件，并提供可点击的逐文件 diff 链接。

## 原因与影响

这些修改主要解决代理 SSH 会话卡在“打开会话”、SFTP 关闭造成界面无响应、连接管理器大量主机不便管理，以及快捷命令参数无法正常使用等问题。更新后可按主机配置代理、批量连接、排序并保存连接管理器布局，同时提高异常网络环境下的连接稳定性。

在此基础上，WebDAV 同步解决多台设备之间需要反复手动导出和导入配置的问题。同步采用 ETag 和三方合并，尽量避免不同设备互相覆盖；发生同一记录的并发修改时会保留本机版本并留下可见日志。

设置相关入口集中到同一窗口，避免每点击一个配置项就打开独立窗口或导致原设置页面消失；设置窗口背景和内嵌页面会跟随主题更新。

## 验证

- macOS 使用 Xcode Swift 6 工具链执行 `swift build`，构建通过。
- 本地生成并运行 arm64 `PixShell.app` 测试包。
- 已验证密码与密钥登录、HTTP/SOCKS5 代理连接、连接管理器缩放及批量选择界面。

## 审阅建议

建议按以下顺序审阅，便于区分功能边界：

1. SSH/代理连接：`OpenSSHSession.swift`、`ProxyStdioBridge.swift`、`AppDelegate+Sessions.swift`。
2. 连接管理器：`ConnManager.swift`、`HostStore.swift`、`Components.swift`。
3. 快捷命令：macOS/Windows 的 `CommandPanel` 和 `QuickCommands.swift`。
4. WebDAV：`WebDAVSyncCoordinator.swift`、`BackupBundle.swift`、`BackupPanel.swift`。
5. 设置外观：`SettingsCenter.swift`、`ProxyPanel.swift` 和三个 Manager 的内嵌接口。
