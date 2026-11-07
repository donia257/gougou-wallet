# 汪汪钱包

独立实现的 Flutter Android 日常记账应用，当前版本 0.2.1。

![汪汪钱包 Logo](assets/brand/wangwang-wallet-logo.png)

支持 Android 7.0 及以上设备。发布标签为 `v0.2.1`，Android 构建号为 `4`。
应用标识为 `io.github.donia257.gougouwallet`。
版本记录见 [CHANGELOG.md](CHANGELOG.md)。

## 功能

- 人民币收入、支出与转账，支持日期、具体时间和备注。
- 日常与账单按日期分组，显示当天收支及每笔账单时间。
- 连续记账、复制账单、编辑删除，以及日期范围、账户、分类组合筛选。
- 分类添加、改名、图标、拖动及菜单排序，删除已使用分类时迁移历史账单。
- 月收支、结余、分类占比、每日支出趋势、月预算与超支提示。
- 设置页提供分类、预算、备份恢复、GitHub 检查更新与应用信息。
- SQLite 本地存储，JSON 完整备份，最近 5 份本机恢复快照。

## 覆盖升级

v0.2.0 使用与 v0.1.0 相同的应用标识和发布签名，直接安装新版 APK 即可覆盖升级。
启动时读取旧版 `daily_ledger.db`，在迁移前保留原账本快照，再将分类名称映射为稳定 ID。
旧账单的金额、日期时间、备注、账户关联、初始余额和预算均参与迁移校验。
设置中的“从文件恢复”支持 v0.1.0 JSON 备份。

已完成真实旧版 SQLite 数据库迁移及事务回滚测试，并在 Android 15 模拟器上安装
v0.1.0 发布包、录入数据、覆盖安装 v0.2.0 发布包进行核对。
模拟器同时验证了系统文件选择器导出备份、导入旧版 JSON，以及从本机快照恢复账本。

## 开发

当前使用 Flutter 3.47.9、JDK 17 和 Android SDK 36。

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
flutter build apk --debug
```

开发工具放在被 Git 忽略的 `.tooling` 中。可以使用
`.\.tooling\flutter\bin\flutter.bat` 调用当前工作区安装的 Flutter。

当前 Windows 环境使用 `tools/dev.ps1` 自动配置本地工具链及英文路径入口。

```powershell
.\tools\dev.ps1 -Command analyze
.\tools\dev.ps1 -Command test
.\tools\dev.ps1 -Command apk
.\tools\dev.ps1 -Command release
.\tools\dev.ps1 -Command run
```

英文入口位于用户目录 `wangwang-wallet-work`，指向原项目。
Gradle 缓存位于用户目录 `.codex/toolchains/wangwang-gradle`，避免中文路径导致 Kotlin 编译失败。
构建依赖使用 Flutter 中国镜像，当前机器的 Gradle 缓存配置了阿里云 Maven 镜像。

## 数据规则

金额使用整数分存储。转账是一条同时关联两个账户的记录，不参与收支和预算计算。
每次保存将完整账本快照写入 SQLite 事务，成功后再更新界面。
日期分组后的账单使用按需构建的滚动列表，自动化测试覆盖 1 万笔记录的查询和显示。
每日首次修改、版本迁移及恢复备份前生成恢复点，保留最近 5 份有效快照。

备份恢复完整校验后，经过确认替换当前账本。备份为明文 JSON，限 20 MB。
卸载应用或清除应用数据会丢失本地账本，请先导出备份。
应用关闭 Android 系统自动备份。正式发布构建从被 Git 忽略的 `android/key.properties`
读取签名配置。当前机器的签名密钥位于 `.tooling/signing`，密码和密钥仅保存在本机。
请另行安全备份签名目录及配置，后续版本需使用同一密钥签名才能覆盖安装。

## GitHub 更新

公开项目为 https://github.com/donia257/gougou-wallet 。
设置页手动检查 GitHub 最新正式 Release，并可通过浏览器进入发布页下载安装包。
GitHub API 限流时，自动通过 GitHub Releases 的公开版本跳转获取最新版本。
联网操作发送版本查询请求，账本保存在本机。
日常记账、统计、分类管理和备份恢复可离线使用。

主界面提供日常、账单、统计、设置四个入口，旧版账户数据用于历史账务关联与转账。

蜜蜂记账和好享记账用于功能研究，未引入其源码。
字体使用 Manrope 与 Noto Sans SC，许可证随字体位于 `assets/fonts`。
