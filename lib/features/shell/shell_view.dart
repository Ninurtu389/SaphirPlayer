import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/controllers/library_controller.dart';
import '../../core/controllers/settings_controller.dart';
import '../../core/storage/progress_sync_service.dart';
import '../../core/theme/effect_mode.dart';
import '../../widgets/window_title_bar.dart';
import '../home/home_controller.dart';
import '../home/home_view.dart';
import '../library/library_models.dart';
import '../library/library_view.dart';
import '../library/series_detail_view.dart';
import '../player/playback_session.dart';
import '../player/saphir_player_controller.dart';
import '../player/saphir_player_view.dart';
import '../stats/stats_controller.dart';
import '../stats/stats_view.dart';
import 'shell_controller.dart';

class ShellView extends StatefulWidget {
  const ShellView({
    super.key,
    required this.shellController,
    required this.settingsController,
    required this.libraryController,
    required this.homeController,
    required this.statsController,
    required this.playerController,
    required this.syncService,
  });

  final ShellController shellController;
  final SettingsController settingsController;
  final LibraryController libraryController;
  final HomeController homeController;
  final StatsController statsController;
  final SaphirPlayerController playerController;
  final ProgressSyncService syncService;

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

  String _formatCacheSize(int bytes) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<void> _triggerScan() async {
    await widget.syncService.syncWithRoots(widget.settingsController.nasPaths);
    await widget.libraryController.refreshLibrary();
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
    await widget.syncService.syncWithRoots(widget.settingsController.nasPaths);
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
    final selectedUri = await FilePicker.pickDirectory(
      dialogTitle: AppStrings.pickFolderDialogTitle,
    );
    if (!mounted || selectedUri == null) {
      return;
    }
    final selectedDirectory = selectedUri.isScheme('file')
        ? selectedUri.toFilePath(windows: Platform.isWindows)
        : selectedUri.toString();
    if (selectedDirectory.trim().isEmpty) {
      return;
    }
    _addFolderPath(selectedDirectory);
  }

  void _handleAddFolderFromInput() {
    final candidate = _nasInputController.text.trim();
    if (candidate.isEmpty) {
      return;
    }
    if (_addFolderPath(candidate)) {
      _nasInputController.clear();
    }
  }

