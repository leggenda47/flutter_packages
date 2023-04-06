// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import '../go_router.dart';
import 'information_provider.dart';
import 'matching.dart';
import 'path_utils.dart';
import 'typedefs.dart';

/// The base class for [GoRoute] and [ShellRoute].
///
/// Routes are defined in a tree such that parent routes must match the
/// current location for their child route to be considered a match. For
/// example the location "/home/user/12" matches with parent route "/home" and
/// child route "user/:userId".
///
/// To create sub-routes for a route, provide them as a [GoRoute] list
/// with the sub routes.
///
/// For example these routes:
/// ```
/// /         => HomePage()
///   family/f1 => FamilyPage('f1')
///     person/p2 => PersonPage('f1', 'p2') ← showing this page, Back pops ↑
/// ```
///
/// Can be represented as:
///
/// ```
/// final GoRouter _router = GoRouter(
///   routes: <GoRoute>[
///     GoRoute(
///       path: '/',
///       pageBuilder: (BuildContext context, GoRouterState state) => MaterialPage<void>(
///         key: state.pageKey,
///         child: HomePage(families: Families.data),
///       ),
///       routes: <GoRoute>[
///         GoRoute(
///           path: 'family/:fid',
///           pageBuilder: (BuildContext context, GoRouterState state) {
///             final Family family = Families.family(state.params['fid']!);
///             return MaterialPage<void>(
///               key: state.pageKey,
///               child: FamilyPage(family: family),
///             );
///           },
///           routes: <GoRoute>[
///             GoRoute(
///               path: 'person/:pid',
///               pageBuilder: (BuildContext context, GoRouterState state) {
///                 final Family family = Families.family(state.params['fid']!);
///                 final Person person = family.person(state.params['pid']!);
///                 return MaterialPage<void>(
///                   key: state.pageKey,
///                   child: PersonPage(family: family, person: person),
///                 );
///               },
///             ),
///           ],
///         ),
///       ],
///     ),
///   ],
/// );
///
/// If there are multiple routes that match the location, the first match is used.
/// To make predefined routes to take precedence over dynamic routes eg. '/:id'
/// consider adding the dynamic route at the end of the routes
/// For example:
/// ```
/// final GoRouter _router = GoRouter(
///   routes: <GoRoute>[
///     GoRoute(
///       path: '/',
///       redirect: (_) => '/family/${Families.data[0].id}',
///     ),
///     GoRoute(
///       path: '/family',
///       pageBuilder: (BuildContext context, GoRouterState state) => ...,
///     ),
///     GoRoute(
///       path: '/:username',
///       pageBuilder: (BuildContext context, GoRouterState state) => ...,
///     ),
///   ],
/// );
/// ```
/// In the above example, if /family route is matched, it will be used.
/// else /:username route will be used.
/// ///
/// See [main.dart](https://github.com/flutter/packages/blob/main/packages/go_router/example/lib/main.dart)
@immutable
abstract class RouteBase {
  const RouteBase._({
    this.routes = const <RouteBase>[],
  });

  /// The list of child routes associated with this route.
  final List<RouteBase> routes;
}

/// A route that is displayed visually above the matching parent route using the
/// [Navigator].
///
/// The widget returned by [builder] is wrapped in [Page] and provided to the
/// root Navigator, the nearest ShellRoute ancestor's Navigator, or the
/// Navigator with a matching [parentNavigatorKey].
///
/// The Page depends on the application type: [MaterialPage] for
/// [MaterialApp], [CupertinoPage] for [CupertinoApp], or
/// [NoTransitionPage] for [WidgetsApp].
///
/// {@category Get started}
/// {@category Configuration}
/// {@category Transition animations}
/// {@category Named routes}
/// {@category Redirection}
class GoRoute extends RouteBase {
  /// Constructs a [GoRoute].
  /// - [path] and [name] cannot be empty strings.
  /// - One of either [builder] or [pageBuilder] must be provided.
  GoRoute({
    required this.path,
    this.name,
    this.builder,
    this.pageBuilder,
    this.parentNavigatorKey,
    this.redirect,
    super.routes = const <RouteBase>[],
  })  : assert(path.isNotEmpty, 'GoRoute path cannot be empty'),
        assert(name == null || name.isNotEmpty, 'GoRoute name cannot be empty'),
        assert(pageBuilder != null || builder != null || redirect != null,
            'builder, pageBuilder, or redirect must be provided'),
        super._() {
    // cache the path regexp and parameters
    _pathRE = patternToRegExp(path, pathParams);
  }

  /// Optional name of the route.
  ///
  /// If used, a unique string name must be provided and it can not be empty.
  ///
  /// This is used in [GoRouter.namedLocation] and its related API. This
  /// property can be used to navigate to this route without knowing exact the
  /// URI of it.
  ///
  /// {@tool snippet}
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// GoRoute(
  ///   name: 'home',
  ///   path: '/',
  ///   builder: (BuildContext context, GoRouterState state) =>
  ///       HomeScreen(),
  ///   routes: <GoRoute>[
  ///     GoRoute(
  ///       name: 'family',
  ///       path: 'family/:fid',
  ///       builder: (BuildContext context, GoRouterState state) =>
  ///           FamilyScreen(),
  ///     ),
  ///   ],
  /// );
  ///
  /// context.go(
  ///   context.namedLocation('family'),
  ///   params: <String, String>{'fid': 123},
  ///   queryParams: <String, String>{'qid': 'quid'},
  /// );
  /// ```
  ///
  /// See the [named routes example](https://github.com/flutter/packages/blob/main/packages/go_router/example/lib/named_routes.dart)
  /// for a complete runnable app.
  final String? name;

