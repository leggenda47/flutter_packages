# go_router

A declarative routing package for Flutter that uses the Router API to provide a
convenient, url-based API for navigating between different screens. You can
define URL patterns, navigate using a URL, handle deep links, and a number of
other navigation-related scenarios.

# go_router_flow

This package was created for [SportsVisio's](https://sportsvisio.com/) apps, and it's currently in use and tested, and it'll be updated until the day go_router implements it.

This is a fork of the go_router package that let's you communicate between pages by returning values on pop like in navigator 1.0. This was implemented by adding completers in the routes and waiting for the values when requested.

## Returning values

This is the reason for this package, to be able to return stuff when a screens pop.

Waiting for a value to be returned:

```dart
onTap: () {
  // In the new page you can do 'context.pop<bool>(someValue)' to return a value.
  final bool? result = await context.push<bool>('/page2');

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if(result ?? false)...
  });
}
```

Returning a value:

```dart
onTap: () => context.pop(true)
```

## Features

GoRouter has a number of features to make navigation straightforward:

- Parsing path and query parameters using a template syntax (for example, "user/:id')
- Displaying multiple screens for a destination (sub-routes)
- Redirection support - you can re-route the user to a different URL based on
  application state, for example to a sign-in when the user is not
  authenticated
- Support for multiple Navigators via
  [ShellRoute](https://pub.dev/documentation/go_router/latest/go_router/ShellRoute-class.html) -
  you can display an inner Navigator that displays its own pages based on the
  matched route. For example, to display a BottomNavigationBar that stays
  visible at the bottom of the
  screen
- Support for both Material and Cupertino apps
- Backwards-compatibility with Navigator API

## Documentation

See the API documentation for details on the following topics:
Follow the [package install instructions](https://pub.dev/packages/go_router_flow/install),
and you can start using go_router_flow in your app:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

void main() => runApp(App());

class App extends StatelessWidget {
  App({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
      title: 'GoRouter Example',
    );
  }

  final GoRouter _router = GoRouter(
    routes: <GoRoute>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) {
          return ScreenA();
        },
      ),
      GoRoute(
        path: '/b',
        builder: (BuildContext context, GoRouterState state) {
          return ScreenB();
        },
      ),
    ],
  );
}
```

## Define Routes

go_router is governed by a set of routes which are specified as part of the
[GoRouter](https://pub.dev/documentation/go_router/latest/go_router/GoRouter-class.html)
constructor:

```dart
GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const Page1Screen(),
    ),
    GoRoute(
      path: '/page2',
      builder: (context, state) => const Page2Screen(),
    ),
  ],
);
```

In the above snippet, two routes are defined, `/` and `/page2`.
When the URL changes, it is matched against each route path.
The path is matched in a case-insensitive way, but the case for
parameters is preserved. If there are multiple route matches,
the **first match** in the list takes priority over the others.

The [builder](https://pub.dev/documentation/go_router/latest/go_router/GoRoute/builder.html)
is responsible for building the `Widget` to display on screen.
Alternatively, you can use `pageBuilder` to customize the transition
animation when that route becomes active.
The default transition is used between pages
depending on the app at the top of its widget tree, e.g. the use of `MaterialApp`
will cause go_router to use the `MaterialPage` transitions. Consider using
[pageBuilder](https://pub.dev/documentation/go_router/latest/go_router/GoRoute/pageBuilder.html)
for custom `Page` class.

## Initialization

Create a [GoRouter](https://pub.dev/documentation/go_router/latest/go_router/GoRouter-class.html)
object and initialize your `MaterialApp` or `CupertinoApp`:

```dart
final GoRouter _router = GoRouter(
  routes: <GoRoute>[
     // ...
  ]
);

