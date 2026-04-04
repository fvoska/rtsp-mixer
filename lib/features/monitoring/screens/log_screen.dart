import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/logging/app_logger.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final _scrollController = ScrollController();
  bool _autoScroll = true;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    AppLogger.instance.addListener(_onLogUpdate);
  }

  @override
  void dispose() {
    AppLogger.instance.removeListener(_onLogUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _onLogUpdate() {
    if (!mounted) return;
    setState(() {});
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  List<String> get _filteredLines {
    final lines = AppLogger.instance.lines;
    if (_filter.isEmpty) return lines;
    final upper = _filter.toUpperCase();
    return lines.where((l) => l.toUpperCase().contains(upper)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final lines = _filteredLines;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Logs (${lines.length})'),
        actions: [
          IconButton(
            icon: Icon(_autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_bottom_outlined),
            tooltip: _autoScroll ? 'Auto-scroll on' : 'Auto-scroll off',
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy all to clipboard',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: AppLogger.instance.exportFromDisk));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logs copied to clipboard')),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              style: theme.textTheme.bodySmall,
              decoration: InputDecoration(
                hintText: 'Filter (e.g. AUDIO, FGS, ERROR)',
                hintStyle: theme.textTheme.bodySmall,
                prefixIcon: const Icon(Icons.filter_list, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
        ),
      ),
      body: ListView.builder(
        controller: _scrollController,
        itemCount: lines.length,
        itemBuilder: (_, i) {
          final line = lines[i];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            child: Text(
              line,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: _colorForLine(line, theme),
              ),
            ),
          );
        },
      ),
    );
  }

  Color _colorForLine(String line, ThemeData theme) {
    if (line.contains('[ERROR]') || line.contains('error') || line.contains('Error')) {
      return theme.colorScheme.error;
    }
    if (line.contains('[FGS]')) return Colors.tealAccent;
    if (line.contains('[LIFECYCLE]')) return Colors.amberAccent;
    if (line.contains('[UI]')) return Colors.lightBlueAccent;
    return theme.colorScheme.onSurface.withValues(alpha: 0.8);
  }
}
