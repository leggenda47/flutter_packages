// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'configuration.dart';
import 'delegate.dart';
import 'match.dart';
import 'path_utils.dart';

/// Converts a location into a list of [RouteMatch] objects.
class RouteMatcher {
  /// [RouteMatcher] constructor.
  RouteMatcher(this.configuration);

  /// The route configuration.
  final RouteConfiguration configuration;

  /// Finds the routes that matched the given URL.
  RouteMatchList findMatch(String location, {Object? extra}) {
    final Uri uri = Uri.parse(canonicalUri(location));

    final Map<String, String> pathParameters = <String, String>{};
    final List<RouteMatch> matches =
        _getLocRouteMatches(uri, extra, pathParameters);
    return RouteMatchList(matches, uri, pathParameters);
  }

  List<RouteMatch> _getLocRouteMatches(
      Uri uri, Object? extra, Map<String, String> pathParameters) {
    final List<RouteMatch>? result = _getLocRouteRecursively(
      loc: uri.path,
      restLoc: uri.path,
      routes: configuration.routes,
      parentSubloc: '',
      pathParameters: pathParameters,
      extra: extra,
    );

    if (result == null) {
      throw MatcherError('no routes for location', uri.toString());
    }

    return result;
  }
}

/// The list of [RouteMatch] objects.
///
/// This corresponds to the GoRouter's history.
class RouteMatchList {
  /// RouteMatchList constructor.
  RouteMatchList(List<RouteMatch> matches, this._uri, this.pathParameters)
      : _matches = matches,
        fullpath = _generateFullPath(matches);

  RouteMatchList._(
      this._matches, this._uri, this.pathParameters, this.fullpath);

  /// Creates a copy of this RouteMatchList that can be modified without
  /// affecting the original.
  RouteMatchList clone() {
    return RouteMatchList._(List<RouteMatch>.from(_matches), _uri,
        Map<String, String>.from(pathParameters), fullpath);
  }

  /// Constructs an empty matches object.
  static RouteMatchList empty = RouteMatchList(
      const <RouteMatch>[], Uri.parse(''), const <String, String>{});

  /// Generates the full path (ex: `'/family/:fid/person/:pid'`) of a list of
  /// [RouteMatch].
  ///
  /// This methods considers that [matches]'s elements verify the go route
  /// structure given to `GoRouter`. For example, if the routes structure is
  ///
  /// ```dart
  /// GoRoute(
  ///   path: '/a',
  ///   routes: [
  ///     GoRoute(
  ///       path: 'b',
  ///       routes: [
  ///         GoRoute(
  ///           path: 'c',
  ///         ),
  ///       ],
  ///     ),
  ///   ],
  /// ),
  /// ```
  ///
  /// The [matches] must be the in same order of how GoRoutes are matched.
  ///
  /// ```dart
  /// [RouteMatchA(), RouteMatchB(), RouteMatchC()]
  /// ```
  static String _generateFullPath(Iterable<RouteMatch> matches) {
    final StringBuffer buffer = StringBuffer();
    bool addsSlash = false;
    for (final RouteMatch match in matches) {
      final RouteBase route = match.route;
      if (route is GoRoute) {
        if (addsSlash) {
          buffer.write('/');
        }
        buffer.write(route.path);
        addsSlash = addsSlash || route.path != '/';
      }
    }
    return buffer.toString();
  }

  final List<RouteMatch> _matches;

  /// the full path pattern that matches the uri.
  ///
  /// For example:
  ///
  /// ```dart
  /// '/family/:fid/person/:pid'
  /// ```
  final String fullpath;

  /// Parameters for the matched route, URI-encoded.
  final Map<String, String> pathParameters;

  /// The uri of the current match.
  Uri get uri => _uri;
  Uri _uri;

  /// Returns true if there are no matches.
  bool get isEmpty => _matches.isEmpty;

  /// Returns true if there are matches.
  bool get isNotEmpty => _matches.isNotEmpty;

  /// Pushes a match onto the list of matches.
  void push(RouteMatch match) {
    _matches.add(match);
  }

  /// Removes the match from the list.
  void remove(RouteMatch match) {
    final int index = _matches.indexOf(match);
    assert(index != -1);
    _matches.removeRange(index, _matches.length);

    // Also pop ShellRoutes when there are no subsequent route matches
    while (_matches.isNotEmpty && _matches.last.route is ShellRouteBase) {
      _matches.removeLast();
    }

    final String fullPath = _generateFullPath(
        _matches.where((RouteMatch match) => match is! ImperativeRouteMatch));
    // Need to remove path parameters that are no longer in the fullPath.
    final List<String> newParameters = <String>[];
    patternToRegExp(fullPath, newParameters);
    final Set<String> validParameters = newParameters.toSet();
    pathParameters.removeWhere(
        (String key, String value) => !validParameters.contains(key));

    _uri = _uri.replace(path: patternToPath(fullPath, pathParameters));
  }