  /// The path of this go route.
  ///
  /// For example:
  /// ```
  /// GoRoute(
  ///   path: '/',
  ///   pageBuilder: (BuildContext context, GoRouterState state) => MaterialPage<void>(
  ///     key: state.pageKey,
  ///     child: HomePage(families: Families.data),
  ///   ),
  /// ),
  /// ```
  ///
  /// The path also support path parameters. For a path: `/family/:fid`, it
  /// matches all URIs start with `/family/...`, e.g. `/family/123`,
  /// `/family/456` and etc. The parameter values are stored in [GoRouterState]
  /// that are passed into [pageBuilder] and [builder].
  ///
  /// The query parameter are also capture during the route parsing and stored
  /// in [GoRouterState].
  ///
  /// See [Query parameters and path parameters](https://github.com/flutter/packages/blob/main/packages/go_router/example/lib/sub_routes.dart)
  /// to learn more about parameters.
  final String path;

  /// A page builder for this route.
  ///
  /// Typically a MaterialPage, as in:
  /// ```
  /// GoRoute(
  ///   path: '/',
  ///   pageBuilder: (BuildContext context, GoRouterState state) => MaterialPage<void>(
  ///     key: state.pageKey,
  ///     child: HomePage(families: Families.data),
  ///   ),
  /// ),
  /// ```
  ///
  /// You can also use CupertinoPage, and for a custom page builder to use
  /// custom page transitions, you can use [CustomTransitionPage].
  final GoRouterPageBuilder? pageBuilder;

  /// A custom builder for this route.
  ///
  /// For example:
  /// ```
  /// GoRoute(
  ///   path: '/',
  ///   builder: (BuildContext context, GoRouterState state) => FamilyPage(
  ///     families: Families.family(
  ///       state.params['id'],
  ///     ),
  ///   ),
  /// ),
  /// ```
  ///
  final GoRouterWidgetBuilder? builder;

  /// An optional redirect function for this route.
  ///
  /// In the case that you like to make a redirection decision for a specific
  /// route (or sub-route), consider doing so by passing a redirect function to
  /// the GoRoute constructor.
  ///
  /// For example:
  /// ```
  /// final GoRouter _router = GoRouter(
  ///   routes: <GoRoute>[
  ///     GoRoute(
  ///       path: '/',
  ///       redirect: (_) => '/family/${Families.data[0].id}',
  ///     ),
  ///     GoRoute(
  ///       path: '/family/:fid',
  ///       pageBuilder: (BuildContext context, GoRouterState state) => ...,
  ///     ),
  ///   ],
  /// );
  /// ```
  ///
  /// If there are multiple redirects in the matched routes, the parent route's
  /// redirect takes priority over sub-route's.
  ///
  /// For example:
  /// ```
  /// final GoRouter _router = GoRouter(
  ///   routes: <GoRoute>[
  ///     GoRoute(
  ///       path: '/',
  ///       redirect: (_) => '/page1', // this takes priority over the sub-route.
  ///       routes: <GoRoute>[
  ///         GoRoute(
  ///           path: 'child',
  ///           redirect: (_) => '/page2',
  ///         ),
  ///       ],
  ///     ),
  ///   ],
  /// );
  /// ```
  ///
  /// The `context.go('/child')` will be redirected to `/page1` instead of
  /// `/page2`.
  ///
  /// Redirect can also be used for conditionally preventing users from visiting
  /// routes, also known as route guards. One canonical example is user
  /// authentication. See [Redirection](https://github.com/flutter/packages/blob/main/packages/go_router/example/lib/redirection.dart)
  /// for a complete runnable example.
  ///
  /// If [BuildContext.dependOnInheritedWidgetOfExactType] is used during the
  /// redirection (which is how `of` method is usually implemented), a
  /// re-evaluation will be triggered if the [InheritedWidget] changes.
  final GoRouterRedirect? redirect;

  /// An optional key specifying which Navigator to display this route's screen
  /// onto.
  ///
  /// Specifying the root Navigator will stack this route onto that
  /// Navigator instead of the nearest ShellRoute ancestor.
  final GlobalKey<NavigatorState>? parentNavigatorKey;

  // TODO(chunhtai): move all regex related help methods to path_utils.dart.
  /// Match this route against a location.
  RegExpMatch? matchPatternAsPrefix(String loc) =>
      _pathRE.matchAsPrefix(loc) as RegExpMatch?;

  /// Extract the path parameters from a match.
  Map<String, String> extractPathParams(RegExpMatch match) =>
      extractPathParameters(pathParams, match);

  /// The path parameters in this route.
  @internal
  final List<String> pathParams = <String>[];

  @override
  String toString() {
    return 'GoRoute(name: $name, path: $path)';
  }

  late final RegExp _pathRE;
}

/// Base class for classes that act as shells for sub-routes, such
/// as [ShellRoute] and [StatefulShellRoute].
abstract class ShellRouteBase extends RouteBase {
  /// Constructs a [ShellRouteBase].
  const ShellRouteBase._({super.routes}) : super._();

