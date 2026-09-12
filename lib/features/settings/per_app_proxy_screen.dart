import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/native_models.dart';
import '../../core/platform/nirang_native.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_surface.dart';
import '../vpn/app_controller.dart';
import 'per_app_ordering.dart';

class PerAppProxyScreen extends ConsumerStatefulWidget {
  const PerAppProxyScreen({required this.settings, super.key});

  final NativeSettings settings;

  @override
  ConsumerState<PerAppProxyScreen> createState() => _PerAppProxyScreenState();
}

class _PerAppProxyScreenState extends ConsumerState<PerAppProxyScreen> {
  late String _mode;
  late Set<String> _selected;
  late final Future<List<_InstalledApp>> _apps;
  String _query = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.settings.perAppMode;
    _selected = widget.settings.perAppPackages.toSet();
    _apps = NirangNative.installedApps().then(
      (items) => items.map(_InstalledApp.fromMap).toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const GlassSurface(
          radius: 0,
          style: NirangGlassStyle.chrome,
          showShadow: false,
          showBorder: false,
          child: SizedBox.expand(),
        ),
        title: Text(context.s('perAppProxy')),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.s('apply')),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: GlassSurface(
              radius: 18,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: context.s('searchApplications'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _ModeSelector(
                          value: _mode,
                          onChanged: (value) => setState(() => _mode = value),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: context.s('perAppModeHelp'),
                        visualDensity: VisualDensity.compact,
                        onPressed: _showModeHelp,
                        icon: const Icon(Icons.info_outline_rounded, size: 20),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<_InstalledApp>>(
              future: _apps,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final apps = orderSelectedFirst(
                  snapshot.data!.where(
                    (app) =>
                        _query.isEmpty ||
                        app.name.toLowerCase().contains(_query) ||
                        app.packageName.toLowerCase().contains(_query),
                  ),
                  isSelected: (app) => _selected.contains(app.packageName),
                  label: (app) => app.name,
                );
                if (apps.isEmpty) {
                  return Center(child: Text(context.s('noApplicationsFound')));
                }
                return ListView.builder(
                  itemCount: apps.length,
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 24),
                  itemBuilder: (context, index) {
                    final app = apps[index];
                    final checked = _selected.contains(app.packageName);
                    return CheckboxListTile(
                      value: checked,
                      enabled: _mode != 'all',
                      secondary: app.icon == null
                          ? CircleAvatar(
                              backgroundColor: scheme.primaryContainer,
                              child: Text(app.name.characters.first),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                app.icon!,
                                width: 40,
                                height: 40,
                                cacheWidth: 80,
                                cacheHeight: 80,
                              ),
                            ),
                      title: Text(app.name),
                      subtitle: Text(
                        app.packageName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onChanged: _mode == 'all'
                          ? null
                          : (value) => setState(() {
                              if (value == true) {
                                _selected.add(app.packageName);
                              } else {
                                _selected.remove(app.packageName);
                              }
                            }),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showModeHelp() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          content: Text(context.s('perAppModeHelpBody')),
        ),
      );
  }

  Future<void> _save() async {
    if (_mode == 'selected' && _selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.s('selectOneApplication'))),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(appControllerProvider.notifier).updateSettings({
        'perAppMode': _mode,
        'perAppPackages': _selected.toList(growable: false),
      });
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final modes = <(String, String)>[
      ('all', context.s('allApps')),
      ('selected', context.s('selectedOnly')),
      ('exclude', context.s('exclude')),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final mode in modes)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Material(
                  color: value == mode.$1
                      ? scheme.primaryContainer.withValues(alpha: .78)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: () => onChanged(mode.$1),
                    child: SizedBox(
                      height: 38,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              mode.$2,
                              maxLines: 1,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    fontWeight: value == mode.$1
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InstalledApp {
  const _InstalledApp(this.packageName, this.name, this.icon);

  factory _InstalledApp.fromMap(Map<dynamic, dynamic> map) => _InstalledApp(
    '${map['packageName'] ?? ''}',
    '${map['name'] ?? map['packageName'] ?? 'Application'}',
    map['icon'] is Uint8List ? map['icon'] as Uint8List : null,
  );

  final String packageName;
  final String name;
  final Uint8List? icon;
}
