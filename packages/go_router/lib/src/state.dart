// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/widgets.dart';

import '../go_router.dart';
import 'configuration.dart';
import 'misc/errors.dart';

/// The route state during routing.
///
/// The state contains parsed artifacts of the current URI.
@immutable
class GoRouterState {
  /// Default constructor for creating route state during routing.
  GoRouterState(
    this._configuration, {
    required this.location,
    required this.subloc,
    required this.name,
    this.path,
    this.fullpath,
    this.params = const <String, String>{},
    this.queryParams = const <String, String>{},
    this.queryParametersAll = const <String, List<String>>{},
    this.extra,
    this.error,
    ValueKey<String>? pageKey,
  }) : pageKey = pageKey ??
            ValueKey<String>(error != null
                ? 'error'
                : fullpath != null && fullpath.isNotEmpty
                    ? fullpath
                    : subloc);

  // TODO(johnpryan): remove once namedLocation is removed from go_router.
  // See https://github.com/flutter/flutter/issues/107729
  final RouteConfiguration _configuration;

  /// The full location of the route, e.g. /family/f2/person/p1
  final String location;

  /// The location of this sub-route, e.g. /family/f2
  final String subloc;

  /// The optional name of the route.
  final String? name;

  /// The path to this sub-route, e.g. family/:fid
  final String? path;

  /// The full path to this sub-route, e.g. /family/:fid
  final String? fullpath;

  /// The parameters for this sub-route, e.g. {'fid': 'f2'}
  final Map<String, String> params;

  /// The query parameters for the location, e.g. {'from': '/family/f2'}
  final Map<String, String> queryParams;

  /// The query parameters for the location,
  /// e.g. `{'q1': ['v1'], 'q2': ['v2', 'v3']}`
  final Map<String, List<String>> queryParametersAll;

  /// An extra object to pass along with the navigation.
  final Object? extra;

  /// The error associated with this sub-route.
  final Exception? error;

  /// A unique string key for this sub-route, e.g. ValueKey('/family/:fid')
  final ValueKey<String> pageKey;

  /// Gets the [GoRouterState] from context.
  ///
  /// The returned [GoRouterState] will depends on which [GoRoute] or
  /// [ShellRoute] the input `context` is in.
  ///
  /// This method only supports [GoRoute] and [ShellRoute] that generate
  /// [ModalRoute]s. This is typically the case if one uses [GoRoute.builder],
  /// [ShellRoute.builder], [CupertinoPage], [MaterialPage],
  /// [CustomTransitionPage], or [NoTransitionPage].
  ///
  /// This method is fine to be called during [GoRoute.builder] or
  /// [ShellRoute.builder].
  ///
  /// This method cannot be called during [GoRoute.pageBuilder] or
  /// [ShellRoute.pageBuilder] since there is no [GoRouterState] to be
  /// associated with.
  ///
  /// To access GoRouterState from a widget.
  ///
  /// ```
  /// GoRoute(
  ///   path: '/:id'
  ///   builder: (_, __) => MyWidget(),
  /// );
  ///
  /// class MyWidget extends StatelessWidget {
  ///   @override
  ///   Widget build(BuildContext context) {
  ///     return Text('${GoRouterState.of(context).params['id']}');
  ///   }
  /// }
  /// ```
  static GoRouterState of(BuildContext context) {
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (route == null) {
      throw GoError('There is no modal route above the current context.');
    }
    final RouteSettings settings = route.settings;
    if (settings is! Page<Object?>) {
      throw GoError(
          'The parent route must be a page route to have a GoRouterState');
    }
    final GoRouterStateRegistryScope? scope = context
        .dependOnInheritedWidgetOfExactType<GoRouterStateRegistryScope>();
    if (scope == null) {
      throw GoError(
          'There is no GoRouterStateRegistryScope above the current context.');
    }
    final GoRouterState state =
        scope.notifier!._createPageRouteAssociation(settings, route);
    return state;
  }

  /// Get a location from route name and parameters.
  /// This is useful for redirecting to a named location.
  @Deprecated(
      'Uses GoRouter.of(context).routeInformationParser.namedLocation instead')
  String namedLocation(
    String name, {
    Map<String, String> params = const <String, String>{},
    Map<String, String> queryParams = const <String, String>{},
  }) {
    return _configuration.namedLocation(name,
        params: params, queryParams: queryParams);
  }

  @override
  bool operator ==(Object other) {
    return other is GoRouterState &&
        other.location == location &&
        other.subloc == subloc &&
        other.name == name &&
        other.path == path &&
        other.fullpath == fullpath &&
        other.params == params &&
        other.queryParams == queryParams &&
        other.queryParametersAll == queryParametersAll &&
        other.extra == extra &&
        other.error == error &&
        other.pageKey == pageKey;
  }

  @override
  int get hashCode => Object.hash(location, subloc, name, path, fullpath,
      params, queryParams, queryParametersAll, extra, error, pageKey);
}