  /// An optional object provided by the app during navigation.
  Object? get extra => _matches.isEmpty ? null : _matches.last.extra;

  /// The last matching route.
  RouteMatch get last => _matches.last;

  /// The route matches.
  List<RouteMatch> get matches => _matches;

  /// Returns true if the current match intends to display an error screen.
  bool get isError => matches.length == 1 && matches.first.error != null;

  /// Returns the error that this match intends to display.
  Exception? get error => matches.firstOrNull?.error;

  @override
  String toString() {
    return '${objectRuntimeType(this, 'RouteMatchList')}($fullpath)';
  }

  /// Returns a pre-parsed [RouteInformation], containing a reference to this
  /// match list.
  RouteInformation toPreParsedRouteInformation() {
    return RouteInformation(
      location: uri.toString(),
      state: this,
    );
  }

  /// Attempts to extract a pre-parsed match list from the provided
  /// [RouteInformation].
  static RouteMatchList? fromPreParsedRouteInformation(
      RouteInformation routeInformation) {
    if (routeInformation.state is RouteMatchList) {
      return routeInformation.state! as RouteMatchList;
    }
    return null;
  }

  /// Performs a deep comparison of two match lists by comparing the fields
  /// of each object.
  ///
  /// Note that the == and hashCode functions are not overridden by
  /// RouteMatchList because it is mutable.
  static bool matchListEquals(RouteMatchList a, RouteMatchList b) {
    if (identical(a, b)) {
      return true;
    }
    return listEquals<RouteMatch>(a.matches, b.matches) &&
        a.uri == b.uri &&
        mapEquals<String, String>(a.pathParameters, b.pathParameters);
  }
}

/// Handles encoding and decoding of [RouteMatchList] objects to a format
/// suitable for using with [StandardMessageCodec].
///
/// The primary use of this class is for state restoration.
class RouteMatchListCodec {
  /// Creates a new [RouteMatchListCodec] object.
  RouteMatchListCodec(this._matcher);

  static const String _encodedDataKey = 'go_router/encoded_route_match_list';
  static const String _locationKey = 'location';
  static const String _stateKey = 'state';
  static const String _imperativeMatchesKey = 'imperativeMatches';
  static const String _pageKey = 'pageKey';

  final RouteMatcher _matcher;

  /// Encodes the provided [RouteMatchList].
  Object? encodeMatchList(RouteMatchList matchlist) {
    if (matchlist.isEmpty) {
      return null;
    }
    final List<Map<Object?, Object?>> imperativeMatches = matchlist.matches
        .whereType<ImperativeRouteMatch<Object?>>()
        .map((ImperativeRouteMatch<Object?> e) => _toPrimitives(
            e.matches.uri.toString(), e.extra,
            pageKey: e.pageKey.value))
        .toList();

    return <Object?, Object?>{
      _encodedDataKey: _toPrimitives(
          matchlist.uri.toString(), matchlist.matches.first.extra,
          imperativeMatches: imperativeMatches),
    };
  }

  static Map<Object?, Object?> _toPrimitives(String location, Object? state,
      {List<dynamic>? imperativeMatches, String? pageKey}) {
    return <Object?, Object?>{
      _locationKey: location,
      _stateKey: state,
      if (imperativeMatches != null) _imperativeMatchesKey: imperativeMatches,
      if (pageKey != null) _pageKey: pageKey,
    };
  }

  /// Attempts to decode the provided object into a [RouteMatchList].
  RouteMatchList? decodeMatchList(Object? object) {
    if (object is Map && object[_encodedDataKey] is Map) {
      final Map<Object?, Object?> data =
          object[_encodedDataKey] as Map<Object?, Object?>;
      final Object? rootLocation = data[_locationKey];
      if (rootLocation is! String) {
        return null;
      }
      final RouteMatchList matchList =
          _matcher.findMatch(rootLocation, extra: data[_stateKey]);

      final List<Object?>? imperativeMatches =
          data[_imperativeMatchesKey] as List<Object?>?;
      if (imperativeMatches != null) {
        for (int i = 0; i < imperativeMatches.length; i++) {
          final Object? match = imperativeMatches[i];
          if (match is! Map ||
              match[_locationKey] is! String ||
              match[_pageKey] is! String) {
            continue;
          }
          final ValueKey<String> pageKey =
              ValueKey<String>(match[_pageKey] as String);
          final RouteMatchList imperativeMatchList = _matcher.findMatch(
              match[_locationKey] as String,
              extra: match[_stateKey]);
          final ImperativeRouteMatch<Object?> imperativeMatch = ImperativeRouteMatch<Object?>(
            pageKey: pageKey,
            matches: imperativeMatchList,
          );
          matchList.push(imperativeMatch);
        }
      }

      return matchList;
    }
    return null;
  }
}