  /// Attempts to build the Widget representing this shell route.
  ///
  /// Returns null if this shell route does not build a Widget, but instead uses
  /// a Page to represent itself (see [buildPage]).
  Widget? buildWidget(BuildContext context, GoRouterState state,
      ShellRouteContext shellRouteContext);

  /// Attempts to build the Page representing this shell route.
  ///
  /// Returns null if this shell route does not build a Page, but instead uses
  /// a Widget to represent itself (see [buildWidget]).
  Page<dynamic>? buildPage(BuildContext context, GoRouterState state,
      ShellRouteContext shellRouteContext);

  /// Returns the key for the [Navigator] that is to be used for the specified
  /// immediate sub-route of this shell route.
  GlobalKey<NavigatorState> navigatorKeyForSubRoute(RouteBase subRoute);
}

/// Context object used when building the shell and Navigator for a shell route.
class ShellRouteContext {
  /// Constructs a [ShellRouteContext].
  ShellRouteContext({
    required this.subRoute,
    required this.routeMatchList,
    required this.navigatorBuilder,
  });

  /// The current immediate sub-route of the associated shell route.
  final RouteBase subRoute;

  /// The route match list for the current route.
  final RouteMatchList routeMatchList;

  /// The navigator builder.
  final NavigatorBuilder navigatorBuilder;

  /// Builds the [Navigator] for the current route.
  Widget buildNavigator({
    List<NavigatorObserver>? observers,
    String? restorationScopeId,
  }) {
    return navigatorBuilder(
      observers,
      restorationScopeId,
    );
  }
}

/// A route that displays a UI shell around the matching child route.
///
/// When a ShellRoute is added to the list of routes on GoRouter or GoRoute, a
/// new Navigator is used to display any matching sub-routes instead of placing
/// them on the root Navigator.
///
/// To display a child route on a different Navigator, provide it with a
/// [parentNavigatorKey] that matches the key provided to either the [GoRouter]
/// or [ShellRoute] constructor. In this example, the _rootNavigator key is
/// passed to the /b/details route so that it displays on the root Navigator
/// instead of the ShellRoute's Navigator:
///
/// ```
/// final GlobalKey<NavigatorState> _rootNavigatorKey =
///     GlobalKey<NavigatorState>();
///
///   final GoRouter _router = GoRouter(
///     navigatorKey: _rootNavigatorKey,
///     initialLocation: '/a',
///     routes: [
///       ShellRoute(
///         navigatorKey: _shellNavigatorKey,
///         builder: (context, state, child) {
///           return ScaffoldWithNavBar(child: child);
///         },
///         routes: [
///           // This screen is displayed on the ShellRoute's Navigator.
///           GoRoute(
///             path: '/a',
///             builder: (context, state) {
///               return const ScreenA();
///             },
///             routes: <RouteBase>[
///               // This screen is displayed on the ShellRoute's Navigator.
///               GoRoute(
///                 path: 'details',
///                 builder: (BuildContext context, GoRouterState state) {
///                   return const DetailsScreen(label: 'A');
///                 },
///               ),
///             ],
///           ),
///           // Displayed ShellRoute's Navigator.
///           GoRoute(
///             path: '/b',
///             builder: (BuildContext context, GoRouterState state) {
///               return const ScreenB();
///             },
///             routes: <RouteBase>[
///               // Displayed on the root Navigator by specifying the
///               // [parentNavigatorKey].
///               GoRoute(
///                 path: 'details',
///                 parentNavigatorKey: _rootNavigatorKey,
///                 builder: (BuildContext context, GoRouterState state) {
///                   return const DetailsScreen(label: 'B');
///                 },
///               ),
///             ],
///           ),
///         ],
///       ),
///     ],
///   );
/// ```
///
/// The widget built by the matching sub-route becomes the child parameter
/// of the [builder].
///
/// For example:
///
/// ```
/// ShellRoute(
///   builder: (BuildContext context, GoRouterState state, Widget child) {
///     return Scaffold(
///       appBar: AppBar(
///         title: Text('App Shell')
///       ),
///       body: Center(
///         child: child,
///       ),
///     );
///   },
///   routes: [
///     GoRoute(
///       path: 'a'
///       builder: (BuildContext context, GoRouterState state) {
///         return Text('Child Route "/a"');
///       }
///     ),
///   ],
/// ),
/// ```
///
/// {@category Configuration}
class ShellRoute extends ShellRouteBase {
  /// Constructs a [ShellRoute].
  ShellRoute({
    this.builder,
    this.pageBuilder,
    this.observers,
    super.routes,
    GlobalKey<NavigatorState>? navigatorKey,
    this.restorationScopeId,
  })  : assert(routes.isNotEmpty),
        navigatorKey = navigatorKey ?? GlobalKey<NavigatorState>(),
        super._() {
    for (final RouteBase route in routes) {
      if (route is GoRoute) {
        assert(route.parentNavigatorKey == null ||
            route.parentNavigatorKey == navigatorKey);
      }
    }
  }

  /// The widget builder for a shell route.
  ///
  /// Similar to [GoRoute.builder], but with an additional child parameter. This
  /// child parameter is the Widget managing the nested navigation for the
  /// matching sub-routes. Typically, a shell route builds its shell around this
  /// Widget.
  final ShellRouteBuilder? builder;

