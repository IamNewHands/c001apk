import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart' hide Response, FormData;

import '../../logic/model/feed/datum.dart';
import '../../logic/model/feed/user_action.dart';
import '../../logic/model/login/login_response.dart';
import '../../logic/network/network_repo.dart';
import '../../logic/network/api_failure.dart';
import '../../logic/state/loading_state.dart';
import '../../pages/home/return_top_controller.dart';
import '../../utils/extensions.dart';
import '../../utils/global_data.dart';
import '../../utils/storage_util.dart';
import '../../logic/content_filter/app_content_filter.dart';
import '../../logic/content_filter/content_filter_projection.dart';
import '../../logic/content_filter/content_filter_rule.dart';
import '../../logic/content_filter/content_filter_service.dart';
import 'package:hive/hive.dart';

abstract class CommonController extends GetxController {
  int page = 1;
  String? firstItem;
  String? lastItem;
  bool isLoading = false;
  bool isEnd = false;
  bool automaticLoadPaused = false;

  Rx<LoadingState> loadingState = LoadingState.loading().obs;
  Rx<LoadingState> footerState = LoadingState.empty().obs;
  GlobalKey<RefreshIndicatorState>? refreshKey;
  ScrollController? scrollController;
  ReturnTopController? returnTopController;
  List<Datum> rawItems = [];
  final filteredItems = <Datum>[].obs;
  final revealedContentKeys = <String>{};
  final revealedAuthorUids = <String>{};
  ContentFilterService? _filterService;
  StreamSubscription? _legacyFilterSubscription;
  bool get supportsContentFilter => true;

  @override
  void onInit() {
    super.onInit();
    _listenToFilters();
  }

  void _listenToFilters() {
    if (!supportsContentFilter) return;
    if (_filterService != AppContentFilter.service) {
      _filterService?.removeListener(reapplyFilters);
      _filterService = AppContentFilter.service;
      _filterService?.addListener(reapplyFilters);
    }
    if (_legacyFilterSubscription == null && Hive.isBoxOpen('blackList')) {
      _legacyFilterSubscription =
          GStorage.blackList.watch().listen((_) => reapplyFilters());
    }
  }

  FilterMatch? filterMatch(Datum item) {
    if (!supportsContentFilter) return null;
    if (revealedContentKeys.contains(ContentFilterProjection.keyOf(item))) {
      return null;
    }
    final match = ContentFilterProjection.match(item);
    if (match?.kind == FilterRuleKind.author &&
        revealedAuthorUids.contains('${item.uid}')) {
      return null;
    }
    return match;
  }

  void revealItem(Datum item) {
    revealedContentKeys.add(ContentFilterProjection.keyOf(item));
    reapplyFilters();
  }

  void revealAuthorForPage(String uid) {
    revealedAuthorUids.add(uid);
    reapplyFilters();
  }

  void publishItems(List<Datum> items, {bool append = false}) {
    _listenToFilters();
    final previous = !supportsContentFilter && loadingState.value is Success
        ? List<Datum>.from((loadingState.value as Success).response)
        : rawItems;
    final combined = append ? [...previous, ...items] : items;
    rawItems = handleUnique(combined) ?? combined;
    reapplyFilters();
  }

  void reapplyFilters() {
    if (isClosed) return;
    final hidden = <Datum>[];
    final visible = <Datum>[];
    for (final item in rawItems) {
      if (filterMatch(item) != null) {
        hidden.add(item);
        // Keep comment relationships; each comment card renders a placeholder.
        if (item.entityType == 'feed_reply') visible.add(item);
      } else {
        visible.add(item);
      }
    }
    filteredItems.assignAll(hidden);
    if (rawItems.isNotEmpty || loadingState.value is Success) {
      loadingState.value = LoadingState.success(visible);
    }
  }

  @override
  void onClose() {
    _filterService?.removeListener(reapplyFilters);
    _legacyFilterSubscription?.cancel();
    super.onClose();
  }

  List<Datum>? handleResponse(List<Datum> dataList) {
    return null;
  }

  List<Datum>? handleUnique(List<Datum> dataList) {
    return dataList.unique((data) =>
        '${data.entityType}:${data.entityId ?? data.id ?? identityHashCode(data)}');
  }

  LoadingState? handleExtraResponse() {
    return null;
  }

  Future<LoadingState> customGetData();

  Future<void> onGetData([bool isRefresh = true]) async {
    if (!isLoading) {
      _listenToFilters();
      final generation = GlobalData().sessionGeneration;
      isLoading = true;
      automaticLoadPaused = false;
      try {
        for (var attempt = 0; attempt < 3; attempt++) {
          LoadingState response = await customGetData();
          if (isClosed || generation != GlobalData().sessionGeneration) {
            isLoading = false;
            return;
          }
          if (response is Success) {
            List<Datum> dataList = supportsContentFilter
                ? response.rawResponse ?? response.response
                : response.response;
            firstItem ??=
                response.firstItem ?? dataList.firstOrNull?.id.toString();
            lastItem = response.lastItem ??
                dataList.lastOrNull?.id.toString() ??
                lastItem;
            List<Datum>? responseList = handleResponse(dataList);
            if (responseList != null) {
              dataList = responseList;
            }
            if (dataList.any((e) => e.entityTemplate == 'noMoreDataCard')) {
              isEnd = true;
              footerState.value = LoadingState.empty();
            }
            final hasVisibleItems =
                dataList.any((item) => filterMatch(item) == null);
            publishItems(dataList, append: !isRefresh || attempt > 0);
            if (loadingState.value is! Success) {
              loadingState.value = LoadingState.success(<Datum>[]);
            }
            page++;
            if (hasVisibleItems || isEnd) break;
            if (attempt == 2) {
              automaticLoadPaused = true;
              footerState.value = LoadingState.error('点击继续加载');
            }
          } else {
            isEnd = response is Empty;
            automaticLoadPaused = response is Error;
            LoadingState? extraResponse = handleExtraResponse();
            if (extraResponse != null) {
              response = extraResponse;
            }
            if (isRefresh && attempt == 0) {
              if (response is Empty) {
                rawItems = [];
                filteredItems.clear();
              }
              loadingState.value = response;
              if (response is Success) {
                publishItems(List<Datum>.from(response.response));
              }
            } else {
              footerState.value = response;
            }
            break;
          }
        }
      } finally {
        isLoading = false;
      }
    }
  }

