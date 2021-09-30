import 'dart:ui';
import 'package:LoliSnatcher/SettingsHandler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import 'package:LoliSnatcher/SearchGlobals.dart';
import 'package:get/get.dart';
import 'package:LoliSnatcher/widgets/MarqueeText.dart';


class TagSearchBox extends StatefulWidget {
  TagSearchBox();
  @override
  _TagSearchBoxState createState() => _TagSearchBoxState();
}

class _TagSearchBoxState extends State<TagSearchBox> {
  final SettingsHandler settingsHandler = Get.find();
  final SearchHandler searchHandler = Get.find();

  OverlayEntry? _overlayEntry;
  String input = "";
  String lastTag = "";
  List splitInput = [];
  ScrollController scrollController = ScrollController();

  RxList<List<String>> booruResults = RxList([]);
  RxList<List<String>> historyResults = RxList([]);
  RxList<List<String>> databaseResults = RxList([]);
  RxList<List<String>> searchModifiersResults = RxList([]);

  @override
  void initState() {
    super.initState();
    searchHandler.searchBoxFocus.addListener(onFocusChange);
    input = searchHandler.searchTextController.text;
    splitInput = input.split(" ");
    lastTag = input;
  }

  void onFocusChange(){
    if (searchHandler.searchBoxFocus.hasFocus){
      createOverlay();
    } else {
      removeOverlay();
    }
  }

  void createOverlay() {
    if (searchHandler.searchBoxFocus.hasFocus){
      if (this._overlayEntry == null){
        tagStuff();
        combinedSearch();
        this._overlayEntry = _createOverlayEntry();
      }
      this._updateOverlay();
    }
  }

  void removeOverlay(){
    if (this._overlayEntry != null){
      if (this._overlayEntry!.mounted) {
        this._overlayEntry!.remove();
      }
    }
  }

  void _updateOverlay() {
    if (searchHandler.searchBoxFocus.hasFocus) {
      print("textbox is focused");
      if (!this._overlayEntry!.mounted) {
        Overlay.of(context)!.insert(this._overlayEntry!);
      } else {
        tagStuff();
        combinedSearch();
        this._overlayEntry!.markNeedsBuild();
      }
    } else {
      if (this._overlayEntry!.mounted) {
        this._overlayEntry!.remove();
      }
    }
  }

  @override
  void dispose() {
    removeOverlay();
    searchHandler.searchBoxFocus.unfocus();
    super.dispose();
  }

  void tagStuff() {
    if (searchHandler.currentTab.booruHandler.tagSearchEnabled) {
      input = searchHandler.searchTextController.text;
      splitInput = input.split(" ");
      // lastTag = input;
      // if (splitInput.length > 1) {
        // Get last tag in the input and remove minus (exclude symbol)
        // TODO /bug?: use the tag behind the current cursor position, not the last tag
        setState(() {
          lastTag = splitInput[splitInput.length - 1].replaceAll(RegExp(r'^-'), '');
        });
      // }
    }
  }

  void searchBooru(String input) async {
    booruResults.value = [[' ', 'loading']];
    List<String?>? getFromBooru = await searchHandler.currentTab.booruHandler.tagSearch(lastTag);
    booruResults.value = getFromBooru?.map((tag){
      final String tagTemp = tag != null ? tag : '';
      return [tagTemp, 'booru'];
    }).toList() ?? [];
  }
  void searchHistory(String input) async {
    historyResults.value = [[' ', 'loading']];
    historyResults.value = input.isNotEmpty
      ? (await settingsHandler.dbHandler.getSearchHistoryByInput(input, 2)).map((tag){
        return [tag, 'history'];
      }).toList()
      : [];
    historyResults.value = historyResults.where((tag) => booruResults.indexWhere((btag) => btag[0].toLowerCase() == tag[0].toLowerCase()) == -1).toList(); // filter out duplicates
  }
  void searchDatabase(String input) async {
    databaseResults.value = [[' ', 'loading']];
    databaseResults.value = input.isNotEmpty
      ? (await settingsHandler.dbHandler.getTags(input, 2)).map((tag){
        return [tag, 'database'];
      }).toList()
      : [];
    databaseResults.value = databaseResults.where((tag) => booruResults.indexWhere((btag) => btag[0].toLowerCase() == tag[0].toLowerCase()) == -1 && historyResults.indexWhere((htag) => htag[0].toLowerCase() == tag[0].toLowerCase()) == -1).toList();
  }
  // void searchModifiers(String input) async { }

  void combinedSearch() {
    searchBooru(lastTag);
    searchHistory(lastTag);
    searchDatabase(lastTag);
    // searchModifiers(lastTag);
  }