  /// The page builder for a shell route.
  ///
  /// Similar to [GoRoute.pageBuilder], but with an additional child parameter.
  /// This child parameter is the Widget managing the nested navigation for the
  /// matching sub-routes. Typically, a shell route builds its shell around this
  /// Widget.
  final ShellRoutePageBuilder? pageBuilder;

  @override
  Widget? buildWidget(BuildContext context, GoRouterState state,
      ShellRouteContext shellRouteContext) {
    if (builder != null) {
      final Widget navigator = shellRouteContext.buildNavigator(
          observers: observers, restorationScopeId: restorationScopeId);
      return builder!(context, state, navigator);
    }
    return null;
  }

  @override
  Page<dynamic>? buildPage(BuildContext context, GoRouterState state,
      ShellRouteContext shellRouteContext) {
    if (pageBuilder != null) {
      final Widget navigator = shellRouteContext.buildNavigator(
          observers: observers, restorationScopeId: restorationScopeId);
      return pageBuilder!(context, state, navigator);
    }
    return null;
  }

  /// The observers for a shell route.
  ///
  /// The observers parameter is used by the [Navigator] built for this route.
  /// sub-route's observers.
  final List<NavigatorObserver>? observers;

  /// The [GlobalKey] to be used by the [Navigator] built for this route.
  /// All ShellRoutes build a Navigator by default. Child GoRoutes
  /// are placed onto this Navigator instead of the root Navigator.
  final GlobalKey<NavigatorState> navigatorKey;

  /// Restoration ID to save and restore the state of the navigator, including
  /// its history.
  final String? restorationScopeId;

  @override
  GlobalKey<NavigatorState> navigatorKeyForSubRoute(RouteBase subRoute) {
    assert(routes.contains(subRoute));
    return navigatorKey;
  }
}

/// A route that displays a UI shell with separate [Navigator]s for its
/// sub-routes.
///
/// Similar to [ShellRoute], this route class places its sub-route on a
/// different Navigator than the root Navigator. However, this route class
/// differs in that it creates separate Navigators for each of its nested
/// branches (i.e. parallel navigation trees), making it possible to build an
/// app with stateful nested navigation. This is convenient when for instance
/// implementing a UI with a [BottomNavigationBar], with a persistent navigation
/// state for each tab.
///
/// A StatefulShellRoute is created by specifying a List of
/// [StatefulShellBranch] items, each representing a separate stateful branch
/// in the route tree. StatefulShellBranch provides the root routes and the
/// Navigator key ([GlobalKey]) for the branch, as well as an optional initial
/// location.
///
/// Like [ShellRoute], either a [builder] or a [pageBuilder] must be provided
/// when creating a StatefulShellRoute. However, these builders differ slightly
/// in that they accept a [StatefulShellRouteState] parameter instead of a
/// GoRouterState. The StatefulShellRouteState can be used to access information
/// about the state of the route, as well as to switch the active branch (i.e.
/// restoring the navigation stack of another branch). The latter is
/// accomplished by using the method [StatefulShellRouteState.goBranch], for
/// example:
///
/// ```
/// void _onItemTapped(StatefulShellRouteState shellState, int index) {
///   shellState.goBranch(index: index);
/// }
/// ```
///
/// The final child parameter of the builders is a container Widget that manages
/// and maintains the state of the branch Navigators. Typically, a shell is
/// built around this Widget, for example by using it as the body of [Scaffold]
/// with a [BottomNavigationBar].
///
/// Sometimes greater control is needed over the layout and animations of the
/// Widgets representing the branch Navigators. In such cases, a custom
/// implementation can choose to ignore the child parameter of the builders and
/// instead create a [StatefulNavigationShell], which will manage the state
/// of the StatefulShellRoute. When creating this controller, a builder function
/// is provided to create the container Widget for the branch Navigators. See
/// [ShellNavigatorContainerBuilder] for more details.
///
/// Below is a simple example of how a router configuration with
/// StatefulShellRoute could be achieved. In this example, a
/// BottomNavigationBar with two tabs is used, and each of the tabs gets its
/// own Navigator. A container widget responsible for managing the Navigators
/// for all route branches will then be passed as the child argument
/// of the builder function.
///
/// ```
/// final GlobalKey<NavigatorState> _tabANavigatorKey =
///   GlobalKey<NavigatorState>(debugLabel: 'tabANavigator');
/// final GlobalKey<NavigatorState> _tabBNavigatorKey =
///   GlobalKey<NavigatorState>(debugLabel: 'tabBNavigator');
///
/// final GoRouter _router = GoRouter(
///   initialLocation: '/a',
///   routes: <RouteBase>[
///     StatefulShellRoute(
///       builder: (BuildContext context, StatefulShellRouteState state,
///             Widget child) {
///         return ScaffoldWithNavBar(shellState: state, body: child);
///       },
///       branches: [
///         /// The first branch, i.e. tab 'A'
///         StatefulShellBranch(
///           navigatorKey: _tabANavigatorKey,
///           routes: <RouteBase>[
///             GoRoute(
///               path: '/a',
///               builder: (BuildContext context, GoRouterState state) =>
///                   const RootScreen(label: 'A', detailsPath: '/a/details'),
///               routes: <RouteBase>[
///                 /// Will cover screen A but not the bottom navigation bar
///                 GoRoute(
///                   path: 'details',
///                   builder: (BuildContext context, GoRouterState state) =>
///                       const DetailsScreen(label: 'A'),
///                 ),
///               ],
///             ),
///           ],
///         ),
///         /// The second branch, i.e. tab 'B'
///         StatefulShellBranch(
///           navigatorKey: _tabBNavigatorKey,
///           routes: <RouteBase>[
///             GoRoute(
///               path: '/b',
///               builder: (BuildContext context, GoRouterState state) =>
///                   const RootScreen(label: 'B', detailsPath: '/b/details'),
///               routes: <RouteBase>[
///                 /// Will cover screen B but not the bottom navigation bar
///                 GoRoute(
///                   path: 'details',
///                   builder: (BuildContext context, GoRouterState state) =>
///                       const DetailsScreen(label: 'B'),
///                 ),
///               ],
///             ),
///           ],
///         ),
///       ],
///     ),
///   ],
/// );
/// ```
///
/// See [Stateful Nested Navigation](https://github.com/flutter/packages/blob/main/packages/go_router/example/lib/stateful_shell_route.dart)
/// for a complete runnable example using StatefulShellRoute.
class StatefulShellRoute extends ShellRouteBase {
  /// Constructs a [StatefulShellRoute] from a list of [StatefulShellBranch]es,
  /// each representing a separate nested navigation tree (branch).
  ///
  /// A separate [Navigator] will be created for each of the branches, using
  /// the navigator key specified in [StatefulShellBranch]. Note that unlike
  /// [ShellRoute], a builder must always be provided when creating a
  /// StatefulShellRoute. The pageBuilder however is optional, and is used
  /// in addition to the builder.
  StatefulShellRoute({
    required this.branches,
    this.builder,
    this.pageBuilder,
    this.restorationScopeId,
  })  : assert(branches.isNotEmpty),
        assert((pageBuilder != null) ^ (builder != null),
            'builder or pageBuilder must be provided'),
        assert(_debugUniqueNavigatorKeys(branches).length == branches.length,
            'Navigator keys must be unique'),
        assert(_debugValidateParentNavigatorKeys(branches)),
        assert(_debugValidateRestorationScopeIds(restorationScopeId, branches)),
        super._(routes: _routes(branches));

