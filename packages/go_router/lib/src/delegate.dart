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
    with ChangeNotifier {
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
        _restorablePropertiesRestorationId =
            '${restorationScopeId ?? ''}._GoRouterDelegateRestorableProperties' {
    builder = RouteBuilder(
      configuration: configuration,
      builderWithNav: builderWithNav,
      errorPageBuilder: errorPageBuilder,
      errorBuilder: errorBuilder,
      restorationScopeId: restorationScopeId,
      observers: observers,
      onPopPage: _onPopPage,
    );
  }

  /// Builds the top-level Navigator given a configuration and location.
  @visibleForTesting
  late final RouteBuilder builder;

  /// Set to true to disable creating history entries on the web.
  final bool routerNeglect;

  RouteMatchList _matchList = RouteMatchList.empty;

  final RouteConfiguration _configuration;

  final String _restorablePropertiesRestorationId;
  final GlobalKey<_GoRouterDelegateRestorablePropertiesState>
      _restorablePropertiesKey =
      GlobalKey<_GoRouterDelegateRestorablePropertiesState>();

  /// Increments the stored number of times each route route has been pushed.
  ///
  /// This is used to generate a unique key for each route.
  ///
  /// For example, it could be equal to:
  /// ```dart
  /// {
  ///   'family': 1,
  ///   'family/:fid': 2,
  /// }
  /// ```
  int _incrementPushCount(String path) {
    final _GoRouterDelegateRestorablePropertiesState?
        restorablePropertiesState = _restorablePropertiesKey.currentState;
    assert(restorablePropertiesState != null);

    final Map<String, int> pushCounts =
        restorablePropertiesState!.pushCount.value;
    final int count = (pushCounts[path] ?? -1) + 1;
    pushCounts[path] = count;
    restorablePropertiesState.pushCount.value = pushCounts;
    return count;
  }

  _NavigatorStateIterator _createNavigatorStateIterator() =>
      _NavigatorStateIterator(_matchList, navigatorKey.currentState!);

  @override
  Future<bool> popRoute() async {
    final _NavigatorStateIterator iterator = _createNavigatorStateIterator();
    while (iterator.moveNext()) {
      final bool didPop = await iterator.current.maybePop();
      if (didPop) {
        return true;
      }
    }
    return false;
  }

  ValueKey<String> _getNewKeyForPath(String path) {
    // Remap the pageKey to allow any number of the same page on the stack
    final int count = _incrementPushCount(path);
    return ValueKey<String>('$path-p$count');
  }

  Future<T?> _push<T extends Object?>(
      RouteMatchList matches, ValueKey<String> pageKey) async {
    final ImperativeRouteMatch<T> newPageKeyMatch = ImperativeRouteMatch<T>(
      pageKey: pageKey,
      matches: matches,
    );

    _matchList.push(newPageKeyMatch);
    return newPageKeyMatch._future;
  }

  /// Pushes the given location onto the page stack.
  ///
  /// See also:
  /// * [pushReplacement] which replaces the top-most page of the page stack and
  ///   always use a new page key.
  /// * [replace] which replaces the top-most page of the page stack but treats
  ///   it as the same page. The page key will be reused. This will preserve the
  ///   state and not run any page animation.
  Future<T?> push<T extends Object?>(RouteMatchList matches) async {
    assert(matches.last.route is! ShellRoute);

    final ValueKey<String> pageKey = _getNewKeyForPath(matches.fullpath);
    final Future<T?> future = _push(matches, pageKey);
    notifyListeners();
    return future;
  }

  /// Returns `true` if the active Navigator can pop.
  bool canPop() {
    final _NavigatorStateIterator iterator = _createNavigatorStateIterator();
    while (iterator.moveNext()) {
      if (iterator.current.canPop()) {
        return true;
      }
    }
    return false;
  }

  /// Pops the top-most route.
  void pop<T extends Object?>([T? result]) {
    final _NavigatorStateIterator iterator = _createNavigatorStateIterator();
    while (iterator.moveNext()) {
      if (iterator.current.canPop()) {
        iterator.current.pop<T>(result);
        return;
      }
    }
    throw GoError('There is nothing to pop');
  }

  void _debugAssertMatchListNotEmpty() {
    assert(
      _matchList.isNotEmpty,
      'You have popped the last page off of the stack,'
      ' there are no pages left to show',
    );
  }

  bool _onPopPage(Route<Object?> route, Object? result, RouteMatch? match) {
    if (!route.didPop(result)) {
      return false;
    }
    assert(match != null);
    if (match is ImperativeRouteMatch) {
      match.complete(result);
    }
    _matchList.remove(match!);
    notifyListeners();
    assert(() {
      _debugAssertMatchListNotEmpty();
      return true;
    }());
    return true;
  }

  /// Replaces the top-most page of the page stack with the given one.
  ///
  /// The page key of the new page will always be different from the old one.
  ///
  /// See also:
  /// * [push] which pushes the given location onto the page stack.
  /// * [replace] which replaces the top-most page of the page stack but treats
  ///   it as the same page. The page key will be reused. This will preserve the
  ///   state and not run any page animation.
  void pushReplacement(RouteMatchList matches) {
    assert(matches.last.route is! ShellRoute);
    _matchList.remove(_matchList.last);
    push(matches); // [push] will notify the listeners.
  }

  /// Replaces the top-most page of the page stack with the given one but treats
  /// it as the same page.
  ///
  /// The page key will be reused. This will preserve the state and not run any
  /// page animation.
  ///
  /// See also:
  /// * [push] which pushes the given location onto the page stack.
  /// * [pushReplacement] which replaces the top-most page of the page stack but
  ///   always uses a new page key.
  void replace(RouteMatchList matches) {
    assert(matches.last.route is! ShellRoute);
    final RouteMatch routeMatch = _matchList.last;
    final ValueKey<String> pageKey = routeMatch.pageKey;
    _matchList.remove(routeMatch);
    _push(matches, pageKey);
    notifyListeners();
  }

  /// For internal use; visible for testing only.
  @visibleForTesting
  RouteMatchList get matches => _matchList;

  /// For use by the Router architecture as part of the RouterDelegate.
  GlobalKey<NavigatorState> get navigatorKey => _configuration.navigatorKey;

  /// For use by the Router architecture as part of the RouterDelegate.
  @override
  RouteMatchList get currentConfiguration => _matchList;

  /// For use by the Router architecture as part of the RouterDelegate.
  @override
  Widget build(BuildContext context) {
    return _GoRouterDelegateRestorableProperties(
      key: _restorablePropertiesKey,
      restorationId: _restorablePropertiesRestorationId,
      builder: (BuildContext context) => builder.build(
        context,
        _matchList,
        routerNeglect,
      ),
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

/// An iterator that iterates through navigators that [GoRouterDelegate]
/// created from the inner to outer.
///
/// The iterator starts with the navigator that hosts the top-most route. This
/// navigator may not be the inner-most navigator if the top-most route is a
/// pageless route, such as a dialog or bottom sheet.
class _NavigatorStateIterator extends Iterator<NavigatorState> {
  _NavigatorStateIterator(this.matchList, this.root)
      : index = matchList.matches.length;

  final RouteMatchList matchList;
  int index = 0;
  final NavigatorState root;
  @override
  late NavigatorState current;

  @override
  bool moveNext() {
    if (index < 0) {
      return false;
    }
    late RouteBase subRoute;
    for (index -= 1; index >= 0; index -= 1) {
      final RouteMatch match = matchList.matches[index];
      final RouteBase route = match.route;
      if (route is GoRoute && route.parentNavigatorKey != null) {
        final GlobalKey<NavigatorState> parentNavigatorKey =
            route.parentNavigatorKey!;
        final ModalRoute<Object?>? parentModalRoute =
            ModalRoute.of(parentNavigatorKey.currentContext!);
        // The ModalRoute can be null if the parentNavigatorKey references the
        // root navigator.
        if (parentModalRoute == null) {
          index = -1;
          assert(root == parentNavigatorKey.currentState);
          current = root;
          return true;
        }
        // It must be a ShellRoute that holds this parentNavigatorKey;
        // otherwise, parentModalRoute would have been null. Updates the index
        // to the ShellRoute
        for (index -= 1; index >= 0; index -= 1) {
          final RouteBase route = matchList.matches[index].route;
          if (route is ShellRoute) {
            if (route.navigatorKey == parentNavigatorKey) {
              break;
            }
          }
        }
        // There may be a pageless route on top of ModalRoute that the
        // NavigatorState of parentNavigatorKey is in. For example, an open
        // dialog. In that case we want to find the navigator that host the
        // pageless route.
        if (parentModalRoute.isCurrent == false) {
          continue;
        }

        current = parentNavigatorKey.currentState!;
        return true;
      } else if (route is ShellRouteBase) {
        // Must have a ModalRoute parent because the navigator ShellRoute
        // created must not be the root navigator.
        final GlobalKey<NavigatorState> navigatorKey =
            route.navigatorKeyForSubRoute(subRoute);
        final ModalRoute<Object?> parentModalRoute =
            ModalRoute.of(navigatorKey.currentContext!)!;
        // There may be pageless route on top of ModalRoute that the
        // parentNavigatorKey is in. For example an open dialog.
        if (parentModalRoute.isCurrent == false) {
          continue;
        }
        current = navigatorKey.currentState!;
        return true;
      }
      subRoute = route;
    }
    assert(index == -1);
    current = root;
    return true;
  }
}

/// The route match that represent route pushed through [GoRouter.push].
class ImperativeRouteMatch<T> extends RouteMatch {
  /// Constructor for [ImperativeRouteMatch].
  ImperativeRouteMatch({
    required super.pageKey,
    required this.matches,
  })  : _completer = Completer<T?>(),
        super(
          route: matches.last.route,
          subloc: matches.last.subloc,
          extra: matches.last.extra,
          error: matches.last.error,
        );

  /// The matches that produces this route match.
  final RouteMatchList matches;

  /// The completer for the future returned by [GoRouter.push].
  final Completer<T?> _completer;

  /// Called when the corresponding [Route] associated with this route match is
  /// completed.
  void complete([dynamic value]) {
    _completer.complete(value as T?);
  }

  /// The future of the [RouteMatch] completer.
  /// When the future completes, this will return the value passed to [complete].
  Future<T?> get _future => _completer.future;
}

class _GoRouterDelegateRestorableProperties extends StatefulWidget {
  const _GoRouterDelegateRestorableProperties(
      {required super.key, required this.restorationId, required this.builder});

  final String restorationId;
  final WidgetBuilder builder;

  @override
  State<StatefulWidget> createState() =>
      _GoRouterDelegateRestorablePropertiesState();
}

class _GoRouterDelegateRestorablePropertiesState
    extends State<_GoRouterDelegateRestorableProperties> with RestorationMixin {
  final _RestorablePushCount pushCount = _RestorablePushCount();

  @override
  String? get restorationId => widget.restorationId;

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(pushCount, 'push_count');
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context);
  }
}

class _RestorablePushCount extends RestorableValue<Map<String, int>> {
  @override
  Map<String, int> createDefaultValue() => <String, int>{};

  @override
  Map<String, int> fromPrimitives(Object? data) {
    if (data is Map) {
      return data.map<String, int>((Object? key, Object? value) =>
          MapEntry<String, int>(key! as String, value! as int));
    }
    return <String, int>{};
  }

  @override
  Object? toPrimitives() => value;

  @override
  void didUpdateValue(Map<String, int>? oldValue) {
    notifyListeners();
  }
}
