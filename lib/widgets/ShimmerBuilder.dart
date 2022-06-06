import 'package:LoliSnatcher/SearchGlobals.dart';
import 'package:LoliSnatcher/SettingsHandler.dart';
import 'package:flutter/material.dart';

class ShiverList extends StatelessWidget {
  const ShiverList({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      linearGradient: _shimmerGradient(
        Color.lerp(Theme.of(context).colorScheme.background, Theme.of(context).colorScheme.onBackground, 0.15)!,
        Color.lerp(Theme.of(context).colorScheme.onBackground, Theme.of(context).colorScheme.background, 0.75)!,
        Color.lerp(Theme.of(context).colorScheme.background, Theme.of(context).colorScheme.onBackground, 0.15)!,
      ),
      child: LayoutBuilder(
        builder: ((BuildContext layoutContext, BoxConstraints constraints) {
          final SearchHandler searchHandler = SearchHandler.instance;
          final SettingsHandler settingsHandler = SettingsHandler.instance;
          final String displayType = settingsHandler.previewDisplay;
          final bool isDesktop = settingsHandler.appMode.value == AppMode.DESKTOP;
          final int previewCount = settingsHandler.limit;
          final int columnCount =
              MediaQuery.of(layoutContext).orientation == Orientation.portrait ? settingsHandler.portraitColumns : settingsHandler.landscapeColumns;

          return GridView(
            physics: const NeverScrollableScrollPhysics(),
            addAutomaticKeepAlives: false,
            cacheExtent: 200,
            shrinkWrap: false,
            padding: EdgeInsets.fromLTRB(2, 2 + (isDesktop ? 0 : (kToolbarHeight + MediaQuery.of(context).padding.top)), 2, 80),
            gridDelegate:
                SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columnCount, childAspectRatio: displayType == 'Square' ? 1 : 9 / 16),
            children: List.generate(
              previewCount,
              (int index) {
                return Card(
                  margin: const EdgeInsets.all(2),
                  child: GridTile(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: const ShimmerCard(),
                    ),
                  ),
                );
              },
            ),
          );
        }),
      ),
    );
  }
}

class ShimmerCard extends StatelessWidget {
  const ShimmerCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      isLoading: true,
      child: Container(
        width: double.maxFinite,
        height: double.maxFinite,
        color: Theme.of(context).colorScheme.surface,
      ),
    );
  }
}

LinearGradient _shimmerGradient(Color c1, Color c2, Color c3) => LinearGradient(
      colors: [c1, c2, c3],
      stops: const [
        0.1,
        0.3,
        0.4,
      ],
      begin: const Alignment(-1.0, -0.3),
      end: const Alignment(1.0, 0.3),
      tileMode: TileMode.clamp,
    );

//>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

class Shimmer extends StatefulWidget {
  static ShimmerState? of(BuildContext context) {
    return context.findAncestorStateOfType<ShimmerState>();
  }

  const Shimmer({
    super.key,
    required this.linearGradient,
    this.child,
  });

  final LinearGradient linearGradient;
  final Widget? child;

  @override
  ShimmerState createState() => ShimmerState();
}

class ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();

    _shimmerController = AnimationController.unbounded(vsync: this)..repeat(min: -0.5, max: 1.5, period: const Duration(milliseconds: 1000));
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  LinearGradient get gradient => LinearGradient(
        colors: widget.linearGradient.colors,
        stops: widget.linearGradient.stops,
        begin: widget.linearGradient.begin,
        end: widget.linearGradient.end,
        transform: _SlidingGradientTransform(slidePercent: _shimmerController.value),
      );

  bool get isSized => (context.findRenderObject() as RenderBox).hasSize;

  Size get size => (context.findRenderObject() as RenderBox).size;

  Offset getDescendantOffset({
    required RenderBox descendant,
    Offset offset = Offset.zero,
  }) {
    final shimmerBox = context.findRenderObject() as RenderBox;
    return descendant.localToGlobal(offset, ancestor: shimmerBox);
  }

  Listenable get shimmerChanges => _shimmerController;

  @override
  Widget build(BuildContext context) {
    return widget.child ?? const SizedBox();
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({
    required this.slidePercent,
  });

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0.0, 0.0);
  }
}

//>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

class ShimmerLoading extends StatefulWidget {
  const ShimmerLoading({
    super.key,
    required this.isLoading,
    required this.child,
  });

  final bool isLoading;
  final Widget child;

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading> {
  Listenable? _shimmerChanges;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shimmerChanges != null) {
      _shimmerChanges!.removeListener(_onShimmerChange);
    }
    _shimmerChanges = Shimmer.of(context)?.shimmerChanges;
    if (_shimmerChanges != null) {
      _shimmerChanges!.addListener(_onShimmerChange);
    }
  }

  @override
  void dispose() {
    _shimmerChanges?.removeListener(_onShimmerChange);
    super.dispose();
  }

  void _onShimmerChange() {
    if (widget.isLoading) {
      setState(() {
        // update the shimmer painting.
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading) {
      return widget.child;
    }

    // Collect ancestor shimmer info.
    final shimmer = Shimmer.of(context)!;
    if (!shimmer.isSized) {
      // The ancestor Shimmer widget has not laid
      // itself out yet. Return an empty box.
      return const SizedBox();
    }
    final shimmerSize = shimmer.size;
    final gradient = shimmer.gradient;
    final offsetWithinShimmer = shimmer.getDescendantOffset(
      descendant: context.findRenderObject() as RenderBox,
    );

    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) {
        return gradient.createShader(
          Rect.fromLTWH(
            -offsetWithinShimmer.dx,
            -offsetWithinShimmer.dy,
            shimmerSize.width,
            shimmerSize.height,
          ),
        );
      },
      child: widget.child,
    );
  }
}