  /// Restoration ID to save and restore the state of the navigator, including
  /// its history.
  final String? restorationScopeId;

  /// The widget builder for a stateful shell route.
  ///
  /// Similar to [GoRoute.builder], but with an additional child parameter. This
  /// child parameter is the Widget managing the nested navigation for the
  /// matching sub-routes. Typically, a shell route builds its shell around this
  /// Widget.
  ///
  /// Instead of a GoRouterState, this builder function accepts a
  /// [StatefulShellRouteState] object, which can be used to access information
  /// about which branch is active, and also to navigate to a different branch
  /// (using [StatefulShellRouteState.goBranch]).
  ///
  /// Custom implementations may choose to ignore the child parameter passed to
  /// the builder function, and instead use [StatefulNavigationShell] to
  /// create a custom container for the branch Navigators.
  final StatefulShellRouteBuilder? builder;

  /// The page builder for a stateful shell route.
  ///
  /// Similar to [GoRoute.pageBuilder], but with an additional child parameter.
  /// This child parameter is the Widget managing the nested navigation for the
  /// matching sub-routes. Typically, a shell route builds its shell around this
  /// Widget.
  ///
  /// Instead of a GoRouterState, this builder function accepts a
  /// [StatefulShellRouteState] object, which can be used to access information
  /// about which branch is active, and also to navigate to a different branch
  /// (using [StatefulShellRouteState.goBranch]).
  ///
  /// Custom implementations may choose to ignore the child parameter passed to
  /// the builder function, and instead use [StatefulNavigationShell] to
  /// create a custom container for the branch Navigators.
  final StatefulShellRoutePageBuilder? pageBuilder;

  /// Representations of the different stateful route branches that this
  /// shell route will manage.
  ///
  /// Each branch uses a separate [Navigator], identified
  /// [StatefulShellBranch.navigatorKey].
  final List<StatefulShellBranch> branches;

  final GlobalKey<StatefulNavigationShellState> _shellStateKey =
      GlobalKey<StatefulNavigationShellState>();

  @override
  Widget? buildWidget(BuildContext context, GoRouterState state,
      ShellRouteContext shellRouteContext) {
    if (builder != null) {
      final StatefulNavigationShell shell =
          _createShell(context, state, shellRouteContext);
      return builder!(context, shell.shellRouteState, shell);
    }
    return null;
  }

  @override
  Page<dynamic>? buildPage(BuildContext context, GoRouterState state,
      ShellRouteContext shellRouteContext) {
    if (pageBuilder != null) {
      final StatefulNavigationShell shell =
          _createShell(context, state, shellRouteContext);
      return pageBuilder!(context, shell.shellRouteState, shell);
    }
    return null;
  }

  @override
  GlobalKey<NavigatorState> navigatorKeyForSubRoute(RouteBase subRoute) {
    final StatefulShellBranch? branch = branches.firstWhereOrNull(
        (StatefulShellBranch e) => e.routes.contains(subRoute));
    assert(branch != null);
    return branch!.navigatorKey;
  }

