# Placard v1.9.2：iOS 26.7.3 第一轮兼容性修复

日期：2026-11-11。目标设备：用户报告的 iPhone 13 / iOS 26.7.3。

当前结论：已实现配对入口、文件校验、Library 路径和安装结果处理的源码修正；尚未完成 Swift 编译、IPA 构建或真机测试。不能宣布 iOS 26.7.3 已兼容，不能确认壁纸已写入或能被系统注册。

## 基线和隔离

- 官方源码标签：[frs0n/placard v1.9.2](https://github.com/frs0n/placard/tree/v1.9.2)。标签对应提交 `7dcefb610cc60ae909b6046beee7adb691148e44`。
- 本地修复分支：`fix/ios-26-7-3-compatibility`。
- 未更改官方远端、未上传源码、未创建 Release、未操作手机或用户系统数据。本地官方远端命名为 upstream，并禁用其推送地址。
- 已连接 GitHub 用户为 `bishouyi254-source`；读取 `bishouyi254-source/placard` 返回 404，仅能说明本次连接未找到可访问的该仓库。
- 未改动原有 bad_query 支持版本表，未通过扩大白名单宣称兼容。

## 六处重点审查结果

| 文件 | 原始问题 | 本轮改动 |
| --- | --- | --- |
| SystemCompatibility.swift | 只有 bad_query 范围，没有独立自配对条件 | 保留原范围；独立定义手机端自配对需要 iOS 27；提取可测试的版本判断 |
| AirliftEntryView.swift | 任意非空配对路径就进入下一步，所有系统都能启动自配对 | iOS 26.7.3 隐藏并阻止自配对；增加系统文件选择器；导入后仍须连接检查 |
| PairingController.swift | 自动扫描 Documents 任意 plist，静默写入失败，文件非空就视为配对成功 | 仅识别两个已知文件名；查询路径不写文件；显式校验、受保护的原子保存；保存与连接验证分开 |
| AirliftWallpaperService.swift | 写入函数返回就被上层当作已安装，并进入刷新屏幕流程 | 校验配对记录和容器路径；保存脱敏阶段记录；返回明确的“注册未验证”结果，阻止自动成功与刷新 |
| InstalledWallpapers.swift | load/delete 无条件调用 bad_query | 进入后台任务后先检查可用性；不支持时说明 Library 不可读，不将其解释为壁纸不存在 |
| Exploit/BadQuery.swift | isAvailable 只查动态符号；底层调用无版本保护 | 同时检查原支持范围和符号；在容器查找、读取授权、枚举入口再次保护 |

Library 没有新增 Airlift 回读能力，也不会展示假造的安装记录。现有界面布局、Browse/Create/Library 三个页签、受支持系统的原 bad_query 路径保留；新增导入按钮和诊断分享按钮，并补充中英文提示。

## 安全导入的边界

新增 PairingRecord.swift：

1. 只读取用户明确选中的本地文件；配对导入本身不发起联网请求。
2. 限制为普通文件、拒绝符号链接、最大 1 MiB，并限制实际读取长度。
3. 解析 XML / binary plist。Remote Pairing 检查 `identifier`、32 字节公私钥及密钥匹配，存在 alt_irk 时要求 16 字节。Lockdown 检查完整的证书/私钥字段和 HostID、SystemBUID、WiFiMACAddress。
4. 校验通过才原子保存到应用 Documents/aircard_pairing.plist，使用完整文件保护、0600 权限和备份排除；不改动所选原文件，不再额外复制到第二个别名。
5. 这只是结构检查：不证明证书有效、来自当前手机、仍被手机信任、网络可连通。真正连接检查仍使用 Airlift 发现 PosterBoard 容器；这也不是壁纸安装验证。

格式依据为 Placard 所固定的 AirCard 提交，而不是用最新实现替换二进制：

- [Remote Pairing 解析器，097a058](https://github.com/Mak5er/AirCard-iOS/blob/097a058c984ffc33ccb697b9dfe8058be3e86244/rust-core/vendor/idevice/src/remote_pairing/rp_pairing_file.rs)
- [Airlift 连接路径，097a058](https://github.com/Mak5er/AirCard-iOS/blob/097a058c984ffc33ccb697b9dfe8058be3e86244/rust-core/src/exploit.rs)
- [上游配对导入和 iOS 27 手机端配对说明](https://github.com/Mak5er/AirCard-iOS/releases/tag/v1.3.1)

请勿把真实配对文件上传到 GitHub、问题反馈或聊天中；其中包含私钥。验收只需要脱敏诊断文件和错误截图。

## 安装后验证：已实现的保护与尚未解决的能力

内置 `airlift.h` 只有容器发现、写目录、注入目录、syslog 和刷新等接口，没有壁纸列表、读取任意文件或读取 PosterBoard 注册状态的接口。因此本轮不能诚实实现“自动确认壁纸已被系统接收”。未替换闭源预编译库，未用 canary 写入或探测性系统修改冒充验证。

当前行为：

- 拒绝非预期的 PosterBoard 容器路径，只允许 Application 容器 UUID 根路径，并接受其 /private 别名。
- 解压失败、没有可识别描述文件、主路径或现代 Collections 路径写入失败均抛错，不再吞错或继续报告完成。
- 删除“找不到描述文件就把整个目录当作描述文件”的兜底路径。
- 保留原标识的 Container 类包会在注入前被拒绝：没有回读能力，不能排除覆盖已有壁纸。普通描述包仍生成新的目录标识。此限制适用于使用本 Airlift 适配器的安装；原受支持 bad_query 安装路径未改。
- Airlift 安装不再覆盖 PosterBoard 和 /var/mobile 的整份偏好文件，不触发文件保护重置。
- 即使全部写入请求返回完成，也抛出专用的“系统注册未验证”结果；沿用现有错误提示界面承载说明，不进入 `.installed`，不自动 respring。现有视频生成入口也经由同一个适配器，受相同结果保护。
- 可能已有部分描述文件被写入；没有自动回滚、删除、清理系统壁纸或盲目再次写入。这个版本更适合收集可靠诊断，不能当作已验证的壁纸安装解决方案。

每次正常结束或抛错会保存应用内 `last-airlift-install.json`，包含时间、系统版本、操作编号、阶段、错误码或“写入完成但注册未验证”。不保存配对密钥、完整容器路径、壁纸内容或原始 FFI 消息。Library 错误页提供“分享安装诊断记录”。若应用被系统强制终止或底层调用一直不返回，结束记录可能来不及更新。

原始 Airlift 日志和安装错误日志改用私密 OSLog；详细 FFI 信息不能因此保证可从普通日志导出读取。设备端错误提示、脱敏 JSON 和实际系统墙纸截图应一起保留。

另外，原安装暂存文件使用用户文件名，可能覆盖同名副本；本轮改用随机暂存名称，清理只针对该次应用内副本，不触碰用户选中的原文件。

## 已执行检查

| 检查 | 本次结果 |
| --- | --- |
| git diff --check | 通过 |
| Swift 第三方语法解析 | 20 个文件中，15 个无解析错误；5 个文件的报错集合与 v1.9.2 相同，来自解析器不支持 #Preview / nonisolated(unsafe)。没有新增解析错误。不是 Swift 编译或类型检查 |
| 两份 Actions YAML 解析 | 通过；新增工作流只有指定修复分支 push 和手动触发，contents 为只读，无 Release 发布步骤 |
| Vendor/AirCard/SHA256SUMS | 9 项验证；2 项二进制直接匹配，7 项文本将 Windows 检出的 CRLF 还原 LF 后匹配；没有更换内置 Airlift |
| Swift 行为回归检查 | 已提供 tests/CompatibilityChecks.swift，涵盖配对格式、密钥不匹配、无关 plist、大小、目录/链接和系统版本边界；由于本机无 Swift/Xcode，尚未运行 |
| Xcode 完整编译、链接、IPA 验证 | 尚未运行；本机为 Windows，无 Xcode |
| iPhone 真机配对、安装、系统注册 | 尚未测试 |

第三方语法检查工具初次运行遇到其 WASM 优化器内存错误；限制 WASM 编译并行并禁用分层优化后正常完成。不能把该检查当作 Apple 编译器的替代。

额外核对：Xcode 项目级最低系统为 27.0，但实际应用目标的 Debug/Release 均为 26.0，目标设置覆盖项目设置。本轮没有修改最低系统，也不将项目层差异当作此次故障原因。

## 后续构建

新增 `.github/workflows/compatibility-unsigned.yml`：在修复分支推送或手动运行时，用 `xcode-27` 构建机与 Xcode 27.0，执行 Swift 回归检查、内置库校验、unsigned archive、导出符号和 Info.plist 检查，再打包 IPA。构建还会核对最低系统为 26.0。

[GitHub 官方构建机列表](https://github.com/actions/runner-images)列出 xcode-27；具体能否排队、使用额度、解析依赖和通过编译，以实际运行结果为准。

产物名：`placard-v1.9.2-compatibility-UNVERIFIED-unsigned.ipa`。只上传 Actions artifact，不创建 Release，不修改官方仓库。原有 release-unsigned 工作流仍保留，不应为本轮测试手动运行它，因为它包含发布 Release 的步骤。

下一步需要确认将代码发布到用户自己的 fork/分支并触发构建。当前没有 IPA，不能把源码 ZIP 当成 IPA 安装。获得确认后才能创建/使用 fork、推送修复分支、运行并检查 Actions，下载真实产物；若编译失败，继续修正后重新构建。

## 真机验收步骤（取得成功构建后再进行）

1. 在“设置 › 通用 › 关于本机”记录 iPhone 型号、iOS 版本及构建号。保留原 IPA 和个人备份。不要卸载现有应用或清除墙纸数据来测试；安装测试包如会替换原应用，先确认应用数据的备份方式。
2. 在 iPhone 13 / iOS 26.7.3 启动测试版，连接 Wi-Fi。配对页面应提供“导入配对文件”，不应显示启动手机端自配对按钮，也不应要求去不存在的系统入口。
3. 用一个无关 plist、空文件测试导入：应明确拒绝。取消选择器应不改变已有配对状态。随后只选择自己这台手机的有效配对文件；导入完成只能进入连接检查页，不能直接宣布配对或壁纸功能成功。
4. 按现有流程连接 LocalDevVPN，再点击“检查并进入”。失败时记录具体错误；不要通过删除系统记录、重置隐私权限或更换他人配对文件来反复尝试。导入结构合格不保证旧记录仍有效。
5. 进入 Library：26.7.3 应说明 bad_query 不支持、Airlift 回读未实现；不得再报一个看似确定的“未找到容器”结论，也不得显示虚构的已安装列表。支持范围内设备应继续走原读取/删除确认流程；该回归尚待设备确认。
6. 先使用无效 ZIP 或不含描述文件的包测试：应报错，不应显示安装成功或刷新屏幕。Container 类保留标识包应明确拒绝写入。
7. 如愿意进行一次实际写入测试，仅选一份可信的普通描述包，点击一次安装。记录 UI 阶段与返回消息。即使写入请求完成，也应显示“注册未验证”，不应自动刷新。此操作可能留下部分写入；不要连续点击重试。
8. 打开“设置 › 墙纸 › 添加新墙纸”和现有锁屏切换列表，检查是否出现目标壁纸。未出现仍是未通过验收，不代表可以安全重复写入。此轮不自动 respring；如后续需要手动刷新才能判断，应另行确认并记录刷新前后结果。
9. 返回 Library 的错误页，用“分享安装诊断记录”保存 JSON；同时保留系统墙纸截图与错误提示。不要分享配对文件。诊断中的 write-requests-completed-registration-unverified 只能证明调用链走到该阶段，不能证明设备实际写入和注册成功。
10. 即使墙纸出现，还需验证选择、锁屏显示、动画、重启后状态，以及原有壁纸未受影响。只有这些真机结果才能决定是否继续适配。若未出现，下一步需新增经过审查的只读设备端回读/PosterBoard 日志能力，不应扩大白名单或盲改偏好文件。
