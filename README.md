# 汪汪钱包

独立实现的 Flutter Android 日常记账应用，当前版本 0.1.0。

![汪汪钱包 Logo](assets/brand/wangwang-wallet-logo.png)

首版面向 Android 7.0 及以上设备。发布标签为 `v0.1.0`，Android 构建号为 `1`。
应用标识为 `io.github.donia257.gougouwallet`。
版本记录见 [CHANGELOG.md](CHANGELOG.md)。

## 功能

- 人民币收入、支出、账户间转账，支持日期、备注和自定义分类。
- 账单编辑删除、按月查询、类型筛选与备注/账户/分类搜索。
- 月收支、结余、支出分类占比、月预算与超支提示。
- 多账户与初始余额，余额从完整流水计算。
- 本地 SQLite 持久化，JSON 完整备份导出与校验恢复。

## 开发

使用 Flutter stable、JDK 17+ 和 Android SDK。

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
该方案面向个人日常账本，列表和快照在内存中处理，大量历史记录时需评估性能。

备份恢复完整校验后，经过确认替换当前账本。备份为明文 JSON，限 20 MB。
卸载应用或清除应用数据会丢失本地账本，请先导出备份。
应用关闭 Android 系统自动备份。正式发布构建从被 Git 忽略的 `android/key.properties`
读取签名配置。当前机器的签名密钥位于 `.tooling/signing`，密码和密钥仅保存在本机。
请另行安全备份签名目录及配置，后续版本需使用同一密钥签名才能覆盖安装。

## 当前范围

本版本覆盖本地手动记账。云同步、在线账号、AI、语音、OCR、微信/支付宝账单导入、
周期记账、共享账本、多币种和应用锁留待后续需求确认。
支持新增分类，以及账户新增、重命名和初始余额调整。账户删除和分类重命名、删除尚未提供。

蜜蜂记账和好享记账用于功能研究，未引入其源码。
字体使用 Manrope 与 Noto Sans SC，许可证随字体位于 `assets/fonts`。