  StatefulNavigationShell _createShell(BuildContext context,
      GoRouterState state, ShellRouteContext shellRouteContext) {
    final GlobalKey<NavigatorState> navigatorKey =
        navigatorKeyForSubRoute(shellRouteContext.subRoute);
    final StatefulShellRouteState shellRouteState = StatefulShellRouteState._(
      GoRouter.of(context),
      this,
      _shellStateKey,
      state,
      navigatorKey,
      shellRouteContext,
    );
    return StatefulNavigationShell(shellRouteState: shellRouteState);
  }

  static List<RouteBase> _routes(List<StatefulShellBranch> branches) =>
      branches.expand((StatefulShellBranch e) => e.routes).toList();

  static Set<GlobalKey<NavigatorState>> _debugUniqueNavigatorKeys(
          List<StatefulShellBranch> branches) =>
      Set<GlobalKey<NavigatorState>>.from(
          branches.map((StatefulShellBranch e) => e.navigatorKey));

  static bool _debugValidateParentNavigatorKeys(
      List<StatefulShellBranch> branches) {
    for (final StatefulShellBranch branch in branches) {
      for (final RouteBase route in branch.routes) {
        if (route is GoRoute) {
          assert(route.parentNavigatorKey == null ||
              route.parentNavigatorKey == branch.navigatorKey);
        }
      }
    }
    return true;
  }

  static bool _debugValidateRestorationScopeIds(
      String? restorationScopeId, List<StatefulShellBranch> branches) {
    if (branches
        .map((StatefulShellBranch e) => e.restorationScopeId)
        .whereNotNull()
        .isNotEmpty) {
      assert(
          restorationScopeId != null,
          'A restorationScopeId must be set for '
          'the StatefulShellRoute when using restorationScopeIds on one or more '
          'of the branches');
    }
    return true;
  }
}

/// Representation of a separate branch in a stateful navigation tree, used to
/// configure [StatefulShellRoute].
///
/// The only required argument when creating a StatefulShellBranch is the
/// sub-routes ([routes]), however sometimes it may be convenient to also
/// provide a [initialLocation]. The value of this parameter is used when
/// loading the branch for the first time (for instance when switching branch
/// using the goBranch method in [StatefulShellRouteState]).
///
/// A separate [Navigator] will be built for each StatefulShellBranch in a
/// [StatefulShellRoute], and the routes of this branch will be placed onto that
/// Navigator instead of the root Navigator. A custom [navigatorKey] can be
/// provided when creating a StatefulShellBranch, which can be useful when the
/// Navigator needs to be accessed elsewhere. If no key is provided, a default
/// one will be created.
@immutable
class StatefulShellBranch {
  /// Constructs a [StatefulShellBranch].
  StatefulShellBranch({
    required this.routes,
    GlobalKey<NavigatorState>? navigatorKey,
    this.initialLocation,
    this.restorationScopeId,
    this.observers,
  }) : navigatorKey = navigatorKey ?? GlobalKey<NavigatorState>();

  /// The [GlobalKey] to be used by the [Navigator] built for this branch.
  ///
  /// A separate Navigator will be built for each StatefulShellBranch in a
  /// [StatefulShellRoute] and this key will be used to identify the Navigator.
  /// The routes associated with this branch will be placed o onto that
  /// Navigator instead of the root Navigator.
  final GlobalKey<NavigatorState> navigatorKey;

  /// The list of child routes associated with this route branch.
  final List<RouteBase> routes;

  /// The initial location for this route branch.
  ///
  /// If none is specified, the location of the first descendant [GoRoute] will
  /// be used (i.e. first element in [routes], or a descendant). The default
  /// location is used when loading the branch for the first time (for instance
  /// when switching branch using the goBranch method in
  /// [StatefulShellRouteState]).
  final String? initialLocation;

  /// Restoration ID to save and restore the state of the navigator, including
  /// its history.
  final String? restorationScopeId;

  /// The observers for this branch.
  ///
  /// The observers parameter is used by the [Navigator] built for this branch.
  final List<NavigatorObserver>? observers;
}

/// Builder for a custom container for shell route Navigators.
typedef ShellNavigatorContainerBuilder = Widget Function(BuildContext context,
    StatefulShellRouteState shellRouteState, List<Widget> children);

/// Widget for managing the state of a [StatefulShellRoute].
///
/// Normally, this widget is not used directly, but is instead created
/// internally by StatefulShellRoute. However, if a custom container for the
/// branch Navigators is required, StatefulNavigationShell can be used in
/// the builder or pageBuilder methods of StatefulShellRoute to facilitate this.
/// The container is created using the provided [ShellNavigatorContainerBuilder],
/// where the List of Widgets represent the Navigators for each branch.
///
/// Example:
/// ```
/// builder: (BuildContext context, StatefulShellRouteState state, Widget child) {
///   return StatefulNavigationShell(
///     shellRouteState: state,
///     containerBuilder: (_, __, List<Widget> children) => MyCustomShell(shellState: state, children: children),
///   );
/// }
/// ```
class StatefulNavigationShell extends StatefulWidget {
  /// Constructs an [_StatefulNavigationShell].
  StatefulNavigationShell({
    required this.shellRouteState,
    ShellNavigatorContainerBuilder? containerBuilder,
  })  : containerBuilder = containerBuilder ?? _defaultChildBuilder,
        super(key: shellRouteState._shellStateKey);

  static Widget _defaultChildBuilder(BuildContext context,
      StatefulShellRouteState shellRouteState, List<Widget> children) {
    return _IndexedStackedRouteBranchContainer(
        currentIndex: shellRouteState.currentIndex, children: children);
  }

