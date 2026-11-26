import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/controllers/settings_controller.dart';
import '../../core/theme/effect_mode.dart';
import '../../widgets/surface_panel.dart';
import '../../widgets/window_title_bar.dart';
import 'shell_controller.dart';

class ShellView extends StatefulWidget {
  const ShellView({
    super.key,
    required this.shellController,
    required this.settingsController,
  });

  final ShellController shellController;
  final SettingsController settingsController;

  @override
  State<ShellView> createState() => _ShellViewState();
}

class _ShellViewState extends State<ShellView> {
  late final TextEditingController _nasInputController;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _nasInputController = TextEditingController(
      text: widget.settingsController.nasPath,
    );
  }

  @override
  void dispose() {
    _nasInputController.dispose();
    super.dispose();
  }

  void _handleSaveSettings() {
    widget.settingsController.updateNasPath(_nasInputController.text);
    widget.settingsController.save();
    setState(() {
      _statusMessage = AppStrings.savedStatus;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.shellController,
        widget.settingsController,
      ]),
      builder: (context, _) {
        final effectMode = widget.settingsController.effectMode;
        final activeSection = widget.shellController.activeSection;

        return Scaffold(
          body: Column(
            children: [
              WindowTitleBar(shellController: widget.shellController),
              Expanded(
                child: Row(
                  children: [
                    NavigationRail(
                      backgroundColor: AppColors.anthraciteSurface,
                      selectedIndex: activeSection.index,
                      onDestinationSelected: (index) {
                        widget.shellController.selectSection(
                          AppSection.values[index],
                        );
                      },
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.home_outlined),
                          selectedIcon: Icon(
                            Icons.home,
                            color: AppColors.sapphireBright,
                          ),
                          label: Text(AppStrings.homeTab),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.video_library_outlined),
                          selectedIcon: Icon(
                            Icons.video_library,
                            color: AppColors.sapphireBright,
                          ),
                          label: Text(AppStrings.libraryTab),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.settings_outlined),
                          selectedIcon: Icon(
                            Icons.settings,
                            color: AppColors.sapphireBright,
                          ),
                          label: Text(AppStrings.settingsTab),
                        ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: _buildSectionContent(
                          context,
                          activeSection,
                          effectMode,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionContent(
    BuildContext context,
    AppSection section,
    EffectMode effectMode,
  ) {
    switch (section) {
      case AppSection.home:
      case AppSection.library:
        return SurfacePanel(
          effectMode: effectMode,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppStrings.appTitle,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${AppStrings.portableModeLabel}: ${widget.settingsController.dataDirectoryPath}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '${AppStrings.nasPathLabel}: ${widget.settingsController.nasPath.isEmpty ? AppStrings.nasPathHint : widget.settingsController.nasPath}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      case AppSection.settings:
        return SurfacePanel(
          effectMode: effectMode,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppStrings.settingsTab,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _nasInputController,
                decoration: const InputDecoration(
                  labelText: AppStrings.nasPathLabel,
                  hintText: AppStrings.nasPathHint,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                AppStrings.effectModeLabel,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              SegmentedButton<EffectMode>(
                segments: const [
                  ButtonSegment<EffectMode>(
                    value: EffectMode.glass,
                    label: Text(AppStrings.effectGlassLabel),
                  ),
                  ButtonSegment<EffectMode>(
                    value: EffectMode.lean,
                    label: Text(AppStrings.effectLeanLabel),
                  ),
                ],
                selected: {effectMode},
                onSelectionChanged: (selection) {
                  widget.settingsController.updateEffectMode(selection.first);
                },
              ),
              const SizedBox(height: AppSpacing.xs),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(AppStrings.perDeviceEffectLabel),
                value: widget.settingsController.perDeviceEffect,
                onChanged: widget.settingsController.updatePerDeviceEffect,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: _handleSaveSettings,
                    child: const Text(AppStrings.saveSettingsButton),
                  ),
                  if (_statusMessage != null) ...[
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      _statusMessage!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.successGreen,
                          ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
    }
  }
}
