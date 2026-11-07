import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'ui.dart';
import 'update_service.dart';

class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key, this.service});
  final UpdateService? service;
  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  bool checking = false;
  GithubRelease? release;
  String? status;

  Future<void> check() async {
    if (checking) return;
    setState(() {
      checking = true;
      status = null;
      release = null;
    });
    try {
      final latest = await (widget.service ?? UpdateService()).latest();
      if (mounted) {
        setState(() {
          release = latest;
          status = isNewerVersion(latest.tag, appVersion)
              ? '发现新版本 ${latest.tag}'
              : '当前已是最新版本';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => status = error is HttpException || error is FormatException
              ? (error is HttpException
                    ? error.message
                    : (error as FormatException).message)
              : '暂时无法检查更新，请稍后重试',
        );
      }
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> open(Uri url) async {
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication) &&
          mounted) {
        showMessage(context, '未能打开浏览器，请稍后重试');
      }
    } catch (_) {
      if (mounted) showMessage(context, '未能打开浏览器，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('检查更新')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              'assets/brand/wangwang-wallet-logo.png',
              width: 96,
              height: 96,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          '汪汪钱包',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '当前版本 v$appVersion · 构建 $appBuild',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 28),
        panel(
          const Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              '更新源为 GitHub 官方项目。点击检查时联网获取正式版本信息，记账数据保存在本机。',
              style: TextStyle(color: muted, height: 1.7),
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: checking ? null : check,
          icon: const Icon(Icons.system_update_alt_rounded),
          label: Text(checking ? '正在连接 GitHub…' : '检查更新'),
        ),
        if (checking)
          const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        if (status != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              status!,
              style: const TextStyle(
                color: forest,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (release != null && isNewerVersion(release!.tag, appVersion)) ...[
          if (release!.notes.isNotEmpty)
            panel(
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  release!.notes,
                  style: const TextStyle(height: 1.7),
                ),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => open(release!.url),
            child: const Text('到 GitHub 下载新版'),
          ),
        ],
        TextButton(
          onPressed: () => open(Uri.parse(githubRepositoryUrl)),
          child: const Text('查看 GitHub 项目'),
        ),
      ],
    ),
  );
}