  void onReset() {
    page = 1;
    isEnd = false;
    automaticLoadPaused = false;
    firstItem = null;
    lastItem = null;
    footerState.value = LoadingState.loading();
    revealedContentKeys.clear();
  }

  void setFooterState(LoadingState footerState) {
    this.footerState.value = footerState;
  }

  void setLoadingState(LoadingState loadingState) {
    this.loadingState.value = loadingState;
  }

  Future<void> animateToTop() async {
    scrollController?.animToTop();
    returnTopController?.setIndex(999);
    refreshKey?.currentState?.show();
  }

  void onBlock(dynamic uid) {
    reapplyFilters();
  }

  Future<void> postLikeDeleteFollow(
    dynamic id,
    dynamic fid, {
    bool isFollow = false,
    bool isFeed = false,
    bool isReply = false,
    bool isNoti = false,
    bool isProduct = false,
  }) async {
    String url = isFeed
        ? '/v6/feed/deleteFeed'
        : isReply
            ? '/v6/feed/deleteReply'
            : isNoti
                ? '/v6/notification/delete'
                : '/v6/product/changeFollowStatus';
    try {
      Response response = await NetworkRepo.postLikeDeleteFollow(
        url,
        id: isProduct ? null : id,
        data: isProduct
            ? FormData.fromMap({'id': id, 'status': isFollow ? 0 : 1})
            : null,
      );
      readApiObject(response);
      LoginResponse data = LoginResponse.fromJson(response.data);
      if (!data.message.isNullOrEmpty) {
        SmartDialog.showToast(data.message!);
        if (isProduct) {
          handleGetFollow();
        }
      } else if (data.data != null) {
        List<Datum> dataList = rawItems;
        if (fid != null) {
          dataList = dataList.map((data) {
            if (data.id == fid) {
              return data
                ..replyRows =
                    data.replyRows!.where((data) => data.id != id).toList();
            } else {
              return data;
            }
          }).toList();
        } else {
          dataList = dataList.where((data) => data.id != id).toList();
        }
        publishItems(dataList);
        SmartDialog.showToast(data.data!);
      }
    } catch (e) {
      SmartDialog.showToast(ApiFailure.fromError(e).message);
    }
  }

  bool handleLike(dynamic like, dynamic likenum) {
    return false;
  }

  Future<void> onLike(
    dynamic id,
    dynamic like, {
    bool isFeed = false,
    bool isReply = false,
  }) async {
    try {
      String isLike = isFeed
          ? (like == 1 ? 'unlike' : 'like')
          : (like == 1 ? 'unLikeReply' : 'likeReply');
      Response response =
          await NetworkRepo.postLikeDeleteFollow('/v6/feed/$isLike', id: id);
      readApiObject(response);
      LoginResponse datum = LoginResponse.fromJson(response.data);
      if (!datum.message.isNullOrEmpty) {
        SmartDialog.showToast(datum.message!);
      } else {
        if (isFeed && handleLike(like, datum.data['count'])) {
          return;
        }
        List<Datum> dataList = (loadingState.value as Success).response;
        dataList = dataList.map((data) {
          if (data.id == id) {
            return data
              ..likenum = isFeed ? datum.data['count'] : datum.data
              ..userAction = UserAction(like: like == 1 ? 0 : 1);
          } else {
            return data;
          }
        }).toList();
        loadingState.value = LoadingState.success(dataList);
      }
    } catch (e) {
      SmartDialog.showToast(ApiFailure.fromError(e).message);
    }
  }

  void handleGetFollow() {}

  Future<void> onGetFollow(
    bool isFollow,
    String url, {
    dynamic tag,
    dynamic id,
  }) async {
    try {
      Response response = await NetworkRepo.getFollow(url, tag: tag, id: id);
      final body =
          readApiObject(response, allowSuccessWithoutData: tag != null);
      LoginResponse data = LoginResponse.fromJson(body);
      if (!data.message.isNullOrEmpty) {
        SmartDialog.showToast(data.message!);
        if (tag != null) {
          handleGetFollow();
        }
      } else if (data.data != null) {
        SmartDialog.showToast(isFollow ? '取消关注成功' : '关注成功');
        handleGetFollow();
      }
    } catch (e) {
      SmartDialog.showToast(ApiFailure.fromError(e).message);
    }
  }

  void onPM(dynamic id) {
    List<Datum> dataList = (loadingState.value as Success).response;
    dataList = dataList.map((data) {
      if (data.id == id) {
        return data..unreadNum = null;
      } else {
        return data;
      }
    }).toList();
    loadingState.value = LoadingState.success(dataList);
  }
}