  Future<List<List<String>?>> combinedSearchOld(String input) async {
    List<String?>? getFromBooru = await searchHandler.currentTab.booruHandler.tagSearch(lastTag);
    final List<List<String>> booruResults = getFromBooru?.map((tag){
      final String tagTemp = tag != null ? tag : '';
      return [tagTemp, 'booru'];
    }).toList() ?? [];

    final List<List<String>> historyResults = input.isNotEmpty
      ? (await settingsHandler.dbHandler.getSearchHistoryByInput(input, 2)).map((tag){
        return [tag, 'history'];
      }).toList()
      : [];
    final List<List<String>> databaseResults = input.isNotEmpty
      ? (await settingsHandler.dbHandler.getTags(input, 2)).map((tag){
        return [tag, 'database'];
      }).toList()
      : [];

    // TODO add a list of search modifiers (rating:s, sort:score...) to every booru handler
    // final List<List<String>> searchModifiersResults = input.isNotEmpty
    //   ? searchHandler.booruHandler.searchModifiers().where((String sm) => sm.contains(input))
    //   : [];

    return [
      ...historyResults.where((tag) => booruResults.indexWhere((btag) => btag[0].toLowerCase() == tag[0].toLowerCase()) == -1), // filter out duplicates
      ...databaseResults.where((tag) => booruResults.indexWhere((btag) => btag[0].toLowerCase() == tag[0].toLowerCase()) == -1 && historyResults.indexWhere((htag) => htag[0].toLowerCase() == tag[0].toLowerCase()) == -1),
      ...booruResults
    ];
  }


  OverlayEntry? _createOverlayEntry() {
    RenderBox renderBox = context.findRenderObject()! as RenderBox;
    // searchHandler.currentTab.booruHandler.limit = 20;
    var size = renderBox.size;
    var offset = renderBox.localToGlobal(Offset.zero);

    return OverlayEntry(
      builder: (context) => Positioned(
        left: offset.dx,
        top: offset.dy + size.height + 5.0,
        width: size.width * 1.2,
        height: 300,
        child: Material(
          elevation: 4.0,
          child: Obx(() {
            List<List<String>> items = [
              ...historyResults,
              ...databaseResults,
              ...booruResults,
            ];
            if(items.length == 0) {
              return Container(
                padding: EdgeInsets.all(10),
                child: Text('No results!', style: TextStyle(fontSize: 16))
              );
            } else {
              return Scrollbar(
                controller: scrollController,
                interactive: true,
                isAlwaysShown: true,
                thickness: 10,
                radius: Radius.circular(10),
                child: ListView.builder(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (BuildContext context, int index) {
                    final List<String> item = items[index];
                    if (item[0].isNotEmpty) {
                      Widget? itemIcon;
                      switch (item[1]) {
                        case 'history':
                          itemIcon = Icon(Icons.history);
                        break;
                        case 'database':
                          itemIcon = Icon(Icons.archive);
                        break;
                        case 'loading':
                          itemIcon = CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(Get.theme.colorScheme.secondary)
                          );
                      }
                      return ListTile(
                        horizontalTitleGap: 4,
                        minLeadingWidth: 20,
                        minVerticalPadding: 0,
                        leading: itemIcon,
                        title: MarqueeText(
                          text: item[0],
                          fontSize: 16,
                          startPadding: 0,
                          isExpanded: false,
                        ),
                        onTap: (() {
                          // widget.searchBoxFocus.unfocus();
                          // Keep minus if its in the beggining of current (last) tag
                          bool isExclude = RegExp(r'^-').hasMatch(splitInput[splitInput.length - 1]);
                          String newInput = input.substring(0, input.lastIndexOf(" ") + 1) + (isExclude ? '-' : '') + item[0] + " ";
                          setState(() {
                            searchHandler.searchTextController.text = newInput;

                            // Set the cursor to the end of the search and reset the overlay data
                            searchHandler.searchTextController.selection = TextSelection.fromPosition(TextPosition(offset: newInput.length));
                          });
                          this._overlayEntry!.markNeedsBuild();
                        }),
                      );
                    } else {
                      return const SizedBox();
                    }
                  }
                )
              );
            }
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextField(
        controller: searchHandler.searchTextController,
        focusNode: searchHandler.searchBoxFocus,
        onChanged: (text) {
          createOverlay();
        },
        onSubmitted: (String text) {
          searchHandler.searchBoxFocus.unfocus();
          searchHandler.searchAction(text, null);
        },
        onEditingComplete: (){
          searchHandler.searchBoxFocus.unfocus();
        },
        onTap: (){
          if(!searchHandler.searchBoxFocus.hasFocus) {
            // set cursor to the end when tapped unfocused
            searchHandler.searchTextController.selection = TextSelection.fromPosition(TextPosition(offset: searchHandler.searchTextController.text.length));
          }
        },
        decoration: InputDecoration(
          fillColor: Get.theme.colorScheme.surface,
          filled: true,
          hintText: "Enter Tags",
          prefixIcon: searchHandler.searchTextController.text.length > 0
            ? IconButton(
                padding: const EdgeInsets.all(5),
                onPressed: () => setState(() {searchHandler.searchTextController.clear();}),
                icon: Icon(Icons.clear),
              )
            : null,
          contentPadding: EdgeInsets.fromLTRB(15, 0, 10, 0), // left,top,right,bottom
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Get.theme.colorScheme.secondary),
            borderRadius: BorderRadius.circular(50),
            gapPadding: 0,
          ),
          errorBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Get.theme.errorColor),
            borderRadius: BorderRadius.circular(50),
            gapPadding: 0,
          ),
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Get.theme.colorScheme.secondary),
            borderRadius: BorderRadius.circular(50),
            gapPadding: 0,
          ),
        ),
      )
    );
  }
}
