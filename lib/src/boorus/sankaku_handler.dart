import 'dart:async';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/comment_item.dart';
import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/note_item.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

class SankakuHandler extends BooruHandler {
  SankakuHandler(super.booru, super.limit);

  String authToken = '';

  @override
  Map<String, TagType> get tagTypeMap => {
        '8': TagType.meta,
        '3': TagType.copyright,
        '4': TagType.character,
        '1': TagType.artist,
        '0': TagType.none,
      };

  @override
  bool get hasSizeData => true;

  @override
  bool get hasTagSuggestions => true;

  @override
  bool get hasCommentsSupport => true;

  @override
  bool get hasNotesSupport => true;

  @override
  bool get hasLoadItemSupport => true;

  @override
  bool get hasSignInSupport => true;

  @override
  Future<Response<dynamic>> fetchSearch(
    Uri uri,
    String input, {
    bool withCaptchaCheck = true,
    Map<String, dynamic>? queryParams,
  }) async {
    return DioNetwork.get(
      uri.toString(),
      headers: getHeaders(),
      queryParameters: queryParams,
      options: fetchSearchOptions(),
      customInterceptor: withCaptchaCheck ? (dio) => DioNetwork.captchaInterceptor(dio, customUserAgent: Constants.defaultBrowserUserAgent) : null,
    );
  }

  @override
  List parseListFromResponse(dynamic response) {
    final List<dynamic> parsedResponse = response.data;
    return parsedResponse;
  }

  @override
  BooruItem? parseItemFromResponse(dynamic responseItem, int index) {
    final dynamic current = responseItem;

    final List<String> tags = [];
    final Map<TagType, List<String>> tagMap = {};

    for (int x = 0; x < current['tags'].length; x++) {
      tags.add(current['tags'][x]['tagName'].toString());
      final String typeStr = current['tags'][x]['type'].toString();
      final TagType type = tagTypeMap[typeStr] ?? TagType.none;
      if (tagMap.containsKey(type)) {
        tagMap[type]?.add(current['tags'][x]['tagName'].toString());
      } else {
        tagMap[type] = [current['tags'][x]['tagName'].toString()];
      }
    }
    tags.sort((a, b) => a.compareTo(b));

    if (current['file_url'] != null) {
      for (int i = 0; i < tagMap.entries.length; i++) {
        addTagsWithType(tagMap.entries.elementAt(i).value, tagMap.entries.elementAt(i).key);
      }

      // String fileExt = current["file_type"].split("/")[1]; // image/jpeg

      // backwards compatibility with possible future change (first seen in idol)
      final postDateIsString = current['created_at'] is String;
      // ISO string or unix time without in seconds (need to x1000?)
      final postDate = postDateIsString ? current['created_at'] : current['created_at']['s'].toString();
      final postDateFormat = postDateIsString ? 'iso' : 'unix';

      final BooruItem item = BooruItem(
        fileURL: current['file_url'],
        sampleURL: current['sample_url'],
        thumbnailURL: current['preview_url'],
        tagsList: tags,
        postURL: makePostURL(current['id'].toString()),
        fileSize: current['file_size'],
        fileWidth: current['width'].toDouble(),
        fileHeight: current['height'].toDouble(),
        sampleWidth: current['sample_width'].toDouble(),
        sampleHeight: current['sample_height'].toDouble(),
        previewWidth: current['preview_width'].toDouble(),
        previewHeight: current['preview_height'].toDouble(),
        hasNotes: current['has_notes'],
        hasComments: current['has_comments'],
        serverId: current['id'].toString(),
        rating: current['rating'],
        score: current['total_score'].toString(),
        md5String: current['md5'],
        postDate: postDate,
        postDateFormat: postDateFormat,
      );
      return item;
    } else {
      return null;
    }
  }

