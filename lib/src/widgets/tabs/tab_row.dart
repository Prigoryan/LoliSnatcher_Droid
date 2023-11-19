import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/widgets/common/marquee_text.dart';
import 'package:lolisnatcher/src/widgets/image/favicon.dart';

class TabRow extends StatelessWidget {
  const TabRow({
    required this.tab,
    this.color,
    this.fontWeight,
    this.withFavicon = true,
    this.withColoredTags = true,
    this.filterText,
    super.key,
  });

  final SearchTab tab;
  final Color? color;
  final FontWeight? fontWeight;
  final bool withFavicon;
  final bool withColoredTags;
  final String? filterText;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // print(tab.tags);
      final String rawTagsStr = tab.tags;
      final String tagText = (rawTagsStr.trim().isEmpty ? '[No Tags]' : rawTagsStr).trim();

      final bool hasItems = tab.booruHandler.filteredFetched.isNotEmpty;
      final bool isNotEmptyBooru = tab.selectedBooru.value.faviconURL != null;

      Widget marquee = MarqueeText(
        key: ValueKey(tagText),
        text: tagText,
        style: TextStyle(
          fontSize: 16,
          fontStyle: hasItems ? FontStyle.normal : FontStyle.italic,
          fontWeight: fontWeight ?? FontWeight.normal,
          color: color ?? (tab.tags == '' ? Colors.grey : null) ?? Theme.of(context).colorScheme.onBackground,
        ),
      );

      if (tab.tags.trim().isNotEmpty) {
        if (filterText?.isNotEmpty == true) {
          final List<TextSpan> spans = [];
          final List<String> split = tagText.split(filterText!);

          for (int i = 0; i < split.length; i++) {
            final spanStyle = TextStyle(
              fontSize: 16,
              fontStyle: hasItems ? FontStyle.normal : FontStyle.italic,
              fontWeight: fontWeight ?? FontWeight.normal,
              color: color ?? (tab.tags == '' ? Colors.grey : null) ?? Theme.of(context).colorScheme.onBackground,
            );

            spans.add(
              TextSpan(
                text: split[i],
                style: spanStyle,
              ),
            );
            if (i < split.length - 1) {
              spans.add(
                TextSpan(
                  text: filterText,
                  style: spanStyle.copyWith(backgroundColor: Colors.green),
                ),
              );
            }
          }

          marquee = MarqueeText.rich(
            key: ValueKey(tagText),
            textSpan: TextSpan(
              children: spans,
            ),
            style: TextStyle(
              fontSize: 16,
              fontStyle: hasItems ? FontStyle.normal : FontStyle.italic,
              fontWeight: fontWeight ?? FontWeight.normal,
              color: color ?? (tab.tags == '' ? Colors.grey : null) ?? Theme.of(context).colorScheme.onBackground,
            ),
          );
        } else if (withColoredTags) {
          final List<TextSpan> spans = [];
          final List<String> split = tagText.trim().split(' ');

          for (int i = 0; i < split.length; i++) {
            final tag = split[i].trim();

            final tagData = TagHandler.instance.getTag(tag);

            final bool isColored = !tagData.tagType.isNone;

            final spanStyle = TextStyle(
              fontSize: 16,
              fontStyle: hasItems ? FontStyle.normal : FontStyle.italic,
              fontWeight: fontWeight ?? FontWeight.normal,
              color: color ?? (tab.tags == '' ? Colors.grey : null) ?? Theme.of(context).colorScheme.onBackground,
              backgroundColor: isColored ? tagData.tagType.getColour().withOpacity(0.66) : null,
            );

            spans.add(
              TextSpan(
                // add non-breaking space to the end of italics to hide text overflowing the bgColor,
                text: '$tag${(hasItems || !isColored) ? '' : '\u{00A0}'}',
                style: spanStyle,
              ),
            );
            if (i < split.length - 1) {
              spans.add(
                TextSpan(
                  text: ' ',
                  style: spanStyle.copyWith(
                    backgroundColor: Colors.transparent,
                  ),
                ),
              );
            }
          }

          marquee = MarqueeText.rich(
            key: ValueKey(tagText),
            textSpan: TextSpan(
              children: spans,
            ),
            style: TextStyle(
              fontSize: 16,
              fontStyle: hasItems ? FontStyle.normal : FontStyle.italic,
              fontWeight: fontWeight ?? FontWeight.normal,
              color: color ?? (tab.tags == '' ? Colors.grey : null),
            ),
          );
        }
      }

      return SizedBox(
        width: double.maxFinite,
        child: Row(
          children: [
            if (withFavicon) ...[
              if (isNotEmptyBooru) ...[
                if (tab.selectedBooru.value.type == BooruType.Downloads)
                  const Icon(Icons.file_download_outlined, size: 18)
                else if (tab.selectedBooru.value.type == BooruType.Favourites)
                  const Icon(Icons.favorite, color: Colors.red, size: 18)
                else
                  Favicon(tab.selectedBooru.value, color: color),
              ] else
                const Icon(CupertinoIcons.question, size: 18),
              const SizedBox(width: 3),
            ],
            marquee,
          ],
        ),
      );
    });
  }
}
