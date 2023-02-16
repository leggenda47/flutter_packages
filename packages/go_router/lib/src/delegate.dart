// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'builder.dart';
import 'configuration.dart';
import 'match.dart';
import 'matching.dart';
import 'misc/errors.dart';
import 'typedefs.dart';

/// GoRouter implementation of [RouterDelegate].
class GoRouterDelegate extends RouterDelegate<RouteMatchList>
    with PopNavigatorRouterDelegateMixin<RouteMatchList>, ChangeNotifier {
  /// Constructor for GoRouter's implementation of the RouterDelegate base
  /// class.
  GoRouterDelegate({
    required RouteConfiguration configuration,
    required GoRouterBuilderWithNav builderWithNav,
    required GoRouterPageBuilder? errorPageBuilder,
    required GoRouterWidgetBuilder? errorBuilder,
    required List<NavigatorObserver> observers,
    required this.routerNeglect,
    String? restorationScopeId,
  })  : _configuration = configuration,
        builder = RouteBuilder(
          configuration: configuration,
          builderWithNav: builderWithNav,
          errorPageBuilder: errorPageBuilder,
          errorBuilder: errorBuilder,
          restorationScopeId: restorationScopeId,
          observers: observers,
        );

  /// Builds the top-level Navigator given a configuration and location.
  @visibleForTesting
  final RouteBuilder builder;

  /// Set to true to disable creating history entries on the web.
  final bool routerNeglect;

  RouteMatchList _matchList = RouteMatchList.empty();
  final Map<String, int> _pushCounts = <String, int>{};
  final RouteConfiguration _configuration;

  @override
  Future<bool> popRoute() async {
    // Iterate backwards through the RouteMatchList until seeing a GoRoute with
    // a non-null parentNavigatorKey or a ShellRoute with a non-null
    // parentNavigatorKey and pop from that Navigator instead of the root.
    final int matchCount = _matchList.matches.length;
    RouteBase? childRoute;
    for (int i = matchCount - 1; i >= 0; i -= 1) {
      final RouteMatch match = _matchList.matches[i];
      final RouteBase route = match.route;

      if (route is GoRoute && route.parentNavigatorKey != null) {
        final bool didPop =
            await route.parentNavigatorKey!.currentState!.maybePop();

        // Continue if didPop was false.
        if (didPop) {
          return didPop;
        }
      } else if (route is ShellRouteBase && childRoute != null) {
        // For shell routes, find the navigator key that should be used for the
        // child route in the current match list
        final GlobalKey<NavigatorState>? navigatorKey =
            route.navigatorKeyForChildRoute(childRoute);

        final bool didPop =
            await navigatorKey?.currentState!.maybePop() ?? false;

        // Continue if didPop was false.
        if (didPop) {
          return didPop;
        }
      }
      childRoute = route;
    }

    // Use the root navigator if no ShellRoute Navigators were found and didn't
    // pop
    final NavigatorState navigator = navigatorKey.currentState!;
    return navigator.maybePop();
  }

  /// Pushes the given location onto the page stack with an optional promise.
  // Remap the pageKey to allow any number of the same page on the stack.
  Future<T?> push<T extends Object?>(RouteMatch match) {
    if (match.route is ShellRoute) {
      throw GoError('ShellRoutes cannot be pushed');
    }

    // Remap the pageKey to allow any number of the same page on the stack
    final String fullPath = match.fullpath;

    // Create a completer for the promise and store it in the completers map.
    final Completer<T?> completer = Completer<T?>();

    final int count = (_pushCounts[fullPath] ?? 0) + 1;
    _pushCounts[fullPath] = count;
    final ValueKey<String> pageKey = ValueKey<String>('$fullPath-p$count');
    final RouteMatch newPageKeyMatch = RouteMatch(
      completer: completer,
      route: match.route,
      subloc: match.subloc,
      fullpath: match.fullpath,
      encodedParams: match.encodedParams,
      queryParams: match.queryParams,
      queryParametersAll: match.queryParametersAll,
      extra: match.extra,
      error: match.error,
      pageKey: pageKey,
    );

    _matchList.push(newPageKeyMatch);
    notifyListeners();
    return completer.future;
  }

  /// Returns `true` if the active Navigator can pop.
  bool canPop() {
    // Loop through navigators in reverse and call canPop()
    final int matchCount = _matchList.matches.length;
    RouteBase? childRoute;
    for (int i = matchCount - 1; i >= 0; i -= 1) {
      final RouteMatch match = _matchList.matches[i];
      final RouteBase route = match.route;
      if (route is GoRoute && route.parentNavigatorKey != null) {
        final bool canPop =
            route.parentNavigatorKey!.currentState?.canPop() ?? false;

        // Continue if canPop is false.
        if (canPop) {
          return canPop;
        }
      } else if (route is ShellRouteBase && childRoute != null) {
        // For shell routes, find the navigator key that should be used for the
        // child route in the current match list
        final GlobalKey<NavigatorState>? navigatorKey =
            route.navigatorKeyForChildRoute(childRoute);

        final bool canPop = navigatorKey?.currentState!.canPop() ?? false;

        // Continue if canPop is false.
        if (canPop) {
          return canPop;
        }
      }
      childRoute = route;
    }
    return navigatorKey.currentState?.canPop() ?? false;
  }

  /// Pop the top page off the GoRouter's page stack and complete a promise if
  /// there is one.
  void pop<T extends Object?>([T? value]) {
    final RouteMatch last = _matchList.last;

    // If there is a promise for this page, complete it.
    if (last.completer != null) {
      last.completer?.complete(value);
    }

    _matchList.pop();
    notifyListeners();
  }

  /// Replaces the top-most page of the page stack with the given one.
  ///
  /// See also:
  /// * [push] which pushes the given location onto the page stack.
  Future<T?>? replace<T extends Object?>(RouteMatch match) {
    _matchList.matches.last = match;

    notifyListeners();
    return match.completer?.future as Future<T?>?;
  }

  /// For internal use; visible for testing only.
  @visibleForTesting
  RouteMatchList get matches => _matchList;

  /// For use by the Router architecture as part of the RouterDelegate.
  @override
  GlobalKey<NavigatorState> get navigatorKey => _configuration.navigatorKey;

  /// For use by the Router architecture as part of the RouterDelegate.
  @override
  RouteMatchList get currentConfiguration => _matchList;

  /// For use by the Router architecture as part of the RouterDelegate.
  @override
  Widget build(BuildContext context) {
    return builder.build(
      context,
      _matchList,
      pop,
      routerNeglect,
    );
  }

  /// For use by the Router architecture as part of the RouterDelegate.
  @override
  Future<void> setNewRoutePath(RouteMatchList configuration) {
    _matchList = configuration;
    assert(_matchList.isNotEmpty);
    notifyListeners();
    // Use [SynchronousFuture] so that the initial url is processed
    // synchronously and remove unwanted initial animations on deep-linking
    return SynchronousFuture<void>(null);
  }
}