MaterialApp.router(
  routerConfig: _router,
);
```

## Error handling

By default, go_router comes with default error screens for both `MaterialApp` and
`CupertinoApp` as well as a default error screen in the case that none is used.
Once can also replace the default error screen by using the [errorBuilder](https://pub.dev/documentation/go_router/latest/go_router/GoRouter/GoRouter.html):

```dart
GoRouter(
  ...
  errorBuilder: (context, state) => ErrorScreen(state.error),
);
```

## Redirection

You can use redirection to prevent the user from visiting a specific page. In
go_router, redirection can be asynchronous.

```dart
GoRouter(
  ...
  redirect: (context, state) async {
    if (await LoginService.of(context).isLoggedIn) {
      return state.location;
    }
    return '/login';
  },
);
```

If the code depends on [BuildContext](https://api.flutter.dev/flutter/widgets/BuildContext-class.html)
through the [dependOnInheritedWidgetOfExactType](https://api.flutter.dev/flutter/widgets/BuildContext/dependOnInheritedWidgetOfExactType.html)
(which is how `of` methods are usually implemented), the redirect will be called every time the [InheritedWidget](https://api.flutter.dev/flutter/widgets/InheritedWidget-class.html)
updated.

### Top-level redirect

The [GoRouter.redirect](https://pub.dev/documentation/go_router/latest/go_router/GoRouter-class.html)
is always called for every navigation regardless of which GoRoute was matched. The
top-level redirect always takes priority over route-level redirect.

### Route-level redirect

If the top-level redirect does not redirect to a different location,
the [GoRoute.redirect](https://pub.dev/documentation/go_router/latest/go_router/GoRoute/redirect.html)
is then called if the route has matched the GoRoute. If there are multiple
GoRoute matches, e.g. GoRoute with sub-routes, the parent route redirect takes
priority over sub-routes' redirect.

## Navigation

To navigate between routes, use the [GoRouter.go](https://pub.dev/documentation/go_router/latest/go_router/GoRouter/go.html) method:

```dart
onTap: () => GoRouter.of(context).go('/page2')
```

go_router also provides a more concise way to navigate using Dart extension
methods:

```dart
onTap: () => context.go('/page2')
```

## Nested Navigation

The `ShellRoute` route type provides a way to wrap all sub-routes with a UI shell.
Under the hood, GoRouter places a Navigator in the widget tree, which is used
to display matching sub-routes:

```dart
final  _router = GoRouter(
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        return AppScaffold(child: child);
      },
      routes: <RouteBase>[
        GoRoute(
          path: '/albums',
          builder: (context, state) {
            return HomeScreen();
          },
          routes: <RouteBase>[
            /// The details screen to display stacked on the inner Navigator.
            GoRoute(
              path: 'song/:songId',
              builder: (BuildContext context, GoRouterState state) {
                return const DetailsScreen(label: 'A');
              },
            ),
          ],
        ),
      ],
    ),
  ],
);
```

For more details, see the
[ShellRoute](https://pub.dev/documentation/go_router/latest/go_router/ShellRoute-class.html)
API documentation. For a complete
example, see the
[ShellRoute sample](https://github.com/flutter/packages/tree/main/packages/go_router/example/lib/shell_route.dart)
in the example/ directory.

### Still not sure how to proceed?

See [examples](https://github.com/flutter/packages/tree/main/packages/go_router/example) for complete runnable examples or visit [API documentation](https://pub.dev/documentation/go_router/latest/go_router/go_router-library.html)

- [Getting started](https://pub.dev/documentation/go_router/latest/topics/Get%20started-topic.html)
- [Upgrade an existing app](https://pub.dev/documentation/go_router/latest/topics/Upgrading-topic.html)
- [Configuration](https://pub.dev/documentation/go_router/latest/topics/Configuration-topic.html)
- [Navigation](https://pub.dev/documentation/go_router/latest/topics/Navigation-topic.html)
- [Redirection](https://pub.dev/documentation/go_router/latest/topics/Redirection-topic.html)
- [Web](https://pub.dev/documentation/go_router/latest/topics/Web-topic.html)
- [Deep linking](https://pub.dev/documentation/go_router/latest/topics/Deep%20linking-topic.html)
- [Transition animations](https://pub.dev/documentation/go_router/latest/topics/Transition%20animations-topic.html)
- [Type-safe routes](https://pub.dev/documentation/go_router/latest/topics/Type-safe%20routes-topic.html)
- [Named routes](https://pub.dev/documentation/go_router/latest/topics/Named%20routes-topic.html)
- [Error handling](https://pub.dev/documentation/go_router/latest/topics/Error%20handling-topic.html)

## Migration guides

- [Migrating to 5.1.2](https://flutter.dev/go/go-router-v5-1-2-breaking-changes)
- [Migrating to 5.0](https://flutter.dev/go/go-router-v5-breaking-changes)
- [Migrating to 4.0](https://flutter.dev/go/go-router-v4-breaking-changes)
- [Migrating to 3.0](https://flutter.dev/go/go-router-v3-breaking-changes)
- [Migrating to 2.5](https://flutter.dev/go/go-router-v2-5-breaking-changes)
- [Migrating to 2.0](https://flutter.dev/go/go-router-v2-breaking-changes)

## Changelog

See the
[Changelog](https://github.com/flutter/packages/blob/main/packages/go_router/CHANGELOG.md)
for a list of new features and breaking changes.

## Roadmap

See the [GitHub project](https://github.com/orgs/flutter/projects/17/) for a
prioritized list of feature requests and known issues.