  /// The current state of the associated [StatefulShellRoute].
  final StatefulShellRouteState shellRouteState;

  /// The builder for a custom container for shell route Navigators.
  final ShellNavigatorContainerBuilder containerBuilder;

  @override
  State<StatefulWidget> createState() => StatefulNavigationShellState();
}

/// State for StatefulNavigationShell.
class StatefulNavigationShellState extends State<StatefulNavigationShell>
    with RestorationMixin {
  final Map<Key, Widget> _branchNavigators = <Key, Widget>{};

  StatefulShellRoute get _route => widget.shellRouteState.route;

  StatefulShellRouteState get _routeState => widget.shellRouteState;

  GoRouter get _router => _routeState._router;
  RouteMatcher get _matcher => _router.routeInformationParser.matcher;
  GoRouteInformationProvider get _routeInformationProvider =>
      _router.routeInformationProvider;

  final Map<StatefulShellBranch, _RestorableRouteMatchList> _branchLocations =
      <StatefulShellBranch, _RestorableRouteMatchList>{};

  @override
  String? get restorationId => _route.restorationScopeId;

  /// Generates a derived restoration ID for the branch location property,
  /// falling back to the identity hash code of the branch to ensure an ID is
  /// always returned (needed for _RestorableRouteMatchList/RestorableValue).
  String _branchLocationRestorationScopeId(StatefulShellBranch branch) {
    return branch.restorationScopeId != null
        ? '${branch.restorationScopeId}-location'
        : identityHashCode(branch).toString();
  }

  _RestorableRouteMatchList _branchLocation(StatefulShellBranch branch) {
    return _branchLocations.putIfAbsent(branch, () {
      final _RestorableRouteMatchList branchLocation =
          _RestorableRouteMatchList(_matcher);
      registerForRestoration(
          branchLocation, _branchLocationRestorationScopeId(branch));
      return branchLocation;
    });
  }

  Widget? _navigatorForBranch(StatefulShellBranch branch) {
    return _branchNavigators[branch.navigatorKey];
  }

  void _setNavigatorForBranch(StatefulShellBranch branch, Widget? navigator) {
    navigator != null
        ? _branchNavigators[branch.navigatorKey] = navigator
        : _branchNavigators.remove(branch.navigatorKey);
  }

  RouteMatchList? _matchListForBranch(int index) =>
      _branchLocations[_route.branches[index]]?.value;

  void _updateCurrentBranchStateFromWidget() {
    final StatefulShellBranch branch =
        _route.branches[_routeState.currentIndex];
    final ShellRouteContext shellRouteContext = _routeState._shellRouteContext;

    /// Create an clone of the current RouteMatchList, to prevent mutations from
    /// affecting the copy saved as the current state for this branch.
    final RouteMatchList currentBranchLocation =
        shellRouteContext.routeMatchList.clone();

    final _RestorableRouteMatchList branchLocation = _branchLocation(branch);
    final RouteMatchList previousBranchLocation = branchLocation.value;
    branchLocation.value = currentBranchLocation;
    final bool hasExistingNavigator = _navigatorForBranch(branch) != null;

    /// Only update the Navigator of the route match list has changed
    final bool locationChanged = !RouteMatchList.matchListEquals(
        previousBranchLocation, currentBranchLocation);
    if (locationChanged || !hasExistingNavigator) {
      final Widget currentNavigator = shellRouteContext.buildNavigator(
        observers: branch.observers,
        restorationScopeId: branch.restorationScopeId,
      );
      _setNavigatorForBranch(branch, currentNavigator);
    }
  }

  void _goBranch(int index) {
    assert(index >= 0 && index < _route.branches.length);
    final RouteMatchList? matchlist = _matchListForBranch(index);
    if (matchlist != null && matchlist.isNotEmpty) {
      _routeInformationProvider.value = matchlist.toPreParsedRouteInformation();
    } else {
      _router.go(_routeState._effectiveInitialBranchLocation(index));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateCurrentBranchStateFromWidget();
  }

  @override
  void dispose() {
    super.dispose();
    for (final StatefulShellBranch branch in _route.branches) {
      _branchLocations[branch]?.dispose();
    }
  }

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    _route.branches.forEach(_branchLocation);
  }

  @override
  void didUpdateWidget(covariant StatefulNavigationShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateCurrentBranchStateFromWidget();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = _route.branches
        .map((StatefulShellBranch branch) => _BranchNavigatorProxy(
            key: ObjectKey(branch),
            branch: branch,
            navigatorForBranch: _navigatorForBranch))
        .toList();
    return widget.containerBuilder(context, _routeState, children);
  }
}

/// [RestorableProperty] for enabling state restoration of [RouteMatchList]s.
class _RestorableRouteMatchList extends RestorableValue<RouteMatchList> {
  _RestorableRouteMatchList(RouteMatcher matcher)
      : _matchListCodec = RouteMatchListCodec(matcher);

  final RouteMatchListCodec _matchListCodec;

  @override
  RouteMatchList createDefaultValue() => RouteMatchList.empty;

  @override
  void didUpdateValue(RouteMatchList? oldValue) {
    notifyListeners();
  }

  @override
  RouteMatchList fromPrimitives(Object? data) {
    return _matchListCodec.decodeMatchList(data) ?? RouteMatchList.empty;
  }