  bool _addFolderPath(String path) {
    final added = widget.settingsController.addNasPath(path);
    setState(() {
      _statusMessage = added
          ? AppStrings.folderAddedStatus
          : AppStrings.folderDuplicateStatus;
    });
    return added;
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

  Future<void> _playFromCardItem(MediaCardItem item) async {
    if (item.seriesId != null) {
      final detail = widget.homeController.loadSeriesDetail(item.seriesId!);
      if (detail != null) {
        final flatEpisodes = <EpisodeEntry>[];
        for (final season in detail.seasons) {
          flatEpisodes.addAll(season.episodes);
        }
        if (flatEpisodes.isNotEmpty) {
          final targetIdx =
              flatEpisodes.indexWhere((e) => e.filePath == item.filePath);
          final resolvedIdx = targetIdx >= 0 ? targetIdx : 0;
          await _startEpisodeQueue(detail.title, flatEpisodes, resolvedIdx);
          return;
        }
      }
    }

    final session = PlaybackSession(
      queue: [
        PlaybackQueueEntry(
          mediaKey: item.mediaKey,
          mediaType: item.mediaType,
          title: item.title,
          subtitle: item.subtitle,
          filePath: item.filePath,
          seriesId: item.seriesId,
          startPositionMs: 0,
        ),
      ],
      initialIndex: 0,
    );
    await _launchPlayer(session);
  }

  Future<void> _playEpisodeFromDetail(
    SeriesDetailData detail,
    EpisodeEntry selectedEpisode,
  ) async {
    final flatEpisodes = <EpisodeEntry>[];
    for (final season in detail.seasons) {
      flatEpisodes.addAll(season.episodes);
    }
    final index = flatEpisodes.indexWhere((e) => e.id == selectedEpisode.id);
    await _startEpisodeQueue(
        detail.title, flatEpisodes, index >= 0 ? index : 0);
  }

  Future<void> _startEpisodeQueue(
    String seriesTitle,
    List<EpisodeEntry> episodes,
    int startIndex,
  ) async {
    final queue = episodes
        .map(
          (ep) => PlaybackQueueEntry(
            mediaKey: 'episode_${ep.id}',
            mediaType: 'episode',
            title: seriesTitle,
            subtitle: 'S${ep.seasonNumber}E${ep.episodeNumber} · ${ep.title}',
            filePath: ep.filePath,
            seriesId: ep.seriesId,
            startPositionMs: ep.isCompleted ? 0 : ep.positionMs,
          ),
        )
        .toList();

    await _launchPlayer(
      PlaybackSession(
        queue: queue,
        initialIndex: startIndex,
      ),
    );
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
                    _NavigationSidebar(
                      activeSection: activeSection,
                      onSelectSection: (section) {
                        if (section == AppSection.stats) {
                          widget.statsController.refreshStats();
                        }
                        widget.shellController.selectSection(section);
                      },
                    ),
                    Expanded(
                      child: _buildSectionContent(
                        context,
                        activeSection,
                        effectMode,
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
    final seriesDetail = widget.shellController.selectedSeriesDetail;
    if (seriesDetail != null) {
      return SeriesDetailView(
        detail: seriesDetail,
        effectMode: effectMode,
        onBack: widget.shellController.closeSeriesDetail,
        onPlayEpisode: (ep) => _playEpisodeFromDetail(seriesDetail, ep),
        onToggleWatched: (ep) {
          widget.homeController
              .toggleEpisodeWatched(ep, Platform.localHostname);
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
          onSelectItem: _playFromCardItem,
          onOpenSeries: _openSeriesById,
        );
      case AppSection.library:
        return LibraryView(
          libraryController: widget.libraryController,
          effectMode: effectMode,
          onSelectItem: _playFromCardItem,
          onOpenSeries: _openSeriesById,
        );
      case AppSection.stats:
        return StatsView(
          statsController: widget.statsController,
          effectMode: effectMode,
        );
      case AppSection.settings:
        return _buildSettingsView(context, effectMode);
    }
  }

  Widget _buildSettingsView(BuildContext context, EffectMode effectMode) {
    final folders = widget.settingsController.nasPaths;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSpacing.maxSettingsWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.settingsTab,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              _SettingsSectionCard(
                title: AppStrings.settingsMediaSectionTitle,
                description: AppStrings.settingsMediaSectionDesc,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _nasInputController,
                            onSubmitted: (_) => _handleAddFolderFromInput(),
                            decoration: const InputDecoration(
                              labelText: AppStrings.nasPathLabel,
                              hintText: AppStrings.nasPathHint,
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        ElevatedButton.icon(
                          onPressed: _handleAddFolder,
                          icon: const Icon(
                            Icons.create_new_folder_outlined,
                            size: AppSpacing.iconSizeMd,
                          ),
                          label: const Text(AppStrings.addFolderButton),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (folders.isEmpty)
                      Text(
                        AppStrings.noFoldersConfigured,
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: folders.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: AppSpacing.xs),
                        itemBuilder: (context, index) {
                          final folderPath = folders[index];
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.elevatedSurface,
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusSm),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.folder_outlined,
                                  color: AppColors.sapphireBright,
                                  size: AppSpacing.iconSizeMd,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    folderPath,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ),
                                IconButton(
                                  tooltip: AppStrings.removeFolderTooltip,
                                  onPressed: () =>
                                      _handleRemoveFolder(folderPath),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: AppSpacing.iconSizeMd,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: widget.libraryController.isScanning
                              ? null
                              : _triggerScan,
                          icon: const Icon(
                            Icons.refresh,
                            size: AppSpacing.iconSizeMd,
                          ),
                          label: const Text(AppStrings.scanButton),
                        ),
                        if (widget.libraryController.statusMessage.isNotEmpty) ...[
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              widget.libraryController.statusMessage,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _SettingsSectionCard(
                title: AppStrings.settingsAppearanceSectionTitle,
                description: AppStrings.settingsAppearanceSectionDesc,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                        widget.settingsController
                            .updateEffectMode(selection.first);
                      },
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      effectMode == EffectMode.glass
                          ? AppStrings.settingsEffectGlassDesc
                          : AppStrings.settingsEffectLeanDesc,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Divider(height: AppSpacing.dividerThickness),
                    const SizedBox(height: AppSpacing.xs),
                    Material(
                      color: Colors.transparent,
                      child: SwitchListTile(
                        tileColor: Colors.transparent,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(AppStrings.perDeviceEffectLabel),
                        subtitle: Text(
                          AppStrings.settingsPerDeviceDesc,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        value: widget.settingsController.perDeviceEffect,
                        onChanged:
                            widget.settingsController.updatePerDeviceEffect,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _SettingsSectionCard(
                title: AppStrings.settingsSyncSectionTitle,
                description: AppStrings.settingsSyncSectionDesc,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${AppStrings.cacheSectionTitle}: ${_formatCacheSize(widget.settingsController.cacheBytes)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _handleSaveSettings,
                          icon: const Icon(
                            Icons.save_outlined,
                            size: AppSpacing.iconSizeMd,
                          ),
                          label: const Text(AppStrings.saveSettingsButton),
                        ),
                        OutlinedButton.icon(
                          onPressed: _handleSyncNow,
                          icon: const Icon(
                            Icons.sync,
                            size: AppSpacing.iconSizeMd,
                          ),
                          label: const Text(AppStrings.syncNowButton),
                        ),
                        OutlinedButton.icon(
                          onPressed: _handleClearCache,
                          icon: const Icon(
                            Icons.delete_outline,
                            size: AppSpacing.iconSizeMd,
                          ),
                          label: const Text(AppStrings.clearCacheButton),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.errorRed,
                            side: const BorderSide(color: AppColors.errorRed),
                          ),
                          onPressed: _handleResetDatabase,
                          icon: const Icon(
                            Icons.delete_forever_outlined,
                            size: AppSpacing.iconSizeMd,
                          ),
                          label: const Text(AppStrings.resetDatabaseButton),
                        ),
                      ],
                    ),
                    if (_statusMessage != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _statusMessage!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.successGreen,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationSidebar extends StatelessWidget {
  const _NavigationSidebar({
    required this.activeSection,
    required this.onSelectSection,
  });

  final AppSection activeSection;
  final ValueChanged<AppSection> onSelectSection;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.navRailWidth,
      color: AppColors.anthraciteSurface,
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.md),
          _NavRailItem(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
            label: AppStrings.homeTab,
            selected: activeSection == AppSection.home,
            onTap: () => onSelectSection(AppSection.home),
          ),
          const SizedBox(height: AppSpacing.xs),
          _NavRailItem(
            icon: Icons.video_library_outlined,
            selectedIcon: Icons.video_library,
            label: AppStrings.libraryTab,
            selected: activeSection == AppSection.library,
            onTap: () => onSelectSection(AppSection.library),
          ),
          const SizedBox(height: AppSpacing.xs),
          _NavRailItem(
            icon: Icons.bar_chart_outlined,
            selectedIcon: Icons.bar_chart,
            label: AppStrings.statsTab,
            selected: activeSection == AppSection.stats,
            onTap: () => onSelectSection(AppSection.stats),
          ),
          const Spacer(),
          _NavRailItem(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            label: AppStrings.settingsTab,
            selected: activeSection == AppSection.settings,
            onTap: () => onSelectSection(AppSection.settings),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _NavRailItem extends StatefulWidget {
  const _NavRailItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavRailItem> createState() => _NavRailItemState();
}

class _NavRailItemState extends State<_NavRailItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.selected;
    final foregroundColor = isSelected
        ? AppColors.sapphireBright
        : (_isHovered ? AppColors.textPrimary : AppColors.textSecondary);
    final backgroundColor = isSelected
        ? AppColors.elevatedSurface
        : (_isHovered ? AppColors.surfaceHover : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Container(
            height: AppSpacing.navItemHeight,
            color: backgroundColor,
            child: Row(
              children: [
                Container(
                  width: AppSpacing.navIndicatorWidth,
                  height: AppSpacing.navIndicatorHeight,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.sapphireBright
                        : AppColors.borderTransparent,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(AppSpacing.xxs),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isSelected ? widget.selectedIcon : widget.icon,
                        color: foregroundColor,
                        size: AppSpacing.iconSizeMd,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: foregroundColor,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.anthraciteSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}
