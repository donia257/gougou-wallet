import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ledger.dart';
import 'repository.dart';
import 'ui.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({
    super.key,
    required this.repository,
    required this.currentLedger,
    required this.onRestore,
  });
  final LedgerRepository repository;
  final Ledger? Function() currentLedger;
  final Future<bool> Function(Ledger, String) onRestore;
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool busy = false;
  List<RecoverySnapshot>? snapshots;
  String? error;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final result = await widget.repository.snapshots();
      if (mounted) {
        setState(() {
          snapshots = result;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = '恢复快照暂时无法读取，可选择外部备份文件');
    }
  }

  Future<void> export() async {
    final ledger = widget.currentLedger();
    if (busy || ledger == null) return;
    setState(() => busy = true);
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '保存账本备份',
        fileName: '汪汪钱包-${DateTime.now().millisecondsSinceEpoch}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(ledger.encode())),
      );
      if (result != null && mounted) showMessage(context, '备份已保存');
    } catch (_) {
      if (mounted) showMessage(context, '导出失败，请选择可写入的位置后重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> import() async {
    if (busy) return;
    setState(() => busy = true);
    Ledger? imported;
    String? failure;
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result == null) return;
      final file = result.files.single;
      if (file.size > 20 * 1024 * 1024) {
        throw const FormatException('文件超过 20 MB');
      }
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      if (bytes.length > 20 * 1024 * 1024) {
        throw const FormatException('文件超过 20 MB');
      }
      imported = Ledger.decode(utf8.decode(bytes));
    } on FormatException catch (error) {
      failure = '备份无效，${error.message}';
    } catch (_) {
      failure = '无法读取备份，请选择汪汪钱包导出的 JSON 文件';
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (!mounted) return;
    if (failure != null) showMessage(context, failure);
    if (imported != null) await restore(imported, '恢复外部备份之前');
  }

  Future<void> restore(Ledger ledger, String reason) async {
    if (busy ||
        !await confirmAction(
          context,
          '恢复这份备份？',
          '这份备份包含 ${ledger.entries.length} 笔账单。恢复将替换当前账本，并尝试保留恢复前的本地快照。',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    final success = await widget.onRestore(ledger, reason);
    if (!mounted) return;
    setState(() => busy = false);
    if (success) {
      showMessage(context, '账本已恢复');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('数据与备份')),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        if (busy) const LinearProgressIndicator(),
        panel(
          Column(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.file_download_outlined,
                  color: forest,
                ),
                title: const Text('导出完整备份'),
                subtitle: const Text('保存为 JSON 文件'),
                onTap: busy || widget.currentLedger() == null ? null : export,
              ),
              ListTile(
                leading: const Icon(Icons.restore_rounded, color: forest),
                title: const Text('从文件恢复'),
                subtitle: const Text('支持 v0.1.0 及新版备份'),
                onTap: busy ? null : import,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        sectionTitle('本机恢复快照', action: '刷新', onTap: busy ? null : refresh),
        const Text(
          '保留最近 5 份。每日首次修改、版本迁移和恢复备份前自动生成。',
          style: TextStyle(color: muted, fontSize: 12, height: 1.7),
        ),
        const SizedBox(height: 12),
        if (error != null)
          Text(error!, style: const TextStyle(color: coral))
        else if (snapshots == null)
          const Center(child: CircularProgressIndicator())
        else if (snapshots!.isEmpty)
          emptyState('还没有恢复快照', '记录生活后，这里会陆续保留可恢复的账本。')
        else
          panel(
            Column(
              children: snapshots!
                  .map(
                    (snapshot) => ListTile(
                      leading: const Icon(Icons.history_rounded, color: forest),
                      title: Text(snapshot.reason),
                      subtitle: Text(
                        '${dayKey(snapshot.createdAt)} ${timeLabel(snapshot.createdAt)} · ${snapshot.ledger.entries.length} 笔',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: busy
                          ? null
                          : () => restore(snapshot.ledger, '恢复本地快照之前'),
                    ),
                  )
                  .toList(),
            ),
          ),
        const SizedBox(height: 20),
        const Text(
          '完整备份为明文文件。卸载应用或清除应用数据也会删除本机快照，请将重要备份保存到自选目录。',
          style: TextStyle(color: muted, fontSize: 12, height: 1.8),
        ),
      ],
    ),
  );
}
