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
import '../player/playback_session.dart';
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
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _nasInputController = TextEditingController();
    _globalSearchController = TextEditingController();
  }

  @override
  void dispose() {
    _nasInputController.dispose();
    _globalSearchController.dispose();
    super.dispose();
  }

  Future<void> _triggerScan() async {
    await widget.libraryController.syncAndRefreshLibrary();
    widget.homeController.refreshHomeFeeds();
    widget.statsController.refreshStats();
  }

  void _handleGlobalSearchChanged(String query) {
    widget.homeController.updateSearchQuery(query);
    widget.libraryController.updateSearchQuery(query);
    final hasQuery = query.trim().isNotEmpty;
    if (hasQuery &&
        (widget.shellController.selectedSeriesDetail != null ||
            widget.shellController.activeSection == AppSection.settings ||
            widget.shellController.activeSection == AppSection.stats)) {
      widget.shellController.selectSection(AppSection.library);
    }
    setState(() {});
  }

  void _handleClearGlobalSearch() {
    _globalSearchController.clear();
    _handleGlobalSearchChanged('');
  }

  Future<void> _handleSyncNow() async {
    await widget.settingsController.syncProgress();
    widget.homeController.refreshHomeFeeds();
    if (mounted) {
      setState(() {
        _statusMessage = AppStrings.syncCompletedStatus;
      });
    }
  }

  Future<void> _handleClearCache() async {
    await widget.settingsController.clearThumbnailCache();
    widget.homeController.refreshHomeFeeds();
    if (mounted) {
      setState(() {
        _statusMessage = AppStrings.cacheClearedStatus;
      });
    }
  }

  Future<void> _handleAddFolder() async {
    final added = await widget.settingsController
        .pickAndAddFolder(AppStrings.pickFolderDialogTitle);
    if (!mounted || added == null) {
      return;
    }
    setState(() {
      _statusMessage = added
          ? AppStrings.folderAddedStatus
          : AppStrings.folderDuplicateStatus;
    });
  }

  void _handleAddFolderFromInput() {
    final candidate = _nasInputController.text.trim();
    if (candidate.isEmpty) {
      return;
    }
    final added = widget.settingsController.addNasPath(candidate);
    setState(() {
      _statusMessage = added
          ? AppStrings.folderAddedStatus
          : AppStrings.folderDuplicateStatus;
    });
    if (added) {
      _nasInputController.clear();
    }
  }

  Future<void> _handleResetDatabase() async {
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

    await widget.settingsController.resetDatabase();
    widget.libraryController.resetLibraryState();
    widget.homeController.refreshHomeFeeds();
    widget.statsController.refreshStats();
    _nasInputController.clear();
    _globalSearchController.clear();
    widget.homeController.updateSearchQuery('');

    if (mounted) {
      setState(() {
        _statusMessage = AppStrings.databaseResetStatus;
      });
    }
  }

  void _handleRemoveFolder(String path) {
    widget.settingsController.removeNasPath(path);
    setState(() {
      _statusMessage = AppStrings.folderRemovedStatus;
    });
  }

  void _handleSaveSettings() {
    final pendingInput = _nasInputController.text.trim();
    if (pendingInput.isNotEmpty) {
      widget.settingsController.addNasPath(pendingInput);
      _nasInputController.clear();
    }
    widget.settingsController.save();
    setState(() {
      _statusMessage = AppStrings.savedStatus;
    });
    _triggerScan();
  }

  void _openSeriesById(int seriesId) {
    final detail = widget.homeController.loadSeriesDetail(seriesId);
    if (detail != null) {
      widget.shellController.openSeriesDetail(detail);
    }
  }

  Future<void> _launchPlayer(PlaybackSession session) async {
    widget.libraryController.setPlaybackActive(true);
    widget.shellController.openPlaybackSession(session);
    await widget.playerController.startSession(session);
  }

  void _handlePlayerClosed() {
    widget.libraryController.setPlaybackActive(false);
    widget.shellController.closePlaybackSession();
    widget.homeController.refreshHomeFeeds();
    widget.statsController.refreshStats();
    final currentSeries = widget.shellController.selectedSeriesDetail;
    if (currentSeries != null) {
      _openSeriesById(currentSeries.seriesId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.shellController,
        widget.settingsController,
        widget.libraryController,
      ]),
      builder: (context, _) {
        final effectMode = widget.settingsController.effectMode;
        final activeSection = widget.shellController.activeSection;

        if (widget.shellController.isPlayerOpen) {
          return Scaffold(
            body: SaphirPlayerView(
              controller: widget.playerController,
              effectMode: effectMode,
              onClose: _handlePlayerClosed,
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
                onSearchChanged: _handleGlobalSearchChanged,
                onClearSearch: _handleClearGlobalSearch,
              ),
              Expanded(
                child: Row(
                  children: [
                    NavigationSidebar(
                      activeSection: activeSection,
                      onSelectSection: (section) {
                        if (section == AppSection.stats) {
                          widget.statsController.refreshStats();
                        }
                        widget.shellController.selectSection(section);
                      },
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
        detail: seriesDetail,
        effectMode: effectMode,
        onBack: widget.shellController.closeSeriesDetail,
        onPlayEpisode: (ep) => _launchPlayer(
          widget.homeController.buildSessionForEpisode(seriesDetail, ep),
        ),
        onToggleWatched: (ep) {
          widget.homeController.toggleEpisodeWatchedLocal(ep);
          widget.statsController.refreshStats();
          _openSeriesById(seriesDetail.seriesId);
        },
      );
    }

    switch (section) {
      case AppSection.home:
        return HomeView(
          homeController: widget.homeController,
          effectMode: effectMode,
          onSelectItem: (item) =>
              _launchPlayer(widget.homeController.buildSessionForCard(item)),
          onOpenSeries: _openSeriesById,
        );
      case AppSection.library:
        return LibraryView(
          libraryController: widget.libraryController,
          effectMode: effectMode,
          onSelectItem: (item) =>
              _launchPlayer(widget.homeController.buildSessionForCard(item)),
          onOpenSeries: _openSeriesById,
        );
      case AppSection.stats:
        return StatsView(
          statsController: widget.statsController,
          effectMode: effectMode,
        );
      case AppSection.settings:
        return SettingsView(
          settingsController: widget.settingsController,
          libraryController: widget.libraryController,
          nasInputController: _nasInputController,
          effectMode: effectMode,
          statusMessage: _statusMessage,
          onAddFolderFromInput: _handleAddFolderFromInput,
          onAddFolderFromPicker: _handleAddFolder,
          onRemoveFolder: _handleRemoveFolder,
          onTriggerScan: _triggerScan,
          onSaveSettings: _handleSaveSettings,
          onSyncNow: _handleSyncNow,
          onClearCache: _handleClearCache,
          onResetDatabase: _handleResetDatabase,
        );
    }
  }
}
