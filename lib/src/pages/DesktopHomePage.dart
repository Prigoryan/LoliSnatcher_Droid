import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:LoliSnatcher/widgets/BooruSelectorMain.dart';
import 'package:LoliSnatcher/widgets/DesktopImageListener.dart';
import 'package:LoliSnatcher/widgets/ImagePreviews.dart';
import 'package:LoliSnatcher/widgets/TagView.dart';
import 'package:LoliSnatcher/widgets/TabBox.dart';
import 'package:LoliSnatcher/widgets/TabBoxButtons.dart';
import 'package:LoliSnatcher/widgets/TagSearchBox.dart';
import 'package:LoliSnatcher/widgets/SettingsWidgets.dart';
import 'package:LoliSnatcher/SearchGlobals.dart';
import 'package:LoliSnatcher/SettingsHandler.dart';
import 'package:LoliSnatcher/src/pages/SettingsPage.dart';
import 'package:LoliSnatcher/SnatchHandler.dart';
import 'package:LoliSnatcher/src/pages/SnatcherPage.dart';
import 'package:LoliSnatcher/src/services/getPerms.dart';
import 'package:LoliSnatcher/widgets/FlashElements.dart';
import 'package:LoliSnatcher/widgets/TagSearchButton.dart';
import 'package:LoliSnatcher/widgets/ResizableSplitView.dart';

class DesktopHome extends StatelessWidget {
  const DesktopHome({Key? key}) : super(key: key);


  @override
  Widget build(BuildContext context) {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    final SearchHandler searchHandler = SearchHandler.instance;
    final SnatchHandler snatchHandler = SnatchHandler.instance;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: Theme.of(context).colorScheme.background,
        actions: <Widget>[
          // Obx(() {
          //   if (settingsHandler.booruList.isNotEmpty && searchHandler.list.isNotEmpty) {
          //     return const DesktopTabs();
          //   } else {
          //     return const SizedBox();
          //   }
          // }),
          Obx(() {
            if (settingsHandler.booruList.isNotEmpty && searchHandler.list.isNotEmpty) {
              // return const SizedBox(width: 5);
              return Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: const <Widget>[
                    SizedBox(width: 15),
                    TagSearchBox(),
                    TagSearchButton(),
                    Expanded(flex: 1, child: BooruSelectorMain(true)),
                    Expanded(flex: 2, child: TabBox()),
                    Expanded(flex: 2, child: TabBoxButtons(false, WrapAlignment.start)),
                  ],
                ),
              );
            } else {
              return const SizedBox();
            }
          }),
          Obx(() {
            if (settingsHandler.booruList.isNotEmpty && searchHandler.list.isNotEmpty) {
              return SettingsButton(
                name: 'Snatcher',
                icon: Icon(Icons.download, color: Theme.of(context).colorScheme.onBackground),
                iconOnly: true,
                page: () => const SnatcherPage(),
              );
            } else {
              return const SizedBox();
            }
          }),
          Obx(() {
            if (settingsHandler.booruList.isEmpty || searchHandler.list.isEmpty) {
              return const Center(child: Text('Add Boorus in Settings'));
            } else {
              return const SizedBox();
            }
          }),
          SettingsButton(
            name: 'Settings',
            icon: Icon(Icons.settings, color: Theme.of(context).colorScheme.onBackground),
            iconOnly: true,
            page: () => const SettingsPage(),
          ),
          Obx(() {
            if (searchHandler.list.isNotEmpty) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  SettingsButton(
                    name: 'Save',
                    icon: Icon(Icons.save, color: Theme.of(context).colorScheme.onBackground),
                    iconOnly: true,
                    action: () {
                      getPerms();
                      // call a function to save the currently viewed image when the save button is pressed
                      if (searchHandler.currentTab.selected.isNotEmpty) {
                        snatchHandler.queue(
                          searchHandler.currentTab.getSelected(),
                          searchHandler.currentBooru,
                          settingsHandler.snatchCooldown,
                        );
                        searchHandler.currentTab.selected.value = [];
                      } else {
                        FlashElements.showSnackbar(
                          context: context,
                          title: const Text("No items selected", style: TextStyle(fontSize: 20)),
                          overrideLeadingIconWidget: const Text(" (」°ロ°)」 ", style: TextStyle(fontSize: 18)),
                        );
                      }
                    },
                  ),
                  if (searchHandler.currentTab.selected.isNotEmpty)
                    Positioned(
                      right: 2,
                      bottom: 5,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondary,
                          border: Border.all(color: Theme.of(context).colorScheme.secondary, width: 1),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Center(
                          child: FittedBox(
                            child: Text('${searchHandler.currentTab.selected.length}', style: TextStyle(color: Theme.of(context).colorScheme.onSecondary)),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            } else {
              return const SizedBox();
            }
          }),
        ],
      ),
      body: Center(
        child: ResizableSplitView(
          firstChild: ResizableSplitView(
            firstChild: const ImagePreviews(),
            secondChild: const DesktopTagListener(),
            startRatio: 0.66,
            minRatio: 0.33,
            maxRatio: 1,
            direction: SplitDirection.vertical,
            onRatioChange: (double newRatio) {
              // print('ratioChanged1 $newRatio');
              // TODO save to settings, but debounce the saving to file
            },
          ),
          secondChild: Obx(() => searchHandler.list.isEmpty ? const SizedBox() : DesktopImageListener(searchHandler.currentTab)),
          startRatio: 0.33,
          minRatio: 0.2,
          maxRatio: 0.8,
          onRatioChange: (double newRatio) {
            // print('ratioChanged2 $newRatio');
            // TODO save to settings, but debounce the saving to file
          },
        ),
      ),
    );
  }
}

class DesktopTagListener extends StatelessWidget {
  const DesktopTagListener({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final SearchHandler searchHandler = SearchHandler.instance;

    return Obx(() {
      if (searchHandler.list.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }

      return Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.secondary, width: 1),
        ),
        child: const TagView(),
      );
    });
  }
}