  @override
  Object? toPrimitives() {
    if (value != null && value.isNotEmpty) {
      return _matchListCodec.encodeMatchList(value);
    }
    return null;
  }
}

typedef _NavigatorForBranch = Widget? Function(StatefulShellBranch);

/// Widget that serves as the proxy for a branch Navigator Widget, which
/// possibly hasn't been created yet.
///
/// This Widget hides the logic handling whether a Navigator Widget has been
/// created yet for a branch or not, and at the same time ensures that the same
/// Widget class is consistently passed to the containerBuilder. The latter is
/// important for container implementations that cache child widgets,
/// such as [TabBarView].
class _BranchNavigatorProxy extends StatefulWidget {
  const _BranchNavigatorProxy({
    super.key,
    required this.branch,
    required this.navigatorForBranch,
  });

  final StatefulShellBranch branch;
  final _NavigatorForBranch navigatorForBranch;

  @override
  State<StatefulWidget> createState() => _BranchNavigatorProxyState();
}

/// State for _BranchNavigatorProxy, using AutomaticKeepAliveClientMixin to
/// properly handle some scenarios where Slivers are used to manage the branches
/// (such as [TabBarView]).
class _BranchNavigatorProxyState extends State<_BranchNavigatorProxy>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.navigatorForBranch(widget.branch) ?? const SizedBox.shrink();
  }

  @override
  bool get wantKeepAlive => true;
}

/// Default implementation of a container widget for the [Navigator]s of the
/// route branches. This implementation uses an [IndexedStack] as a container.
class _IndexedStackedRouteBranchContainer extends StatelessWidget {
  const _IndexedStackedRouteBranchContainer(
      {required this.currentIndex, required this.children});

  final int currentIndex;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final List<Widget> stackItems = children
        .mapIndexed((int index, Widget child) =>
            _buildRouteBranchContainer(context, currentIndex == index, child))
        .toList();

    return IndexedStack(index: currentIndex, children: stackItems);
  }

  Widget _buildRouteBranchContainer(
      BuildContext context, bool isActive, Widget child) {
    return Offstage(
      offstage: !isActive,
      child: TickerMode(
        enabled: isActive,
        child: child,
      ),
    );
  }
}

/// The snapshot of the current state of a [StatefulShellRoute].
///
/// Note that this an immutable class, that represents the snapshot of the state
/// of a StatefulShellRoute at a given point in time. Therefore, instances of
/// this object should not be cached, but instead passed down from the builder
/// functions of StatefulShellRoute.
@immutable
class StatefulShellRouteState {
  /// Constructs a [_StatefulShellRouteState].
  StatefulShellRouteState._(
    this._router,
    this.route,
    this._shellStateKey,
    this.routerState,
    GlobalKey<NavigatorState> currentNavigatorKey,
    this._shellRouteContext,
  ) : currentIndex = _indexOfBranchNavigatorKey(route, currentNavigatorKey);

  static int _indexOfBranchNavigatorKey(
      StatefulShellRoute route, GlobalKey<NavigatorState> navigatorKey) {
    final int index = route.branches.indexWhere(
        (StatefulShellBranch branch) => branch.navigatorKey == navigatorKey);
    assert(index >= 0);
    return index;
  }

  final GoRouter _router;

  /// The associated [StatefulShellRoute]
  final StatefulShellRoute route;

  final GlobalKey<StatefulNavigationShellState> _shellStateKey;

  /// The current route state associated with the [StatefulShellRoute].
  final GoRouterState routerState;

  /// The ShellRouteContext responsible for building the Navigator for the
  /// current [StatefulShellBranch]
  final ShellRouteContext _shellRouteContext;

  /// The index of the currently active [StatefulShellBranch].
  ///
  /// Corresponds to the index of the branch in the List returned from
  /// branchBuilder of [StatefulShellRoute].
  final int currentIndex;

  /// Navigate to the last location of the [StatefulShellBranch] at the provided
  /// index in the associated [StatefulShellBranch].
  ///
  /// This method will switch the currently active branch [Navigator] for the
  /// [StatefulShellRoute]. If the branch has not been visited before, this
  /// method will navigate to initial location of the branch (see
  /// [StatefulShellBranch.initialLocation]).
  void goBranch({required int index}) {
    final StatefulNavigationShellState? shellState =
        _shellStateKey.currentState;
    if (shellState != null) {
      shellState._goBranch(index);
    } else {
      assert(_router != null);
      _router.go(_effectiveInitialBranchLocation(index));
    }
  }

  String _effectiveInitialBranchLocation(int index) {
    return _router.routeInformationParser.configuration
        .effectiveInitialBranchLocation(route.branches[index]);
  }

  /// Gets the state for the nearest stateful shell route in the Widget tree.
  static StatefulShellRouteState of(BuildContext context) {
    final StatefulNavigationShellState? shellState =
        context.findAncestorStateOfType<StatefulNavigationShellState>();
    assert(shellState != null);
    return shellState!._routeState;
  }

  /// Gets the state for the nearest stateful shell route in the Widget tree.
  ///
  /// Returns null if no stateful shell route is found.
  static StatefulShellRouteState? maybeOf(BuildContext context) {
    final StatefulNavigationShellState? shellState =
        context.findAncestorStateOfType<StatefulNavigationShellState>();
    return shellState?._routeState;
  }
}
