import 'package:material_ui/material_ui.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/controllers/library_controller.dart';
import '../../core/controllers/settings_controller.dart';
import '../../core/theme/effect_mode.dart';
import '../../widgets/window_title_bar.dart';
import '../home/home_controller.dart';
import '../home/home_view.dart';
import '../library/library_view.dart';
import '../library/series_detail_view.dart';
import '../player/saphir_player_controller.dart';
import '../player/saphir_player_view.dart';
import '../stats/stats_controller.dart';
import '../stats/stats_view.dart';
import 'shell_controller.dart';
import 'widgets/navigation_sidebar.dart';
import 'widgets/settings_view.dart';

class ShellView extends StatefulWidget {
  const ShellView({
    super.key,
    required this.shellController,
    required this.settingsController,
    required this.libraryController,
    required this.homeController,
    required this.statsController,
    required this.playerController,
  });

  final ShellController shellController;
  final SettingsController settingsController;
  final LibraryController libraryController;
  final HomeController homeController;
  final StatsController statsController;
  final SaphirPlayerController playerController;

  @override
  State<ShellView> createState() => _ShellViewState();
}

class _ShellViewState extends State<ShellView> {
  late final TextEditingController _nasInputController;
  late final TextEditingController _globalSearchController;

  @override
  void initState() {
    super.initState();
    _nasInputController = TextEditingController();
    _globalSearchController = TextEditingController();
    widget.shellController.attachDependencies(
      settingsController: widget.settingsController,
      libraryController: widget.libraryController,
      homeController: widget.homeController,
      statsController: widget.statsController,
      playerController: widget.playerController,
    );
  }

  @override
  void dispose() {
    widget.shellController.cancelPendingTimers();
    _nasInputController.dispose();
    _globalSearchController.dispose();
    super.dispose();
  }

  void _handleClearGlobalSearch() {
    _globalSearchController.clear();
    widget.shellController.clearGlobalSearchImmediate();
  }

  void _handleAddFolderFromInput() {
    final added = widget.shellController
        .handleAddFolderFromInput(_nasInputController.text);
    if (added) {
      _nasInputController.clear();
    }
  }

  void _handleSaveSettings() {
    final pending = _nasInputController.text;
    widget.shellController.handleSaveSettings(pending);
    if (pending.trim().isNotEmpty) {
      _nasInputController.clear();
    }
  }

  Future<void> _confirmResetDatabase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.anthraciteSurface,
        title: const Text(AppStrings.resetDatabaseConfirmTitle),
        content: const Text(AppStrings.resetDatabaseConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStrings.cancelAction),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.errorRed,
              foregroundColor: AppColors.textPrimary,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(AppStrings.resetDatabaseConfirmAction),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await widget.shellController.handleResetDatabase();
    _nasInputController.clear();
    _globalSearchController.clear();
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

        if (widget.shellController.isPlayerOpen) {
          return Scaffold(
            body: SaphirPlayerView(
              controller: widget.playerController,
              effectMode: effectMode,
              onClose: widget.shellController.handlePlayerClosed,
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.oledBackground,
          body: Column(
            children: [
              WindowTitleBar(
                shellController: widget.shellController,
                searchController: _globalSearchController,
                onSearchChanged: widget.shellController.updateGlobalSearch,
                onClearSearch: _handleClearGlobalSearch,
              ),
              Expanded(
                child: Row(
                  children: [
                    ListenableBuilder(
                      listenable: widget.libraryController,
                      builder: (context, _) => NavigationSidebar(
                        activeSection: activeSection,
                        onSelectSection: widget.shellController.selectSection,
                        isScanning: widget.libraryController.isScanning,
                        isNasOffline:
                            widget.libraryController.statusMessage ==
                                AppStrings.nasOfflineStatus,
                        statusMessage: widget.libraryController.statusMessage,
                      ),
                    ),
                    Expanded(
                      child: _buildSectionContent(activeSection, effectMode),
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

  Widget _buildSectionContent(AppSection section, EffectMode effectMode) {
    final seriesDetail = widget.shellController.selectedSeriesDetail;
    if (seriesDetail != null) {
      return SeriesDetailView(
        key: ValueKey(seriesDetail.seriesId),
        detail: seriesDetail,
        effectMode: effectMode,
        onBack: widget.shellController.closeSeriesDetail,
        onPlayEpisode: (ep) => widget.shellController.launchPlayer(
          widget.homeController.buildSessionForEpisode(seriesDetail, ep),
        ),
        onToggleWatched: widget.shellController.handleToggleWatched,
      );
    }

    switch (section) {
      case AppSection.home:
        return HomeView(
          homeController: widget.homeController,
          effectMode: effectMode,
          onSelectItem: (item) => widget.shellController.launchPlayer(
            widget.homeController.buildSessionForCard(item),
          ),
          onOpenSeries: widget.shellController.openSeriesById,
          onRemoveFromContinueWatching:
              widget.shellController.handleRemoveFromContinueWatching,
        );
      case AppSection.library:
        return LibraryView(
          libraryController: widget.libraryController,
          effectMode: effectMode,
          onSelectItem: (item) => widget.shellController.launchPlayer(
            widget.homeController.buildSessionForCard(item),
          ),
          onOpenSeries: widget.shellController.openSeriesById,
        );
      case AppSection.stats:
        return StatsView(
          statsController: widget.statsController,
          effectMode: effectMode,
        );
      case AppSection.settings:
        return ListenableBuilder(
          listenable: widget.libraryController,
          builder: (context, _) => SettingsView(
            settingsController: widget.settingsController,
            libraryController: widget.libraryController,
            nasInputController: _nasInputController,
            effectMode: effectMode,
            statusMessage: widget.shellController.statusMessage,
            onAddFolderFromInput: _handleAddFolderFromInput,
            onAddFolderFromPicker:
                widget.shellController.handleAddFolderFromPicker,
            onRemoveFolder: widget.shellController.handleRemoveFolder,
            onTriggerScan: widget.shellController.triggerScan,
            onSaveSettings: _handleSaveSettings,
            onSyncNow: widget.shellController.handleSyncNow,
            onClearCache: widget.shellController.handleClearCache,
            onResetDatabase: _confirmResetDatabase,
          ),
        );
    }
  }
}