/// An inherited widget to host a [GoRouterStateRegistry] for the subtree.
///
/// Should not be used directly, consider using [GoRouterState.of] to access
/// [GoRouterState] from the context.
class GoRouterStateRegistryScope
    extends InheritedNotifier<GoRouterStateRegistry> {
  /// Creates a GoRouterStateRegistryScope.
  const GoRouterStateRegistryScope({
    super.key,
    required GoRouterStateRegistry registry,
    required super.child,
  }) : super(notifier: registry);
}

/// A registry to record [GoRouterState] to [Page] relation.
///
/// Should not be used directly, consider using [GoRouterState.of] to access
/// [GoRouterState] from the context.
class GoRouterStateRegistry extends ChangeNotifier {
  /// creates a [GoRouterStateRegistry].
  GoRouterStateRegistry();

  /// A [Map] that maps a [Page] to a [GoRouterState].
  @visibleForTesting
  final Map<Page<Object?>, GoRouterState> registry =
      <Page<Object?>, GoRouterState>{};

  final Map<Route<Object?>, Page<Object?>> _routePageAssociation =
      <ModalRoute<Object?>, Page<Object?>>{};

  GoRouterState _createPageRouteAssociation(
      Page<Object?> page, ModalRoute<Object?> route) {
    assert(route.settings == page);
    assert(registry.containsKey(page));
    final Page<Object?>? oldPage = _routePageAssociation[route];
    if (oldPage == null) {
      // This is a new association.
      _routePageAssociation[route] = page;
      // If there is an association, the registry relies on the route to remove
      // entry from registry because it wants to preserve the GoRouterState
      // until the route finishes the popping animations.
      route.completed.then<void>((Object? result) {
        // Can't use `page` directly because Route.settings may have changed during
        // the lifetime of this route.
        final Page<Object?> associatedPage =
            _routePageAssociation.remove(route)!;
        assert(registry.containsKey(associatedPage));
        registry.remove(associatedPage);
      });
    } else if (oldPage != page) {
      // Need to update the association to avoid memory leak.
      _routePageAssociation[route] = page;
      assert(registry.containsKey(oldPage));
      registry.remove(oldPage);
    }
    assert(_routePageAssociation[route] == page);
    return registry[page]!;
  }

  /// Updates this registry with new records.
  void updateRegistry(Map<Page<Object?>, GoRouterState> newRegistry) {
    bool shouldNotify = false;
    final Set<Page<Object?>> pagesWithAssociation =
        _routePageAssociation.values.toSet();
    for (final MapEntry<Page<Object?>, GoRouterState> entry
        in newRegistry.entries) {
      final GoRouterState? existingState = registry[entry.key];
      if (existingState != null) {
        if (existingState != entry.value) {
          shouldNotify =
              shouldNotify || pagesWithAssociation.contains(entry.key);
          registry[entry.key] = entry.value;
        }
        continue;
      }
      // Not in the _registry.
      registry[entry.key] = entry.value;
      // Adding or removing registry does not need to notify the listen since
      // no one should be depending on them.
    }
    registry.removeWhere((Page<Object?> key, GoRouterState value) {
      if (newRegistry.containsKey(key)) {
        return false;
      }
      // For those that have page route association, it will be removed by the
      // route future. Need to notify the listener so they can update the page
      // route association if its page has changed.
      if (pagesWithAssociation.contains(key)) {
        shouldNotify = true;
        return false;
      }
      return true;
    });
    if (shouldNotify) {
      notifyListeners();
    }
  }
}

/// The current state for a [StatefulShellRoute].
class StatefulShellRouteState {
  /// Constructs a [StatefulShellRouteState].
  StatefulShellRouteState({
    required this.route,
    required this.navigationBranchState,
    required this.currentBranchIndex,
  });

  /// The associated [StatefulShellRoute]
  final StatefulShellRoute route;

  /// The state for all separate route branches associated with a
  /// [StatefulShellRoute].
  final List<ShellRouteBranchState> navigationBranchState;

  /// The index of the currently active route branch.
  final int currentBranchIndex;

  /// Gets the current location from the [topRouteState] or falls back to
  /// the root path of the associated [route].
  String get currentLocation =>
      navigationBranchState[currentBranchIndex].currentLocation;
}

/// The current state for a particular route branch
/// ([ShellRouteBranch]) of a [StatefulShellRoute].
class ShellRouteBranchState {
  /// Constructs a [ShellRouteBranchState].
  ShellRouteBranchState({
    required this.navigationItem,
    required this.rootRoutePath,
  });

  /// The associated [ShellRouteBranch]
  final ShellRouteBranch navigationItem;

  /// The full path at which root route for the route branch is reachable.
  final String rootRoutePath;

  /// The [Navigator] for this route branch in a [StatefulShellRoute]. This
  /// field will typically not be set until this route tree has been navigated
  /// to at least once.
  Navigator? navigator;

  /// The [GoRouterState] for the top of the current navigation stack.
  GoRouterState? topRouteState;

  /// Gets the defaultLocation specified in [navigationItem] or falls back to
  /// the root path of the associated [route].
  String get defaultLocation => navigationItem.defaultLocation ?? rootRoutePath;

  /// Gets the current location from the [topRouteState] or falls back to
  /// [defaultLocation].
  String get currentLocation => topRouteState?.location ?? defaultLocation;

  /// The root route for the route branch.
  RouteBase get route => navigationItem.rootRoute;
}