  @override
  Future<List> loadItem({required BooruItem item, CancelToken? cancelToken, bool withCapcthaCheck = false}) async {
    try {
      await searchSetup();
      final response = await DioNetwork.get(
        makeApiPostURL(item.postURL.split('/').last),
        headers: getHeaders(),
        cancelToken: cancelToken,
        customInterceptor: withCapcthaCheck ? (dio) => DioNetwork.captchaInterceptor(dio, customUserAgent: Constants.defaultBrowserUserAgent) : null,
      );
      if (response.statusCode != 200) {
        return [item, false, 'Invalid status code ${response.statusCode}'];
      } else {
        final Map<String, dynamic> current = response.data;
        Logger.Inst().log(current.toString(), className, 'updateFavourite', LogTypes.booruHandlerRawFetched);
        if (current['file_url'] != null) {
          item.fileURL = current['file_url'];
          item.sampleURL = current['sample_url'];
          item.thumbnailURL = current['preview_url'];
        }
      }
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        return [item, null, 'Cancelled'];
      }

      return [item, false, e.toString()];
    }
    return [item, true, null];
  }

  @override
  Map<String, String> getHeaders() {
    return {
      'Accept': 'application/json, text/plain, */*',
      if (authToken.isNotEmpty) 'Authorization': authToken,
      'User-Agent': Constants.sankakuAppUserAgent,
      'Referer': 'https://sankaku.app/',
      'Origin': 'https://sankaku.app',
      'api-version': '2',
    };
  }

  @override
  String makePostURL(String id) {
    return 'https://chan.sankakucomplex.com/post/show/$id';
  }

  static List<String> knownUrls = [
    'capi-v2.sankakucomplex.com',
    'sankakucomplex.com',
    'beta.sankakucomplex.com',
    'chan.sankakucomplex.com',
    'sankaku.app',
  ];

  String get baseUrl => knownUrls.any(booru.baseURL!.contains) ? 'https://sankakuapi.com' : booru.baseURL!;

  @override
  String makeURL(String tags) {
    final tagsStr = tags.trim().isEmpty ? '' : 'tags=${tags.trim()}&';

    return '$baseUrl/posts?${tagsStr}limit=$limit&page=$pageNum';
  }

  String makeApiPostURL(String id) {
    return '$baseUrl/posts/$id';
  }

  @override
  Future<bool> isSignedIn() async {
    return authToken.isNotEmpty;
  }

  @override
  Future<bool> signIn() async {
    bool success = false;
    try {
      final response = await DioNetwork.post(
        '$baseUrl/auth/token',
        queryParameters: {'lang': 'english'},
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': Constants.defaultBrowserUserAgent,
        },
        data: {'login': booru.userID, 'password': booru.apiKey},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> parsedResponse = response.data;
        if (parsedResponse['success']) {
          authToken = "${parsedResponse["token_type"]} ${parsedResponse["access_token"]}";
        }
      }
    } catch (e) {
      Logger.Inst().log('Sankaku auth error: $e', className, 'signIn', LogTypes.booruHandlerInfo);
    }
    if (authToken == '') {
      Logger.Inst().log('Sankaku auth error: empty token ', className, 'signIn', LogTypes.booruHandlerInfo);
      success = false;
    } else {
      Logger.Inst().log('Sankaku auth Got authtoken: $authToken', className, 'signIn', LogTypes.booruHandlerInfo);
      success = true;
    }
    return success;
  }

  @override
  Future<void> signOut({bool fromError = false}) async {
    authToken = '';
  }

  @override
  String makeTagURL(String input) {
    return '$baseUrl/tags?name=${input.toLowerCase()}&limit=20';
  }

  @override
  List parseTagSuggestionsList(dynamic response) {
    final List<dynamic> parsedResponse = response.data;
    return parsedResponse;
  }

  @override
  TagSuggestion? parseTagSuggestion(dynamic responseItem, int index) {
    // tagName - sankaku, name - idol
    final String tagStr = responseItem['tagName'] ?? responseItem['name'] ?? '';
    if (tagStr.isEmpty) {
      return null;
    }

    // record tag data for future use
    final String rawTagType = responseItem['type']?.toString() ?? '';
    TagType tagType = TagType.none;
    if (rawTagType.isNotEmpty && tagTypeMap.containsKey(rawTagType)) {
      tagType = tagTypeMap[rawTagType] ?? TagType.none;
    }
    addTagsWithType([tagStr], tagType);
    return TagSuggestion(
      tag: tagStr,
      type: tagType,
      count: responseItem['count'] ?? 0,
    );
  }

  @override
  String makeCommentsURL(String postID, int pageNum) {
    // EXAMPLE: https://sankakuapi.com/posts/25237881/comments
    // Possibly uses pages?
    return '$baseUrl/posts/$postID/comments';
  }

  @override
  List parseCommentsList(dynamic response) {
    final List<dynamic> parsedResponse = response.data;
    return parsedResponse;
  }

  @override
  CommentItem? parseComment(dynamic responseItem, int index) {
    final current = responseItem;
    return CommentItem(
      id: current['id'].toString(),
      title: current['post_id'].toString(),
      content: current['body'].toString(),
      authorID: current['author']['id'].toString(),
      authorName: current['author']['name'].toString(),
      avatarUrl: current['author']['avatar'].toString(),
      score: current['score'] ?? 0,
      postID: current['post_id'].toString(),
      createDate: current['created_at'].toString(), // unix time without in seconds (need to x1000?)
      createDateFormat: 'iso',
    );
  }

  @override
  String makeNotesURL(String postID) {
    return '$baseUrl/posts/$postID/notes';
  }

  @override
  List parseNotesList(dynamic response) {
    final List<dynamic> parsedResponse = response.data;
    return parsedResponse;
  }

  @override
  NoteItem? parseNote(dynamic responseItem, int index) {
    final current = responseItem;
    return NoteItem(
      id: current['id'].toString(),
      postID: current['post_id'].toString(),
      content: current['body'].toString(),
      posX: current['x'] ?? 0,
      posY: current['y'] ?? 0,
      width: current['width'] ?? 0,
      height: current['height'] ?? 0,
    );
  }

  @override
  List<MetaTag> availableMetaTags() {
    final tags = [...super.availableMetaTags()];
    final index = tags.indexWhere((e) => e is SortMetaTag);

    if (index != -1) {
      tags[index] = OrderMetaTag(
        values: [
          MetaTagValue(name: 'Popularity', value: 'popular'),
          ...(tags[index] as SortMetaTag).values,
        ],
      );
    }

    return tags;
  }
}
