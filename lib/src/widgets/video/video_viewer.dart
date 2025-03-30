import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:chewie/chewie.dart';
import 'package:dio/dio.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/local_auth_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/services/dio_downloader.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/media_loading.dart';
import 'package:lolisnatcher/src/widgets/common/transparent_pointer.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail.dart';
import 'package:lolisnatcher/src/widgets/video/loli_controls.dart';

// TODO remove setState use

class VideoViewer extends StatefulWidget {
  const VideoViewer(
    this.booruItem, {
    this.enableFullscreen = true,
    this.isStandalone = false,
    this.customBooru,
    super.key,
  });

  final BooruItem booruItem;
  final bool enableFullscreen;
  final bool isStandalone;
  final Booru? customBooru;

  @override
  State<VideoViewer> createState() => VideoViewerState();
}

class VideoViewerState extends State<VideoViewer> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;
  final ViewerHandler viewerHandler = ViewerHandler.instance;
  final LocalAuthHandler localAuthHandler = LocalAuthHandler.instance;

  PhotoViewScaleStateController scaleController = PhotoViewScaleStateController();
  PhotoViewController viewController = PhotoViewController();
  final ValueNotifier<VideoPlayerController?> videoController = ValueNotifier(null);
  final ValueNotifier<ChewieController?> chewieController = ValueNotifier(null);

  final ValueNotifier<int> total = ValueNotifier(0), received = ValueNotifier(0), startedAt = ValueNotifier(0);
  int lastViewedIndex = -1;
  int isTooBig = 0; // 0 = not too big, 1 = too big, 2 = too big, but allow downloading
  final ValueNotifier<bool> isFromCache = ValueNotifier(false),
      isStopped = ValueNotifier(false),
      isViewed = ValueNotifier(false),
      isZoomed = ValueNotifier(false),
      didAutoplay = ValueNotifier(false),
      forceCache = ValueNotifier(false);
  final ValueNotifier<List<String>> stopReason = ValueNotifier([]);
  Timer? bufferingTimer, pauseCheckTimer;

  CancelToken? cancelToken, sizeCancelToken;
  DioDownloader? client, sizeClient;
  File? video;

  bool get isVideoInited => videoController.value?.value.isInitialized ?? false;

  @override
  void didUpdateWidget(VideoViewer oldWidget) {
    // force redraw on item data change
    if (oldWidget.booruItem != widget.booruItem) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        killLoading([]);
        initVideo(false);
        updateState();
      });
    }
    super.didUpdateWidget(oldWidget);
  }

  Future<void> downloadVideo() async {
    isStopped.value = false;
    startedAt.value = DateTime.now().millisecondsSinceEpoch;

    unawaited(getSize());

    if (!settingsHandler.mediaCache) {
      // Media caching disabled - don't cache videos
      unawaited(initPlayer());
      return;
    }

    final usedVideoCacheMode = forceCache.value ? 'Cache' : settingsHandler.videoCacheMode;

    switch (usedVideoCacheMode) {
      case 'Cache':
        // Cache to device from custom request
        break;

      // Load and stream from default player network request, cache to device from custom request
      // TODO: change video handler to allow viewing and caching from single network request
      case 'Stream+Cache':
        unawaited(initPlayer());
        break;

      // Only stream, notice the return
      case 'Stream':
      default:
        unawaited(initPlayer());
        return;
    }

    cancelToken = CancelToken();
    client = DioDownloader(
      widget.booruItem.fileURL,
      headers: await Tools.getFileCustomHeaders(
        widget.isStandalone ? widget.customBooru : searchHandler.currentBooru,
        checkForReferer: true,
      ),
      cancelToken: cancelToken,
      onProgress: onBytesAdded,
      onEvent: onEvent,
      onError: onError,
      onDoneFile: (File file) async {
        video = file;
        // save video from cache, but restate only if player is not initialized yet
        if (!isVideoInited) {
          unawaited(initPlayer());
          updateState();
        }
      },
      cacheEnabled: settingsHandler.mediaCache,
      cacheFolder: 'media',
      fileNameExtras: widget.booruItem.fileNameExtras,
    );
    unawaited(client!.runRequest());
    return;
  }

  Future<void> getSize() async {
    sizeCancelToken = CancelToken();
    sizeClient = DioDownloader(
      widget.booruItem.fileURL,
      headers: await Tools.getFileCustomHeaders(
        widget.isStandalone ? widget.customBooru : searchHandler.currentBooru,
        checkForReferer: true,
      ),
      cancelToken: sizeCancelToken,
      onEvent: onEvent,
      fileNameExtras: widget.booruItem.fileNameExtras,
    );
    unawaited(sizeClient!.runRequestSize());
    return;
  }

  void onSize(int size) {
    total.value = size;
    // TODO find a way to stop loading based on size when caching is enabled

    final int? maxSize = settingsHandler.preloadSizeLimit == 0 ? null : (1024 * 1024 * settingsHandler.preloadSizeLimit * 1000).round();
    // print('onSize: $size $maxSize ${size > maxSize}');
    if (size == 0) {
      killLoading(['File is zero bytes']);
    } else if (maxSize != null && (size > maxSize) && isTooBig != 2) {
      // TODO add check if resolution is too big
      isTooBig = 1;
      killLoading([
        'File is too big',
        'File size: ${Tools.formatBytes(size, 2)}',
        'Limit: ${Tools.formatBytes(maxSize, 2, withTrailingZeroes: false)}',
      ]);
    }

    if (size > 0 && widget.booruItem.fileSize == null) {
      // set item file size if it wasn't received from api
      widget.booruItem.fileSize = size;
    }
  }

  void onBytesAdded(int receivedNew, int totalNew) {
    received.value = receivedNew;
    total.value = totalNew;
    onSize(totalNew);
  }

  void onEvent(String event, dynamic data) {
    switch (event) {
      case 'loaded':
        //
        break;
      case 'size':
        onSize(data as int);
        break;
      case 'isFromCache':
        isFromCache.value = true;
        break;
      case 'isFromNetwork':
        isFromCache.value = false;
        break;
      default:
        break;
    }
    updateState();
  }

  void onError(Exception error) {
    //// Error handling
    if (error is DioException && CancelToken.isCancel(error)) {
      // print('Canceled by user: $imageURL | $error');
    } else {
      if (error is DioException) {
        killLoading([
          'Loading Error: ${error.type.name}',
          if (error.response?.statusCode != null) '${error.response?.statusCode} - ${error.response?.statusMessage}',
        ]);
      } else {
        killLoading([
          'Loading Error: $error',
          if (settingsHandler.videoBackendMode.isNormal) ...[
            '',
            'Try changing "Video player backend" in Settings->Video if you encounter playback issues often',
          ],
        ]);
      }
      // print('Dio request cancelled: $error');
    }
  }

  @override
  void initState() {
    super.initState();
    viewerHandler.addViewed(widget.key);

    viewController.outputStateStream.listen(onViewStateChanged);
    scaleController.outputScaleStateStream.listen(onScaleStateChanged);

    isViewed.value = widget.isStandalone ||
        (settingsHandler.appMode.value.isMobile
            ? searchHandler.viewedIndex.value == searchHandler.getItemIndex(widget.booruItem)
            : searchHandler.viewedItem.value.fileURL == widget.booruItem.fileURL);
    searchHandler.viewedIndex.addListener(indexListener);

    initVideo(false);
  }

  void updateState() {
    if (mounted) {
      setState(() {});
    }
  }

  void indexListener() {
    final bool prevViewed = isViewed.value;
    final bool isCurrentIndex = widget.isStandalone || searchHandler.viewedIndex.value == searchHandler.getItemIndex(widget.booruItem);
    final bool isCurrentItem = widget.isStandalone || searchHandler.viewedItem.value.fileURL == widget.booruItem.fileURL;
    if (settingsHandler.appMode.value.isMobile ? isCurrentIndex : isCurrentItem) {
      isViewed.value = true;
    } else {
      didAutoplay.value = false;
      isViewed.value = false;
    }

    if (prevViewed != isViewed.value) {
      if (!isViewed.value) {
        // reset zoom if not viewed
        resetZoom();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        updateState();
      });
    }
  }

  void initVideo(bool ignoreTagsCheck) {
    if (widget.booruItem.isHated && !ignoreTagsCheck) {
      final tagsData = settingsHandler.parseTagsList(widget.booruItem.tagsList, isCapped: true);
      killLoading(['Contains Hated tags:', ...tagsData.hatedTags]);
    } else {
      downloadVideo();
    }
  }

  void killLoading(List<String> reason) {
    disposables();

    bufferingTimer?.cancel();
    pauseCheckTimer?.cancel();

    total.value = 0;
    received.value = 0;
    startedAt.value = 0;

    isFromCache.value = false;
    isStopped.value = true;
    stopReason.value = reason;

    viewerHandler.setLoaded(widget.key, false);

    resetZoom();

    video = null;

    updateState();
  }

  @override
  void dispose() {
    disposables();

    bufferingTimer?.cancel();
    pauseCheckTimer?.cancel();

    searchHandler.viewedIndex.removeListener(indexListener);

    viewerHandler.removeViewed(widget.key);

    super.dispose();
  }

  void disposeClient() {
    client?.dispose();
    client = null;
    sizeClient?.dispose();
    sizeClient = null;
  }

  void disposables() {
    videoController.value?.setVolume(0);
    videoController.value?.pause();
    videoController.value?.removeListener(updateVideoState);
    videoController.value?.dispose();
    chewieController.value?.dispose();
    videoController.value = null;
    chewieController.value = null;

    if (!(cancelToken != null && cancelToken!.isCancelled)) {
      cancelToken?.cancel();
    }
    if (!(sizeCancelToken != null && sizeCancelToken!.isCancelled)) {
      sizeCancelToken?.cancel();
    }

    disposeClient();
  }

  // debug functions
  void onScaleStateChanged(PhotoViewScaleState scaleState) {
    // print(scaleState);

    final bool prevIsZoomed = isZoomed.value;

    isZoomed.value = scaleState == PhotoViewScaleState.zoomedIn || scaleState == PhotoViewScaleState.covering || scaleState == PhotoViewScaleState.originalSize;
    viewerHandler.setZoomed(widget.key, isZoomed.value);
    if (prevIsZoomed != isZoomed.value) {
      updateState();
    }
  }

  void onViewStateChanged(PhotoViewControllerValue viewState) {
    // print(viewState);
    viewerHandler.setViewValue(widget.key, viewState);
  }

  void resetZoom() {
    if (!isVideoInited) return;
    scaleController.scaleState = PhotoViewScaleState.initial;
    viewerHandler.setZoomed(widget.key, false);
  }

  void scrollZoomImage(double value) {
    final double upperLimit = min(8, (viewController.scale ?? 1) + (value / 200));
    // zoom on which image fits to container can be less than limit
    // therefore don't clump the value to lower limit if we are zooming in to avoid unnecessary zoom jumps
    final double lowerLimit = value > 0 ? upperLimit : max(0.75, upperLimit);

    // print('ll $lowerLimit $value');
    // if zooming out and zoom is smaller than limit - reset to container size
    // TODO minimal scale to fit can be different from limit
    if (lowerLimit == 0.75 && value < 0) {
      scaleController.scaleState = PhotoViewScaleState.initial;
    } else {
      viewController.scale = lowerLimit;
    }
  }

  void doubleTapZoom() {
    if (!isVideoInited) return;
    // viewController.scale = 2;
    // viewController.updateMultiple(scale: 2);
    scaleController.scaleState = PhotoViewScaleState.covering;
  }

  void updateVideoState() {
    // print(videoController?.value);

    if (chewieController.value == null) return;

    if (isVideoInited) {
      bufferingTimer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        viewerHandler.setLoaded(widget.key, true);
      });
    }

    if (viewerHandler.isFullscreen.value != chewieController.value!.isFullScreen) {
      // redisable sleep when changing fullscreen state
      ServiceHandler.disableSleep();

      // Reset systemui visibility
      if (!chewieController.value!.isFullScreen) {
        ServiceHandler.setSystemUiVisibility(viewerHandler.displayAppbar.value);
      }

      // save fullscreen state only when it changed
      viewerHandler.isFullscreen.value = chewieController.value!.isFullScreen;
    }

    if (widget.isStandalone || searchHandler.viewedIndex.value == searchHandler.getItemIndex(widget.booruItem)) {
      if (chewieController.value!.isFullScreen || !settingsHandler.useVolumeButtonsForScroll) {
        ServiceHandler.setVolumeButtons(true); // in full screen or volumebuttons scroll setting is disabled
      } else {
        ServiceHandler.setVolumeButtons(viewerHandler.displayAppbar.value); // same as app bar value
      }
    }

    if (!isStopped.value && videoController.value?.value.hasError == true) {
      killLoading(['Video Error:', videoController.value!.value.errorDescription ?? '']);
    }
  }

  Future<void> initPlayer() async {
    if (video != null) {
      // Start from cache if was already cached or only caching is allowed
      videoController.value = VideoPlayerController.file(
        video!,
        videoPlayerOptions: Platform.isAndroid ? VideoPlayerOptions(mixWithOthers: true) : null,
      );
    } else {
      // Otherwise load from network
      videoController.value = VideoPlayerController.networkUrl(
        Uri.parse(widget.booruItem.fileURL),
        videoPlayerOptions: Platform.isAndroid ? VideoPlayerOptions(mixWithOthers: true) : null,
        httpHeaders: await Tools.getFileCustomHeaders(
          widget.isStandalone ? widget.customBooru : searchHandler.currentBooru,
          checkForReferer: true,
        ),
      );
    }
    // mixWithOthers: true, allows to not interrupt audio sources from other apps
    videoController.value!.addListener(updateVideoState);

    final Color accentColor = Theme.of(context).colorScheme.secondary;
    final Color darkenedAceentColor = Color.lerp(accentColor, Colors.black, 0.5)!;

    // Player wrapper to allow controls, looping...
    chewieController.value = ChewieController(
      videoPlayerController: videoController.value!,
      // autoplay is disabled here, because videos started playing randomly, but videos will still autoplay when in view (see isViewed check later)
      autoPlay: false,
      allowedScreenSleep: false,
      looping: true,
      allowFullScreen: widget.enableFullscreen,
      showControls: false,
      showControlsOnInitialize: viewerHandler.displayAppbar.value,
      // customControls: SafeArea(child: LoliControls()),
      // MaterialControls(),
      // CupertinoControls(
      //   backgroundColor: Color.fromRGBO(41, 41, 41, 0.7),
      //   iconColor: Color.fromARGB(255, 200, 200, 200)
      // ),
      playbackSpeeds: const [
        0.1,
        0.25,
        0.5,
        0.75,
        1,
        1.25,
        1.5,
        1.75,
        2,
        3,
        4,
        6,
        8,
        12,
        16,
        32,
      ],
      materialProgressColors: ChewieProgressColors(
        playedColor: accentColor,
        handleColor: darkenedAceentColor,
        backgroundColor: Colors.grey,
        bufferedColor: Colors.white.withValues(alpha: 0.66),
      ),
      systemOverlaysOnEnterFullScreen: [],
      systemOverlaysAfterFullScreen: SystemUiOverlay.values,
      errorBuilder: (context, errorMessage) {
        onError(Exception(errorMessage));

        return Center(
          child: Text(errorMessage, style: const TextStyle(color: Colors.white)),
        );
      },

      routePageBuilder: fullscreenRoutePageBuilder,

      // Specify this to allow any orientation in fullscreen, otherwise it will decide for itself based on video dimensions
      // deviceOrientationsOnEnterFullScreen: [
      //     DeviceOrientation.landscapeLeft,
      //     DeviceOrientation.landscapeRight,
      //     DeviceOrientation.portraitUp,
      //     DeviceOrientation.portraitDown,
      // ],
    );

    if (settingsHandler.startVideosMuted) {
      await chewieController.value!.setVolume(0);
    }

    if (!forceCache.value) {
      bufferingTimer?.cancel();
      bufferingTimer = Timer(
        const Duration(seconds: 10),
        () {
          // force restart with cache mode, but only if file size isn't loaded yet or it's small enough (<25mb) (big videos may take a while to buffer)
          const int maxForceCacheSize = 1024 * 1024 * 25;
          if (!isVideoInited && (total.value == 0 || total.value < maxForceCacheSize)) {
            forceCache.value = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              killLoading([]);
              initVideo(false);
              updateState();
            });
          }
        },
      );
    }

    await Future.wait([videoController.value!.initialize()]);

    forceCache.value = false;

    // Ensure the first frame is shown after the video is initialized, even before the play button has been pressed.
    updateState();
  }

  Future<void> pauseOnAppLock() async {
    pauseCheckTimer?.cancel();
    await videoController.value?.pause();
    if (videoController.value?.value.isPlaying == false) {
      return;
    }
    pauseCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (videoController.value?.value.isPlaying == true) {
        await videoController.value?.pause();
        if (videoController.value?.value.isPlaying == false) {
          pauseCheckTimer?.cancel();
        }
      }
    });
  }

  AnimatedWidget fullscreenRoutePageBuilder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    ChewieControllerProvider controllerProvider,
  ) {
    resetZoom();

    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        return child!;
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Container(
          alignment: Alignment.center,
          color: Colors.black,
          child: Stack(
            children: [
              controllerProvider,
              ChewieControllerProvider(
                controller: chewieController.value!,
                child: TransparentPointer(
                  child: SafeArea(
                    child: LoliControls(
                      useLongTapFastForward: settingsHandler.longTapFastForwardVideo,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // print('!!! Build video mobile ${widget.index}!!!');

    // protects from video restart when something forces restate here while video is active (example: favoriting from appbar)
    final int viewedIndex = widget.isStandalone ? 0 : searchHandler.viewedIndex.value;
    final bool needsRestart = lastViewedIndex != viewedIndex;

    if (isVideoInited) {
      if (isViewed.value) {
        // Reset video time if came into view
        if (needsRestart) {
          videoController.value!.seekTo(Duration.zero);
        }
        if (!didAutoplay.value) {
          if (settingsHandler.autoPlayEnabled) {
            // autoplay if viewed and setting is enabled
            videoController.value!.play();
          }
          didAutoplay.value = true;
        }
        if (viewerHandler.videoAutoMute) {
          videoController.value!.setVolume(0);
        }
      } else {
        videoController.value!.pause();
      }
    }

    if (needsRestart) {
      lastViewedIndex = viewedIndex;
    }

    final double aspectRatio = videoController.value?.value.aspectRatio ?? 16 / 9;
    final screenSize = MediaQuery.sizeOf(context);
    final double screenRatio = screenSize.width / screenSize.height;
    final Size childSize = Size(
      aspectRatio > screenRatio ? screenSize.width : screenSize.height * aspectRatio,
      aspectRatio < screenRatio ? screenSize.height : screenSize.width / aspectRatio,
    );

    return Hero(
      tag: 'imageHero${isViewed.value ? '' : '-ignore-'}${widget.booruItem.hashCode}',
      child: Material(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isVideoInited
                  ? const SizedBox.shrink()
                  : Thumbnail(
                      item: widget.booruItem,
                    ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isVideoInited
                  ? const SizedBox.shrink()
                  : MediaLoading(
                      item: widget.booruItem,
                      hasProgress: settingsHandler.mediaCache && (forceCache.value || settingsHandler.videoCacheMode != 'Stream'),
                      isFromCache: isFromCache.value,
                      isDone: isVideoInited,
                      isTooBig: isTooBig > 0,
                      isStopped: isStopped.value,
                      stopReasons: stopReason.value,
                      isViewed: isViewed.value,
                      total: total,
                      received: received,
                      startedAt: startedAt,
                      startAction: () {
                        if (isTooBig == 1) {
                          isTooBig = 2;
                        }
                        initVideo(true);
                        updateState();
                      },
                      stopAction: () {
                        killLoading(['Stopped by User']);
                      },
                    ),
            ),
            //
            AnimatedSwitcher(
              duration: Duration(milliseconds: settingsHandler.appMode.value.isDesktop ? 50 : 200),
              child: isVideoInited
                  ? Listener(
                      onPointerSignal: (pointerSignal) {
                        if (pointerSignal is PointerScrollEvent) {
                          scrollZoomImage(pointerSignal.scrollDelta.dy);
                        }
                      },
                      child: Stack(
                        children: [
                          ImageFiltered(
                            enabled: settingsHandler.blurImages,
                            imageFilter: ImageFilter.blur(
                              sigmaX: 30,
                              sigmaY: 30,
                              tileMode: TileMode.decal,
                            ),
                            child: PhotoView.customChild(
                              childSize: childSize,
                              customSize: Size(
                                MediaQuery.sizeOf(context).width,
                                MediaQuery.sizeOf(context).height,
                              ),
                              minScale: PhotoViewComputedScale.contained,
                              maxScale: PhotoViewComputedScale.covered * 8,
                              initialScale: PhotoViewComputedScale.contained,
                              basePosition: Alignment.center,
                              controller: viewController,
                              scaleStateController: scaleController,
                              enableRotation: settingsHandler.allowRotation,
                              child: ValueListenableBuilder(
                                valueListenable: localAuthHandler.isAuthenticated,
                                builder: (context, isAuthenticated, child) {
                                  if (isAuthenticated != false) {
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      pauseCheckTimer?.cancel();
                                    });

                                    return child!;
                                  } else {
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      pauseOnAppLock();
                                    });

                                    return const Center(child: CircularProgressIndicator());
                                  }
                                },
                                child: Chewie(controller: chewieController.value!),
                              ),
                            ),
                          ),
                          ChewieControllerProvider(
                            controller: chewieController.value!,
                            child: TransparentPointer(
                              child: SafeArea(
                                child: ValueListenableBuilder(
                                  valueListenable: localAuthHandler.isAuthenticated,
                                  builder: (context, isAuthenticated, child) {
                                    if (isAuthenticated != false) {
                                      return child!;
                                    }

                                    return const SizedBox.shrink();
                                  },
                                  child: LoliControls(
                                    useLongTapFastForward: !isZoomed.value && settingsHandler.longTapFastForwardVideo,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
