import 'dart:io';
import 'package:material_ui/material_ui.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/controllers/library_controller.dart';
import '../../core/controllers/settings_controller.dart';
import '../../core/storage/progress_sync_service.dart';
import '../../core/theme/effect_mode.dart';
import '../../widgets/surface_panel.dart';
import '../../widgets/window_title_bar.dart';
import '../home/home_controller.dart';
import '../home/home_view.dart';
import '../library/library_models.dart';
import '../library/series_detail_view.dart';
import '../player/playback_session.dart';
import '../player/saphir_player_controller.dart';
import '../player/saphir_player_view.dart';
import 'shell_controller.dart';

class ShellView extends StatefulWidget {
  const ShellView({
    super.key,
    required this.shellController,
    required this.settingsController,
    required this.libraryController,
    required this.homeController,
    required this.playerController,
    required this.syncService,
  });

  final ShellController shellController;
  final SettingsController settingsController;
  final LibraryController libraryController;
  final HomeController homeController;
  final SaphirPlayerController playerController;
  final ProgressSyncService syncService;

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

  String _formatCacheSize(int bytes) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<void> _triggerScan() async {
    await widget.syncService.syncWithStorage(widget.settingsController.nasPath);
    await widget.libraryController.refreshLibrary();
    widget.homeController.refreshHomeFeeds();
  }

  Future<void> _handleSyncNow() async {
    await widget.syncService.syncWithStorage(widget.settingsController.nasPath);
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

  void _handleSaveSettings() {
    widget.settingsController.updateNasPath(_nasInputController.text);
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
          onTriggerScan: _triggerScan,
        );
      case AppSection.library:
        return SurfacePanel(
          effectMode: effectMode,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppStrings.libraryOverviewTitle,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${widget.libraryController.seriesCount} ${AppStrings.seriesCountLabel} · ${widget.libraryController.movieCount} ${AppStrings.moviesCountLabel}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (widget.libraryController.statusMessage.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  widget.libraryController.statusMessage,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              ElevatedButton.icon(
                onPressed:
                    widget.libraryController.isScanning ? null : _triggerScan,
                icon: const Icon(Icons.refresh),
                label: const Text(AppStrings.scanButton),
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
              Material(
                color: Colors.transparent,
                child: SwitchListTile(
                  tileColor: Colors.transparent,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(AppStrings.perDeviceEffectLabel),
                  value: widget.settingsController.perDeviceEffect,
                  onChanged: widget.settingsController.updatePerDeviceEffect,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '${AppStrings.cacheSectionTitle}: ${_formatCacheSize(widget.settingsController.cacheBytes)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  ElevatedButton(
                    onPressed: _handleSaveSettings,
                    child: const Text(AppStrings.saveSettingsButton),
                  ),
                  OutlinedButton.icon(
                    onPressed: _handleSyncNow,
                    icon: const Icon(Icons.sync),
                    label: const Text(AppStrings.syncNowButton),
                  ),
                  OutlinedButton.icon(
                    onPressed: _handleClearCache,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text(AppStrings.clearCacheButton),
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
        );
    }
  }
}