/// An error that occurred during matching.
class MatcherError extends Error {
  /// Constructs a [MatcherError].
  MatcherError(String message, this.location) : message = '$message: $location';

  /// The error message.
  final String message;

  /// The location that failed to match.
  final String location;

  @override
  String toString() {
    return message;
  }
}

/// Returns the list of `RouteMatch` corresponding to the given `loc`.
///
/// For example, for a given `loc` `/a/b/c/d`, this function will return the
/// list of [RouteBase] `[GoRouteA(), GoRouterB(), GoRouteC(), GoRouterD()]`.
///
/// - [loc] is the complete URL to match (without the query parameters). For
///   example, for the URL `/a/b?c=0`, [loc] will be `/a/b`.
/// - [restLoc] is the remaining part of the URL to match while [parentSubloc]
///   is the part of the URL that has already been matched. For examples, for
///   the URL `/a/b/c/d`, at some point, [restLoc] would be `/c/d` and
///   [parentSubloc] will be `/a/b`.
/// - [routes] are the possible [RouteBase] to match to [restLoc].
List<RouteMatch>? _getLocRouteRecursively({
  required String loc,
  required String restLoc,
  required String parentSubloc,
  required List<RouteBase> routes,
  required Map<String, String> pathParameters,
  required Object? extra,
}) {
  List<RouteMatch>? result;
  late Map<String, String> subPathParameters;
  // find the set of matches at this level of the tree
  for (final RouteBase route in routes) {
    subPathParameters = <String, String>{};

    final RouteMatch? match = RouteMatch.match(
      route: route,
      restLoc: restLoc,
      parentSubloc: parentSubloc,
      pathParameters: subPathParameters,
      extra: extra,
    );

    if (match == null) {
      continue;
    }

    if (match.route is GoRoute &&
        match.subloc.toLowerCase() == loc.toLowerCase()) {
      // If it is a complete match, then return the matched route
      // NOTE: need a lower case match because subloc is canonicalized to match
      // the path case whereas the location can be of any case and still match
      result = <RouteMatch>[match];
    } else if (route.routes.isEmpty) {
      // If it is partial match but no sub-routes, bail.
      continue;
    } else {
      // Otherwise, recurse
      final String childRestLoc;
      final String newParentSubLoc;
      if (match.route is ShellRouteBase) {
        childRestLoc = restLoc;
        newParentSubLoc = parentSubloc;
      } else {
        assert(loc.startsWith(match.subloc));
        assert(restLoc.isNotEmpty);

        childRestLoc =
            loc.substring(match.subloc.length + (match.subloc == '/' ? 0 : 1));
        newParentSubLoc = match.subloc;
      }

      final List<RouteMatch>? subRouteMatch = _getLocRouteRecursively(
        loc: loc,
        restLoc: childRestLoc,
        parentSubloc: newParentSubLoc,
        routes: route.routes,
        pathParameters: subPathParameters,
        extra: extra,
      );

      // If there's no sub-route matches, there is no match for this location
      if (subRouteMatch == null) {
        continue;
      }
      result = <RouteMatch>[match, ...subRouteMatch];
    }
    // Should only reach here if there is a match.
    break;
  }
  if (result != null) {
    pathParameters.addAll(subPathParameters);
  }
  return result;
}

/// The match used when there is an error during parsing.
RouteMatchList errorScreen(Uri uri, String errorMessage) {
  final Exception error = Exception(errorMessage);
  return RouteMatchList(
      <RouteMatch>[
        RouteMatch(
          subloc: uri.path,
          extra: null,
          error: error,
          route: GoRoute(
            path: uri.toString(),
            pageBuilder: (BuildContext context, GoRouterState state) {
              throw UnimplementedError();
            },
          ),
          pageKey: const ValueKey<String>('error'),
        ),
      ],
      uri,
      const <String, String>{});
}
