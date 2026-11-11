// Accessibility audit of the app's screens (flutter_a11y_test, layer
// "runtime").  See README.md in this directory.
//
// Each test launches the real [App] against a fake of the KitchenOwl server
// (support/fake_server.dart), in one of two windows (a phone and a desktop
// browser window), reaches one screen the way a user would (taps, long
// presses, typed text; a URL only where a user would arrive by a link), and
// runs the audit on it.  Findings are RECORDED, not asserted: the
// RuntimeFindingsSink set up in flutter_test_config.dart writes them to
// .a11y/flutter/runtime-findings.json.
import 'dart:io';

import 'package:flutter_a11y_routes/flutter_a11y_routes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenowl/app.dart';
import 'package:kitchenowl/cubits/auth_cubit.dart';
import 'package:kitchenowl/enums/views_enum.dart';
import 'package:kitchenowl/gen/l10n/app_localizations.dart';
import 'package:kitchenowl/models/category.dart';
import 'package:kitchenowl/models/expense_category.dart';
import 'package:kitchenowl/models/shoppinglist.dart';
import 'package:kitchenowl/pages/analytics_page.dart';
import 'package:kitchenowl/pages/email_confirm_page.dart';
import 'package:kitchenowl/pages/expense_add_update_page.dart';
import 'package:kitchenowl/pages/expense_category_add_page.dart';
import 'package:kitchenowl/pages/expense_month_list_page.dart';
import 'package:kitchenowl/pages/expense_overview_page.dart';
import 'package:kitchenowl/pages/expense_page.dart';
import 'package:kitchenowl/pages/household_about_page.dart';
import 'package:kitchenowl/pages/household_add_page.dart';
import 'package:kitchenowl/pages/household_list_page.dart';
import 'package:kitchenowl/pages/household_member_page.dart';
import 'package:kitchenowl/pages/household_page/more.dart';
import 'package:kitchenowl/pages/household_update_page.dart';
import 'package:kitchenowl/pages/icon_selection_page.dart';
import 'package:kitchenowl/pages/item_page.dart';
import 'package:kitchenowl/pages/item_search_page.dart';
import 'package:kitchenowl/pages/item_selection_page.dart';
import 'package:kitchenowl/pages/onboarding_page.dart';
import 'package:kitchenowl/pages/page_not_found.dart';
import 'package:kitchenowl/pages/password_forgot_page.dart';
import 'package:kitchenowl/pages/password_reset_page.dart';
import 'package:kitchenowl/pages/photo_view_page.dart';
import 'package:kitchenowl/pages/recipe_add_update_page.dart';
import 'package:kitchenowl/pages/recipe_cooking_page.dart';
import 'package:kitchenowl/pages/recipe_discover_page.dart';
import 'package:kitchenowl/pages/recipe_generate_page.dart';
import 'package:kitchenowl/pages/recipe_list_display_page.dart';
import 'package:kitchenowl/pages/recipe_page.dart';
import 'package:kitchenowl/pages/recipe_scraper_page.dart';
import 'package:kitchenowl/pages/reports_list_page.dart';
import 'package:kitchenowl/pages/settings/create_user_page.dart';
import 'package:kitchenowl/pages/settings_household/household_settings_category_page.dart';
import 'package:kitchenowl/pages/settings_household/household_settings_expense_category_page.dart';
import 'package:kitchenowl/pages/settings_household/household_settings_items_page.dart';
import 'package:kitchenowl/pages/settings_household/household_settings_shoppinglist_page.dart';
import 'package:kitchenowl/pages/settings_household/household_settings_tags_page.dart';
import 'package:kitchenowl/pages/settings_page.dart';
import 'package:kitchenowl/pages/settings_server_user_page.dart';
import 'package:kitchenowl/pages/settings_user_email_page.dart';
import 'package:kitchenowl/pages/settings_user_linked_accounts_page.dart';
import 'package:kitchenowl/pages/settings_user_page.dart';
import 'package:kitchenowl/pages/settings_user_password_page.dart';
import 'package:kitchenowl/pages/settings_user_sessions_page.dart';
import 'package:kitchenowl/pages/setup_page.dart';
import 'package:kitchenowl/pages/signup_page.dart';
import 'package:kitchenowl/pages/splash_page.dart';
import 'package:kitchenowl/pages/tutorial_page.dart';
import 'package:kitchenowl/pages/unreachable_page.dart';
import 'package:kitchenowl/pages/user_search_page.dart';
import 'package:kitchenowl/router.dart' as app_router;
import 'package:kitchenowl/services/api/api_service.dart';
import 'package:kitchenowl/services/storage/mem_storage.dart';
import 'package:kitchenowl/styles/themes.dart';
import 'package:kitchenowl/widgets/item_popup_menu_button.dart';
import 'package:kitchenowl/widgets/kitchenowl_color_picker_dialog.dart';
import 'package:kitchenowl/widgets/loading_elevated_button.dart';
import 'package:kitchenowl/widgets/recipe_card.dart';
import 'package:kitchenowl/widgets/report_dialog.dart';
import 'package:kitchenowl/widgets/select_dialog.dart';
import 'package:kitchenowl/widgets/selectable_button_card.dart';
import 'package:kitchenowl/widgets/settings/token_bottom_sheet.dart';
import 'package:kitchenowl/widgets/settings_household/update_member_bottom_sheet.dart';
import 'package:kitchenowl/widgets/shimmer_card.dart';
import 'package:kitchenowl/widgets/text_dialog.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_http.dart';
import 'support/fake_platform.dart';
import 'support/fake_server.dart';
import 'support/harness.dart';

/// Pumps until nothing is animating, or for three seconds: a page with a
/// progress indicator never settles.
///
/// Between pumps a moment of real time passes.  Two things in the app only
/// advance in real time, not on the test's fake clock: images are decoded on
/// an engine thread, and reads of the preferences store complete on the root
/// zone (see `installPreferencesStore`).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1)));
    await tester.pump(const Duration(milliseconds: 50));
    if (i >= 12 && !tester.binding.hasScheduledFrame) break;
  }
}

/// The state of the device when the app is started.
class Launch {
  const Launch({
    this.server = true,
    this.signedIn = true,
    this.household = FakeServer.householdId,
    this.location,
    this.preferences = const {},
  });

  /// Whether a server address is saved on the device.
  final bool server;
  final bool signedIn;

  /// The household the user last had open, or null for none.
  final int? household;

  /// A deep link the app is opened with.
  final String? location;
  final Map<String, Object> preferences;
}

/// Starts the real app on a device in the state [options] describes, with
/// [server] answering its requests, and waits for its first page.
Future<void> launch(
  WidgetTester tester,
  AuditViewport viewport,
  FakeServer server,
  Launch options,
) async {
  useViewport(tester, viewport);
  WidgetsApp.debugAllowBannerOverride = false;
  addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
  // `flutter test` draws every shadow as a solid black outline (for stable
  // golden files).  The app is audited with its real shadows.
  debugDisableShadows = false;

  await installFakeDevice(
    images: FakeImageCache(fakeImageFor),
    preferences: {
      if (options.server) 'URL': FakeServer.url,
      if (options.household != null) 'lastHouseholdId': options.household!,
      ...options.preferences,
    },
    token: options.signedIn ? FakeServer.refreshToken : null,
  );
  addTearDown(resetFakeDevice);
  final testHttpOverrides = HttpOverrides.current;
  HttpOverrides.global = FakeHttpOverrides(server);
  addTearDown(() => HttpOverrides.global = testHttpOverrides);

  // The app keeps its API client, its cache and its router in globals.
  ApiService.getInstance().dispose();
  await MemStorage.getInstance().clearAll();
  app_router.initialLocation = null;
  app_router.router.go(options.location ?? '/');

  await tester.pumpWidget(withDeviceChipFont(App()));
  await tester.pump();
  await _settle(tester);
}

/// Gives the app's chip labels the font they have on a device.
///
/// The app's theme sets the chip label style to `TextStyle(color: ...)`, with
/// no font family.  On Android and in Flutter's web renderer such text is
/// drawn in the platform default, Roboto.  Under `flutter test` the default
/// is the engine's test font, in which every glyph is a 1 em square, and no
/// font loaded at run time can take its place.  So the harness puts the app's
/// own chip theme, with `fontFamily: 'Roboto'` added and nothing else
/// changed, above the app; `ChipTheme.of` finds it before the theme's.
///
/// `A11Y_TEST_FONT=ahem` turns this off, like the other real fonts.
Widget withDeviceChipFont(Widget app) {
  if (Platform.environment['A11Y_TEST_FONT'] == 'ahem') return app;
  final theme = AppThemes.light().chipTheme;
  return ChipTheme(
    data: theme.copyWith(
      labelStyle: theme.labelStyle?.copyWith(fontFamily: 'Roboto'),
      secondaryLabelStyle:
          theme.secondaryLabelStyle?.copyWith(fontFamily: 'Roboto'),
    ),
    child: app,
  );
}

/// Takes the app down so that nothing of it outlives the test.
Future<void> shutDown(WidgetTester tester, FakeServer server) async {
  // Requests still on their way are answered or time out (5 s) while the app
  // is still there to receive the answer.  Taking the app down first would
  // leave its cubits emitting after they were closed.
  server.latency = const Duration(milliseconds: 30);
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  final authCubit = find.byType(MaterialApp).evaluate().isEmpty
      ? null
      : BlocProvider.of<AuthCubit>(tester.element(find.byType(MaterialApp)));
  await tester.pumpWidget(const SizedBox.shrink());
  debugDisableShadows = true;
  await authCubit?.close();
  ApiService.getInstance().dispose();
  // Long enough for every request still on its way to come back or time out.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(minutes: 1));
  }
}

/// What a screen's steps work with.
class Run {
  Run(this.tester, this.server, this.viewport);

  final WidgetTester tester;
  final FakeServer server;
  final AuditViewport viewport;

  /// Things worth knowing about how the screen was reached, for the log.
  final List<String> notes = [];

  bool get wide => viewport == AuditViewport.wide;

  Future<void> settle() => _settle(tester);

  /// Taps [finder]'s first match that can be hit.  When nothing matching is
  /// on screen, the page is scrolled down until something is.
  Future<void> tap(Finder finder) async {
    await reveal(finder);
    await tester.tap(finder.hitTestable().first);
    await tester.pump();
    await settle();
  }

  /// Scrolls the frontmost page until [finder] matches something that can be
  /// hit.
  Future<void> reveal(Finder finder) async {
    if (finder.hitTestable().evaluate().isNotEmpty) return;
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder.first);
      await tester.pump();
      await settle();
      if (finder.hitTestable().evaluate().isNotEmpty) return;
    }
    final scrollable = find
        .byWidgetPredicate((widget) =>
            widget is Scrollable &&
            (widget.axisDirection == AxisDirection.down ||
                widget.axisDirection == AxisDirection.up))
        .hitTestable();
    for (var i = 0; i < 40 && finder.hitTestable().evaluate().isEmpty; i++) {
      await tester.drag(scrollable.last, const Offset(0, -250));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
    await settle();
  }

  Future<void> tapText(String text) => tap(find.text(text));

  Future<void> tapIcon(IconData icon) => tap(find.byIcon(icon));

  Future<void> tapTooltip(String tooltip) => tap(find.byTooltip(tooltip));

  Future<void> longPress(Finder finder) async {
    await tester.longPress(finder);
    await tester.pump();
    await settle();
  }

  /// Presses and holds the picture on an item's card.  (Holding the item's
  /// NAME only shows a tooltip with the name: the name is wrapped in a
  /// `Tooltip`, whose long-press wins over the card's.)
  Future<void> longPressItem(String name) async {
    final card = find.ancestor(
        of: find.text(name), matching: find.byType(SelectableButtonCard));
    await reveal(card);
    final rect = tester.getRect(card.hitTestable().first);
    await tester.longPressAt(rect.topCenter + const Offset(0, 24));
    await tester.pump();
    await settle();
  }

  Future<void> enter(Finder field, String text) async {
    await tester.enterText(field, text);
    await tester.pump();
    await settle();
  }

  /// The text field labelled (or hinted) [label].
  Finder field(String label) => find.byWidgetPredicate((widget) =>
      widget is TextField &&
      (widget.decoration?.labelText == label ||
          widget.decoration?.hintText == label));

  /// Opens one of the household's main destinations: the bottom navigation
  /// bar on the phone, the navigation rail in the wide window.
  Future<void> destination(ViewsEnum view) async {
    if (wide) {
      await tapText(view.toLocalizedString(context));
    } else {
      await tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(view.toIcon(context)),
      ));
    }
  }

  BuildContext get context => tester.element(find.byType(Navigator).first);

  /// The app is put in the background and brought back, which makes it ask
  /// the server again.
  Future<void> resume() async {
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    await settle();
  }
}

/// A screen: launch, get there with [reach], audit, in each of [viewports].
///
/// With [grow] the view is made as tall as the page's content first, so a
/// lazily built list is audited in full.  Not for dialogs, sheets and menus,
/// whose place depends on the window's height.
void screen(
  String id,
  Future<void> Function(Run run) reach, {
  Launch options = const Launch(),
  FakeServer Function()? server,
  bool grow = false,
  List<AuditViewport> viewports = AuditViewport.values,
}) {
  declaredScreens.add(id);
  for (final viewport in viewports) {
    final screenId = viewport.idFor(id);
    testWidgets(screenId, (tester) async {
      final fake = server?.call() ?? FakeServer();
      final run = Run(tester, fake, viewport);
      final recorder = ExceptionRecorder()..install();
      try {
        await launch(tester, viewport, fake, options);
        try {
          await reach(run);
        } on Object {
          await maybeScreenshot(tester, '$screenId.NOT-REACHED');
          // ignore: avoid_print
          print('requests:\n  ${fake.requests.join('\n  ')}');
          rethrow;
        }
        await audit(tester, screenId,
            grow: grow,
            recorder: recorder,
            notes: run.notes,
            unhandledRequests: () => fake.unhandled.toSet().toList());
      } finally {
        await shutDown(tester, fake);
        recorder.uninstall();
      }
    });
  }
}

final AppLocalizations l10n = lookupAppLocalizations(const Locale('en'));

/// Every screen id declared with [screen], without the viewport suffix.
final Set<String> declaredScreens = {};

/// The app's go_router routes, as `GoRouterSource` discovers them, and the
/// screens that audit each one.  An empty list is a route that is not
/// audited; the reason is in README.md.
///
/// The routes are not pumped from this table (most need a signed-in session,
/// a household and data, and half of the app's pages are not routes at all).
/// The table exists so that a route added upstream fails the
/// `route coverage` test until someone decides how to audit it.
const Map<String, List<String>> routeCoverage = {
  'root': ['splash-loading'],
  'setup': ['server-setup', 'server-setup-empty-address-error'],
  'onboarding': ['onboarding', 'onboarding-validation-errors'],
  'signin': ['sign-in', 'sign-in-default-server', 'sign-in-wrong-password'],
  'signin/redirect': [],
  'register': ['sign-up', 'sign-up-validation-errors'],
  'unsupported': ['unsupported-server-too-old', 'unsupported-app-too-old'],
  'unreachable': ['server-unreachable'],
  'tutorial': ['tutorial', 'tutorial-recipes'],
  'household': ['household-chooser', 'household-chooser-empty'],
  // Declared as a child of /household with the path '/about/:id'; the real
  // location is /household/about/:id.
  'about/:id': ['household-about'],
  'household/:id': ['shopping-list'],
  'household/:id/items': ['shopping-list', 'shopping-list-empty'],
  'household/:id/recipes': ['recipes', 'recipes-empty'],
  'household/:id/recipes/details/:recipeId': ['recipe-detail'],
  'household/:id/recipes/scrape': ['recipe-import-from-url'],
  'household/:id/recipes/discover': ['recipes-discover'],
  'household/:id/planner': ['planner', 'planner-empty'],
  'household/:id/balances': ['balances', 'balances-empty'],
  'household/:id/balances/overview': ['expense-overview'],
  'household/:id/balances/:expenseId': ['expense-detail'],
  'recipe/:recipeId': [
    'recipe-detail-community',
    'recipe-shared-link-signed-out'
  ],
  'settings': ['settings', 'settings-without-household'],
  'settings/account': ['settings-account'],
  'confirm-email': ['confirm-email'],
  'reset-password': ['reset-password'],
  'forgot-password': ['forgot-password'],
};

void main() {
  setUpAll(installPreferencesStore);

  const signedOut = Launch(signedIn: false, household: null);

  group('first run', () {
    screen('splash-loading', (run) async {
      expect(find.byType(SplashPage), findsOneWidget);
    }, server: () => FakeServer()..latency = const Duration(seconds: 20));

    screen('sign-in-default-server', (run) async {
      expect(find.text(l10n.login), findsOneWidget);
    }, options: const Launch(server: false, signedIn: false, household: null));

    screen('sign-in', (run) async {
      expect(find.text(l10n.login), findsOneWidget);
    }, options: signedOut);

    screen('sign-in-server-menu', (run) async {
      await run.tap(find.byType(PopupMenuButton<int>));
      expect(find.text(l10n.serverChange), findsOneWidget);
    }, options: signedOut);

    screen('sign-in-wrong-password', (run) async {
      await run.enter(run.field(l10n.username), 'maria');
      await run.enter(run.field(l10n.password), 'not the password');
      await run.tapText(l10n.login);
      expect(find.text(l10n.wrongUsernameOrPassword), findsOneWidget);
    }, options: signedOut);

    screen('server-setup', (run) async {
      await run.tap(find.byType(PopupMenuButton<int>));
      await run.tapText(l10n.serverChange);
      expect(find.byType(SetupPage), findsOneWidget);
    }, options: signedOut);

    screen('server-setup-empty-address-error', (run) async {
      await run.tap(find.byType(PopupMenuButton<int>));
      await run.tapText(l10n.serverChange);
      await run.tapText(l10n.go);
      expect(find.text(l10n.fieldCannotBeEmpty(l10n.address)), findsOneWidget);
    }, options: signedOut);

    screen('sign-up', (run) async {
      await run.tapText(l10n.signup);
      expect(find.byType(SignupPage), findsOneWidget);
    }, options: signedOut);

    screen('sign-up-validation-errors', (run) async {
      await run.tapText(l10n.signup);
      await run.tapText(l10n.accountCreate);
      expect(find.byType(SignupPage), findsOneWidget);
    }, options: signedOut);

    screen('forgot-password', (run) async {
      await run.tapText(l10n.passwordForgot);
      expect(find.byType(PasswordForgotPage), findsOneWidget);
    }, options: signedOut);

    screen('reset-password', (run) async {
      expect(find.byType(PasswordResetPage), findsOneWidget);
    },
        options: const Launch(
            signedIn: false,
            household: null,
            location: '/reset-password?t=abc'));

    screen('confirm-email', (run) async {
      expect(find.byType(EmailConfirmPage), findsOneWidget);
    },
        options: const Launch(
            signedIn: false,
            household: null,
            location: '/confirm-email?t=abc'));

    screen('onboarding', (run) async {
      expect(find.byType(OnboardingPage), findsOneWidget);
    }, options: signedOut, server: () => FakeServer(state: ServerState.fresh));

    // After the first account is created the app pushes its tutorial and, on
    // the same state change, goes to the household list.  In the harness the
    // second navigation wins and the tutorial is never on screen, so it is
    // opened by its URL instead.
    screen('tutorial', (run) async {
      expect(find.byType(TutorialPage), findsOneWidget);
      run.notes.add('Opened by URL (/tutorial), not by finishing onboarding.');
    }, options: const Launch(location: '/tutorial'), grow: true);

    screen('tutorial-recipes', (run) async {
      await run.tapText(l10n.next);
      expect(find.byType(TutorialPage), findsOneWidget);
      run.notes.add('Opened by URL (/tutorial), not by finishing onboarding.');
    }, options: const Launch(location: '/tutorial'), grow: true);

    screen('onboarding-validation-errors', (run) async {
      await run.tapText(l10n.start);
      expect(find.text(l10n.fieldCannotBeEmpty(l10n.username)), findsOneWidget);
    }, options: signedOut, server: () => FakeServer(state: ServerState.fresh));
  });

  group('connection states', () {
    screen('server-unreachable', (run) async {
      expect(find.byType(UnreachablePage), findsOneWidget);
    }, options: signedOut, server: () => FakeServer(reachable: false));

    screen('server-unreachable-menu', (run) async {
      await run.tap(find.byType(PopupMenuButton<int>));
      expect(find.text(l10n.serverChange), findsOneWidget);
    }, options: signedOut, server: () => FakeServer(reachable: false));

    screen('unsupported-server-too-old', (run) async {
      expect(find.text(l10n.unsupportedBackendMessage), findsOneWidget);
    }, options: signedOut, server: () => FakeServer(state: ServerState.tooOld));

    screen('unsupported-app-too-old', (run) async {
      expect(find.text(l10n.unsupportedFrontendMessage), findsOneWidget);
    }, options: signedOut, server: () => FakeServer(state: ServerState.tooNew));

    screen('page-not-found', (run) async {
      expect(find.byType(PageNotFound), findsOneWidget);
    }, options: const Launch(location: '/no-such-page'));

    // The server is upgraded past what the app supports while the user is
    // signed in: the app offers to carry on offline.
    screen('unsupported-app-too-old-signed-in', (run) async {
      run.server.state = ServerState.tooNew;
      await run.resume();
      expect(find.text(l10n.forceOfflineMode), findsOneWidget);
    });

    screen('recipes-offline', (run) async {
      await run.destination(ViewsEnum.recipes);
      run.server.reachable = false;
      await run.resume();
      expect(App.isOffline, isTrue);
      expect(find.text('Banana bread'), findsWidgets);
    }, grow: true);

    screen('balances-offline', (run) async {
      run.server.reachable = false;
      await run.resume();
      await run.destination(ViewsEnum.balances);
      expect(find.text(l10n.offlineMessage), findsOneWidget);
    });

    screen('recipes-loading', (run) async {
      run.server.latency = const Duration(seconds: 30);
      await run.destination(ViewsEnum.recipes);
      expect(find.byType(ShimmerCard), findsWidgets);
    });

    screen('shopping-list-offline', (run) async {
      run.server.reachable = false;
      await run.resume();
      expect(find.text('Tomatoes'), findsWidgets);
      expect(App.isOffline, isTrue);
    }, grow: true);
  });

  group('shopping list', () {
    screen('shopping-list', (run) async {
      expect(find.text('Tomatoes'), findsWidgets);
    }, grow: true);

    screen('shopping-list-empty', (run) async {
      expect(find.text(l10n.shoppingListEmpty), findsOneWidget);
    }, server: () => FakeServer(populated: false));

    screen('shopping-list-by-category', (run) async {
      await run.tapText(l10n.sortingAlphabetical);
      await run.tapText(l10n.sortingAlgorithmic);
      expect(find.text('Fruits and vegetables'), findsWidgets);
    }, grow: true);

    screen('shopping-list-as-list', (run) async {
      expect(find.text('Bananas'), findsWidgets);
    },
        options: const Launch(preferences: {'shoppingListListView': true}),
        grow: true);

    screen('shopping-list-second-list', (run) async {
      await run.tap(find.textContaining('Hardware store'));
      expect(find.text('Wood screws'), findsOneWidget);
    });

    screen('shopping-list-search', (run) async {
      await run.enter(find.byType(TextField), 'to');
      expect(find.text('Toilet paper'), findsWidgets);
    }, grow: true);

    screen('shopping-list-search-new-item', (run) async {
      await run.enter(find.byType(TextField), '2 l oat milk');
      expect(find.textContaining('oat milk'), findsWidgets);
    });

    // With "Remove item interaction: Confirm" a tap marks an item as bought
    // and a button confirms the removal.
    screen('shopping-list-items-marked', (run) async {
      await run.tapText('Eggs');
      await run.tapText('Milk');
      expect(find.byTooltip(l10n.confirm), findsOneWidget);
    }, options: const Launch(preferences: {'shoppingListTapToRemove': false}));

    screen('item-detail', (run) async {
      await run.longPressItem('Tomatoes');
      expect(find.byType(ItemPage), findsOneWidget);
    }, grow: true);

    screen('item-link-sheet', (run) async {
      await run.longPressItem('Birthday candles');
      expect(find.text(l10n.openUrl), findsOneWidget);
    });

    screen('item-menu', (run) async {
      await run.longPressItem('Tomatoes');
      await run.tap(find.byType(ItemPopupMenuButton));
      expect(find.text(l10n.changeIcon), findsOneWidget);
    });

    screen('item-icon-selection', (run) async {
      await run.longPressItem('Tomatoes');
      await run.tap(find.byType(ItemPopupMenuButton));
      await run.tapText(l10n.changeIcon);
      expect(find.byType(IconSelectionPage), findsOneWidget);
    });

    screen('item-rename-dialog', (run) async {
      await run.longPressItem('Tomatoes');
      await run.tap(find.byType(ItemPopupMenuButton));
      await run.tapText(l10n.rename);
      expect(find.byType(TextDialog), findsOneWidget);
    });

    screen('item-merge-search', (run) async {
      await run.longPressItem('Tomatoes');
      await run.tap(find.byType(ItemPopupMenuButton));
      await run.tapText(l10n.merge);
      expect(find.byType(ItemSearchPage), findsOneWidget);
      await run.enter(find.byType(TextField).last, 'to');
    });

    screen('item-delete-confirmation', (run) async {
      await run.longPressItem('Tomatoes');
      await run.tap(find.byType(ItemPopupMenuButton));
      await run.tapText(l10n.delete);
      expect(find.text(l10n.itemDelete), findsOneWidget);
    });
  });

  group('recipes', () {
    Future<void> openRecipes(Run run) async {
      await run.destination(ViewsEnum.recipes);
      expect(find.text('Banana bread'), findsWidgets);
    }

    Future<void> openRecipe(Run run,
        [String name = 'Spaghetti al pomodoro']) async {
      await openRecipes(run);
      await run.tapText(name);
      expect(find.byType(RecipePage), findsOneWidget);
    }

    screen('recipes', openRecipes, grow: true);

    screen('recipes-empty', (run) async {
      await run.destination(ViewsEnum.recipes);
      expect(find.text(l10n.recipeEmpty), findsOneWidget);
    }, server: () => FakeServer(populated: false));

    screen('recipes-as-cards', (run) async {
      await openRecipes(run);
      await run.tapText(l10n.sortingAlphabetical);
      expect(find.byType(RecipeCard), findsWidgets);
    }, grow: true);

    screen('recipes-filtered-by-tag', (run) async {
      await openRecipes(run);
      await run.tap(find.widgetWithText(FilterChip, 'Soup'));
      expect(find.text('Banana bread'), findsNothing);
    });

    screen('recipes-search', (run) async {
      await openRecipes(run);
      await run.enter(find.byType(TextField), 'ginger');
      expect(find.text('Banana bread'), findsNothing);
      expect(find.text('Carrot and ginger soup'), findsOneWidget);
    });

    screen('recipes-search-no-results', (run) async {
      await openRecipes(run);
      await run.enter(find.byType(TextField), 'lasagne');
      expect(find.text(l10n.recipeEmptySearch), findsOneWidget);
    });

    screen('recipes-add-menu', (run) async {
      await openRecipes(run);
      await run.tapTooltip(l10n.recipeAdd);
      expect(find.byTooltip(l10n.recipeAddUrl), findsOneWidget);
    });

    screen('recipe-new', (run) async {
      await openRecipes(run);
      await run.tapTooltip(l10n.recipeAdd);
      await run.tapIcon(Icons.note_add_rounded);
      expect(find.byType(AddUpdateRecipePage), findsOneWidget);
    }, grow: true);

    screen('recipe-add-from-url-dialog', (run) async {
      await openRecipes(run);
      await run.tapTooltip(l10n.recipeAdd);
      await run.tapTooltip(l10n.recipeAddUrl);
      expect(find.byType(TextDialog), findsOneWidget);
    });

    screen('recipe-import-from-url', (run) async {
      await openRecipes(run);
      await run.tapTooltip(l10n.recipeAdd);
      await run.tapTooltip(l10n.recipeAddUrl);
      await run.enter(find.byType(TextField).last,
          'https://www.example.org/recipes/mushroom-risotto');
      await run.tapText(l10n.add);
      expect(find.byType(RecipeScraperPage), findsOneWidget);
      expect(find.textContaining('risotto'), findsWidgets);
    }, grow: true);

    screen('recipe-import-review', (run) async {
      await openRecipes(run);
      await run.tapTooltip(l10n.recipeAdd);
      await run.tapTooltip(l10n.recipeAddUrl);
      await run.enter(find.byType(TextField).last,
          'https://www.example.org/recipes/mushroom-risotto');
      await run.tapText(l10n.add);
      await run.tapText(l10n.next);
      expect(find.byType(AddUpdateRecipePage), findsOneWidget);
    }, grow: true);

    screen('recipe-generate', (run) async {
      await openRecipes(run);
      await run.tapTooltip(l10n.recipeAdd);
      await run.tapTooltip(l10n.recipeGenerate);
      expect(find.byType(RecipeGeneratePage), findsOneWidget);
    }, grow: true);

    screen('recipes-discover', (run) async {
      await openRecipes(run);
      await run.tapTooltip(l10n.discover);
      expect(find.byType(RecipeDiscoverPage), findsOneWidget);
      expect(find.text('Shakshuka'), findsWidgets);
    }, grow: true);

    screen('recipe-detail', openRecipe, grow: true);

    screen('recipe-detail-no-photo', (run) async {
      await openRecipe(run, 'Carrot and ginger soup');
    }, grow: true);

    screen('recipe-detail-community', (run) async {
      await openRecipes(run);
      await run.tapTooltip(l10n.discover);
      await run.tap(find.text('Shakshuka'));
      expect(find.byType(RecipePage), findsOneWidget);
      expect(find.text('The Green Kitchen'), findsWidgets);
    }, grow: true);

    // A recipe of another household has a "More" menu instead of an edit
    // button.  Maria administers the server, so hers also offers to edit or
    // delete the recipe.
    Future<void> openCommunityRecipeMenu(Run run) async {
      await openRecipes(run);
      await run.tapTooltip(l10n.discover);
      await run.tap(find.text('Shakshuka'));
      await run.tapTooltip(l10n.more);
    }

    screen('recipe-more-menu', (run) async {
      await openCommunityRecipeMenu(run);
      expect(find.text(l10n.reportRecipe), findsOneWidget);
    });

    screen('recipe-report-dialog', (run) async {
      await openCommunityRecipeMenu(run);
      await run.tapText(l10n.reportRecipe);
      expect(find.byType(ReportDialog), findsOneWidget);
    });

    screen('recipe-delete-confirmation', (run) async {
      await openCommunityRecipeMenu(run);
      await run.tapText(l10n.recipeDelete);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    screen('recipe-choose-shopping-list-dialog', (run) async {
      await openRecipe(run);
      await run.tapIcon(Icons.shopping_bag_rounded);
      expect(find.byType(SelectDialog<ShoppingList>), findsOneWidget);
    });

    screen('recipe-plan-date-picker', (run) async {
      await openRecipe(run);
      await run.tapIcon(Icons.calendar_month_rounded);
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    screen('recipe-cooking-first-step', (run) async {
      await openRecipe(run);
      await run.tapTooltip(l10n.start);
      expect(find.byType(RecipeCookingPage), findsOneWidget);
    }, grow: true);

    screen('recipe-cooking-second-step', (run) async {
      await openRecipe(run);
      await run.tapTooltip(l10n.start);
      await run.tapText(l10n.next);
      expect(find.byType(RecipeCookingPage), findsOneWidget);
    }, grow: true);

    Future<void> openRecipeEdit(Run run) async {
      await openRecipe(run);
      await run.tapTooltip(l10n.recipeEdit);
      expect(find.byType(AddUpdateRecipePage), findsOneWidget);
    }

    screen('recipe-edit', openRecipeEdit, grow: true);

    screen('recipe-edit-visibility-help', (run) async {
      await openRecipeEdit(run);
      await run.tapIcon(Icons.info_outline_rounded);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    screen('recipe-edit-new-tag-dialog', (run) async {
      await openRecipeEdit(run);
      await run.tapTooltip(l10n.addTag);
      expect(find.byType(TextDialog), findsOneWidget);
    });

    screen('recipe-edit-add-ingredients', (run) async {
      await openRecipeEdit(run);
      await run.tap(find.byTooltip(l10n.addItemTitle));
      expect(find.byType(ItemSearchPage), findsOneWidget);
      await run.enter(find.byType(TextField).last, 'on');
      expect(find.text('Onions'), findsWidgets);
    });

    screen('recipe-edit-ingredient', (run) async {
      await openRecipeEdit(run);
      // A tap removes the ingredient; holding it opens it.
      await run.longPressItem('Spaghetti');
      expect(find.byWidgetPredicate((widget) => widget is ItemPage),
          findsOneWidget);
    }, grow: true);

    screen('recipe-edit-unsaved-changes-dialog', (run) async {
      await openRecipeEdit(run);
      await run.enter(run.field(l10n.name), 'Spaghetti al pomodoro e basilico');
      await run.tester.pageBack();
      await run.settle();
      expect(find.text(l10n.unsavedChangesTitle), findsOneWidget);
    });

    screen('recipe-edit-delete-confirmation', (run) async {
      await openRecipeEdit(run);
      await run.tap(find.widgetWithText(LoadingElevatedButton, l10n.delete));
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    screen('recipe-photo', (run) async {
      await openRecipe(run);
      await run.tester.tapAt(const Offset(200, 150));
      await run.settle();
      expect(find.byType(PhotoViewPage), findsOneWidget);
    });

    // A recipe shared by link, opened by someone who is not signed in.
    screen('recipe-shared-link-signed-out', (run) async {
      expect(find.byType(RecipePage), findsOneWidget);
      await run.reveal(find.text(l10n.loginToAddToShoppingList));
      expect(find.text(l10n.loginToAddToShoppingList), findsOneWidget);
    },
        options: const Launch(
            signedIn: false, household: null, location: '/recipe/1'),
        grow: true);
  });

  group('meal planner', () {
    Future<void> openPlanner(Run run) async {
      await run.destination(ViewsEnum.planner);
      expect(find.text(l10n.plannerTitle), findsOneWidget);
    }

    screen('planner', openPlanner, grow: true);

    screen('planner-empty', (run) async {
      await run.destination(ViewsEnum.planner);
      expect(find.text(l10n.plannerEmpty), findsOneWidget);
    }, server: () => FakeServer(populated: false));

    screen('planner-add-items', (run) async {
      await openPlanner(run);
      await run.tapTooltip(l10n.itemsAdd);
      expect(find.byType(ItemSelectionPage), findsOneWidget);
    }, grow: true);

    screen('planner-recent-recipes', (run) async {
      await openPlanner(run);
      if (run.wide) {
        await run.tap(find.widgetWithText(FilledButton, l10n.more));
      } else {
        // On the phone the way in is an arrow after the last card of the row.
        final row = find.byWidgetPredicate((widget) =>
            widget is ListView && widget.scrollDirection == Axis.horizontal);
        await run.reveal(row);
        await run.tester.dragUntilVisible(
          find.byIcon(Icons.keyboard_arrow_right_rounded).hitTestable(),
          row.hitTestable().first,
          const Offset(-300, 0),
        );
        await run.tapIcon(Icons.keyboard_arrow_right_rounded);
      }
      expect(find.byType(RecipeListDisplayPage), findsOneWidget);
    }, grow: true);

    screen('planner-plan-date-picker', (run) async {
      await openPlanner(run);
      await run.tapIcon(Icons.calendar_month_rounded);
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    screen('planner-recipe-from-plan', (run) async {
      await openPlanner(run);
      await run.tapText('Red lentil dal');
      expect(find.byType(RecipePage), findsOneWidget);
    }, grow: true);
  });

  group('expenses', () {
    Future<void> openBalances(Run run) async {
      await run.destination(ViewsEnum.balances);
      expect(find.text('Pizza night'), findsWidgets);
    }

    screen('balances', openBalances, grow: true);

    screen('balances-empty', (run) async {
      await run.destination(ViewsEnum.balances);
      expect(find.text(l10n.expenseEmpty), findsOneWidget);
    }, server: () => FakeServer(populated: false));

    screen('balances-personal', (run) async {
      await openBalances(run);
      await run.tapText(l10n.household);
      expect(find.text(l10n.personal), findsOneWidget);
    }, grow: true);

    screen('balances-search', (run) async {
      await openBalances(run);
      await run.tapIcon(Icons.search);
      await run.enter(find.byType(TextField), 'weekly');
      expect(find.text('Pizza night'), findsNothing);
    });

    screen('balances-category-filter', (run) async {
      await openBalances(run);
      await run.tapIcon(Icons.filter_list_rounded);
      await run.tap(find.widgetWithText(FilterChip, 'Eating out'));
      expect(find.text('Pizza night'), findsWidgets);
      expect(find.text('Bakery'), findsNothing);
    });

    screen('expense-overview', (run) async {
      await openBalances(run);
      await run.tapTooltip(l10n.overview);
      expect(find.byType(ExpenseOverviewPage), findsOneWidget);
    }, grow: true);

    screen('expense-overview-category-month', (run) async {
      await openBalances(run);
      await run.tapTooltip(l10n.overview);
      await run.tap(find.widgetWithText(ListTile, 'Groceries'));
      expect(find.byType(ExpenseMonthListPage), findsOneWidget);
    }, grow: true);

    screen('expense-detail', (run) async {
      await openBalances(run);
      await run.tapText('Pizza night');
      expect(find.byType(ExpensePage), findsOneWidget);
    }, grow: true);

    screen('expense-detail-with-receipt', (run) async {
      await openBalances(run);
      await run.tap(find.text('Weekly shop'));
      expect(find.byType(ExpensePage), findsOneWidget);
      expect(find.text('Saturday market and the supermarket'), findsOneWidget);
    }, grow: true);

    screen('expense-edit', (run) async {
      await openBalances(run);
      await run.tapText('Pizza night');
      await run.tapTooltip(l10n.expenseEdit);
      expect(find.byType(AddUpdateExpensePage), findsOneWidget);
    }, grow: true);

    Future<void> openNewExpense(Run run) async {
      await openBalances(run);
      await run.tapTooltip(l10n.expenseAdd);
      expect(find.byType(AddUpdateExpensePage), findsOneWidget);
    }

    screen('expense-new', openNewExpense, grow: true);

    screen('expense-new-validation-error', (run) async {
      await openNewExpense(run);
      // The phone has a save button in the app bar, the wide window an
      // "Add expense" button under the form.
      if (run.wide) {
        await run
            .tap(find.widgetWithText(LoadingElevatedButton, l10n.expenseAdd));
      } else {
        await run.tapTooltip(l10n.save);
      }
      expect(find.byType(AddUpdateExpensePage), findsOneWidget);
    }, grow: true);

    screen('expense-date-picker', (run) async {
      await openNewExpense(run);
      await run.tapIcon(Icons.calendar_month_rounded);
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    screen('expense-time-picker', (run) async {
      await openNewExpense(run);
      await run.tapIcon(Icons.calendar_month_rounded);
      await run.tapText(MaterialLocalizations.of(run.context).okButtonLabel);
      expect(find.byType(TimePickerDialog), findsOneWidget);
    });

    screen('expense-category-menu', (run) async {
      await openNewExpense(run);
      await run.tap(find.byType(DropdownButton<ExpenseCategory?>));
      expect(find.text('Utilities').hitTestable(), findsOneWidget);
    }, viewports: [AuditViewport.phone]);

    screen('expense-paid-by-menu', (run) async {
      await openNewExpense(run);
      await run.tap(find.byType(DropdownButton<int>));
      expect(find.text('Jonas Jensen').hitTestable(), findsWidgets);
    }, viewports: [AuditViewport.phone]);
  });

  group('households', () {
    const chooser = Launch(household: null);

    screen('household-chooser', (run) async {
      expect(find.byType(HouseholdListPage), findsOneWidget);
      expect(find.text('Lake cabin'), findsOneWidget);
    }, options: chooser, grow: true);

    screen('household-chooser-empty', (run) async {
      expect(find.text(l10n.householdEmpty), findsOneWidget);
    }, options: chooser, server: () => FakeServer(member: false));

    screen('household-leave-sheet', (run) async {
      await run.longPress(find.text('Lake cabin'));
      expect(find.text(l10n.householdLeave), findsOneWidget);
    }, options: chooser);

    Future<void> openNewHousehold(Run run) async {
      await run.tapTooltip(l10n.householdNew);
      expect(find.byType(HouseholdAddPage), findsOneWidget);
    }

    screen('household-new', openNewHousehold, options: chooser, grow: true);

    screen('household-new-language-sheet', (run) async {
      await openNewHousehold(run);
      await run.tapText('English');
      expect(find.text(l10n.languageSelect), findsOneWidget);
    }, options: chooser);

    screen('household-new-member-search', (run) async {
      await openNewHousehold(run);
      await run.tapTooltip(l10n.memberAdd);
      expect(find.byType(UserSearchPage), findsOneWidget);
      await run.enter(find.byType(TextField).last, 'a');
      expect(find.text('Aiko Tanaka'), findsOneWidget);
    }, options: chooser);

    // The "More" destination of the bottom bar.  The wide window has no such
    // destination: its navigation rail lists the same entries.
    screen('household-more-sheet', (run) async {
      await run.tap(find.byType(NavigationDestination).last);
      expect(find.byType(MorePage), findsOneWidget);
    }, viewports: [AuditViewport.phone]);

    // Between phone and wide (up to 950 px) the rail is collapsed, and a
    // button opens the same entries in a drawer.
    screen('household-drawer', (run) async {
      run.tester.view.physicalSize = const Size(800, 800);
      await run.settle();
      await run.tapIcon(Icons.menu_rounded);
      expect(find.byType(NavigationDrawer), findsWidgets);
      run.notes.add('Audited in an 800x800 window: the drawer exists only '
          'between 600 and 950 px.');
    }, viewports: [AuditViewport.wide]);

    screen('household-about', (run) async {
      await run.destination(ViewsEnum.recipes);
      await run.tapTooltip(l10n.discover);
      await run.tap(find.text('Shakshuka'));
      await run.tap(find.text('The Green Kitchen'));
      expect(find.byType(HouseholdAboutPage), findsOneWidget);
      expect(find.text('Apple crumble'), findsWidgets);
    }, grow: true);
  });

  group('settings', () {
    Future<void> openSettings(Run run) async {
      if (!run.wide) await run.tap(find.byType(NavigationDestination).last);
      await run.tapText(l10n.settings);
      expect(find.byType(SettingsPage), findsOneWidget);
    }

    Future<void> openAccount(Run run) async {
      if (!run.wide) await run.tap(find.byType(NavigationDestination).last);
      await run.tapText(l10n.profile);
      expect(find.byType(SettingsUserPage), findsOneWidget);
    }

    screen('settings', openSettings, grow: true);

    screen('settings-without-household', (run) async {
      await run.tapTooltip(l10n.settings);
      expect(find.byType(SettingsPage), findsOneWidget);
    }, options: const Launch(household: null), grow: true);

    screen('settings-offline', (run) async {
      run.server.reachable = false;
      await run.resume();
      await openSettings(run);
    }, grow: true);

    screen('settings-account', openAccount, grow: true);

    screen('settings-account-menu', (run) async {
      await openAccount(run);
      await run.tapIcon(Icons.more_vert);
      expect(find.text(l10n.accountDelete), findsOneWidget);
    });

    screen('settings-account-delete-confirmation', (run) async {
      await openAccount(run);
      await run.tapIcon(Icons.more_vert);
      await run.tapText(l10n.accountDelete);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    screen('settings-password', (run) async {
      await openAccount(run);
      await run.tap(find.widgetWithText(ListTile, l10n.passwordSave));
      expect(find.byType(SettingsUserPasswordPage), findsOneWidget);
    });

    screen('settings-email', (run) async {
      await openAccount(run);
      await run.tap(find.widgetWithText(ListTile, l10n.emailUpdate));
      expect(find.byType(SettingsUserEmailPage), findsOneWidget);
    });

    screen('settings-linked-accounts', (run) async {
      await openAccount(run);
      await run.tap(find.widgetWithText(ListTile, l10n.accountsLinked));
      expect(find.byType(SettingsLinkedAccountsPage), findsOneWidget);
    });

    Future<void> openSessions(Run run) async {
      await openAccount(run);
      await run.tap(find.widgetWithText(ListTile, l10n.sessions));
      expect(find.byType(SettingsUserSessionsPage), findsOneWidget);
    }

    screen('settings-sessions', openSessions, grow: true);

    screen('settings-session-sheet', (run) async {
      await openSessions(run);
      await run.tapText('Firefox on Linux');
      expect(find.byType(TokenBottomSheet), findsOneWidget);
    });

    screen('settings-token-warning', (run) async {
      await openSessions(run);
      await run.tapTooltip(l10n.lltCreate);
      expect(find.text(l10n.lltWarningTitle), findsOneWidget);
    });

    screen('settings-token-name-dialog', (run) async {
      await openSessions(run);
      await run.tapTooltip(l10n.lltCreate);
      await run.tapText(l10n.okay);
      expect(find.byType(TextDialog), findsOneWidget);
    });

    Future<void> openMembers(Run run) async {
      await openSettings(run);
      await run.tap(find.widgetWithText(ListTile, l10n.members));
      expect(find.byType(HouseholdMemberPage), findsOneWidget);
    }

    screen('household-members', openMembers, grow: true);

    screen('household-member-sheet', (run) async {
      await openMembers(run);
      await run.tapText('Aiko Tanaka');
      expect(find.byType(UpdateMemberBottomSheet), findsOneWidget);
    });

    screen('household-member-report-dialog', (run) async {
      await openMembers(run);
      await run.tapText('Aiko Tanaka');
      await run.tapText(l10n.reportUser);
      expect(find.byType(ReportDialog), findsOneWidget);
    });

    screen('household-member-add-search', (run) async {
      await openMembers(run);
      await run.tapTooltip(l10n.memberAdd);
      await run.enter(find.byType(TextField).last, 'sam');
      expect(find.text('Sam Okafor'), findsOneWidget);
    });

    screen('household-member-remove-confirmation', (run) async {
      await openMembers(run);
      await run.tester.drag(find.text('Aiko Tanaka'), const Offset(-600, 0));
      await run.settle();
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    Future<void> openHouseholdSettings(Run run) async {
      await openSettings(run);
      await run.tap(find.widgetWithIcon(ListTile, Icons.house_rounded));
      expect(find.byType(HouseholdUpdatePage), findsOneWidget);
    }

    screen('household-settings', openHouseholdSettings, grow: true);

    screen('household-settings-currency-picker', (run) async {
      await openHouseholdSettings(run);
      await run.tap(find.descendant(
          of: find.widgetWithText(ListTile, l10n.currency),
          matching: find.byType(ElevatedButton)));
      expect(find.text(l10n.searchHint), findsWidgets);
    });

    screen('household-delete-confirmation', (run) async {
      await openHouseholdSettings(run);
      await run.tapText(l10n.householdDelete);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    Future<void> openSub(Run run, String title, Type page) async {
      await openHouseholdSettings(run);
      await run.tap(find.widgetWithText(ListTile, title));
      expect(find.byType(page), findsOneWidget);
    }

    screen('household-items', (run) async {
      await openSub(run, l10n.items, HouseholdSettingsItemsPage);
    }, grow: true);

    screen('household-item-detail', (run) async {
      await openSub(run, l10n.items, HouseholdSettingsItemsPage);
      await run.tapText('Bananas');
      expect(find.byType(ItemPage), findsOneWidget);
    }, grow: true);

    screen('household-shopping-lists', (run) async {
      await openSub(run, l10n.shoppingLists, HouseholdSettingsShoppinglistPage);
    }, grow: true);

    screen('household-shopping-list-add-dialog', (run) async {
      await openSub(run, l10n.shoppingLists, HouseholdSettingsShoppinglistPage);
      await run.tapTooltip(l10n.addShoppingList);
      expect(find.byType(TextDialog), findsOneWidget);
    });

    screen('household-shopping-list-sheet', (run) async {
      await openSub(run, l10n.shoppingLists, HouseholdSettingsShoppinglistPage);
      await run.tapText('Hardware store');
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    screen('household-categories', (run) async {
      await openSub(run, l10n.categories, HouseholdSettingsCategoryPage);
    }, grow: true);

    screen('household-category-add-dialog', (run) async {
      await openSub(run, l10n.categories, HouseholdSettingsCategoryPage);
      await run.tapTooltip(l10n.addCategory);
      expect(find.byType(TextDialog), findsOneWidget);
    });

    screen('household-category-sheet', (run) async {
      await openSub(run, l10n.categories, HouseholdSettingsCategoryPage);
      await run.tapText('Dairy');
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    screen('household-category-merge-dialog', (run) async {
      await openSub(run, l10n.categories, HouseholdSettingsCategoryPage);
      await run.tapText('Dairy');
      await run.tap(find.widgetWithText(ActionChip, l10n.merge));
      expect(find.byType(SelectDialog<Category>), findsOneWidget);
    });

    screen('household-category-delete-confirmation', (run) async {
      await openSub(run, l10n.categories, HouseholdSettingsCategoryPage);
      await run.tapText('Dairy');
      await run.tap(find.widgetWithText(ActionChip, l10n.delete));
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    screen('household-tags', (run) async {
      await openSub(run, l10n.tags, HouseholdSettingsTagsPage);
    }, grow: true);

    screen('household-tag-add-dialog', (run) async {
      await openSub(run, l10n.tags, HouseholdSettingsTagsPage);
      await run.tapTooltip(l10n.addTag);
      expect(find.byType(TextDialog), findsOneWidget);
    });

    screen('household-tag-sheet', (run) async {
      await openSub(run, l10n.tags, HouseholdSettingsTagsPage);
      await run.tapText('Vegetarian');
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    screen('household-expense-categories', (run) async {
      await openSub(
          run, l10n.expenseCategories, HouseholdSettingsExpenseCategoryPage);
    }, grow: true);

    screen('household-expense-category-new', (run) async {
      await openSub(
          run, l10n.expenseCategories, HouseholdSettingsExpenseCategoryPage);
      await run.tapIcon(Icons.add);
      expect(find.byType(AddExpenseCategoryPage), findsOneWidget);
    }, grow: true);

    screen('household-expense-category-sheet', (run) async {
      await openSub(
          run, l10n.expenseCategories, HouseholdSettingsExpenseCategoryPage);
      await run.tapText('Eating out');
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    screen('household-expense-category-color-dialog', (run) async {
      await openSub(
          run, l10n.expenseCategories, HouseholdSettingsExpenseCategoryPage);
      await run.tapText('Eating out');
      await run.tapText(l10n.colorSelect);
      expect(find.byType(KitchenOwlColorPickerDialog), findsOneWidget);
    });

    screen('server-users', (run) async {
      await openSettings(run);
      await run.tap(find.widgetWithText(ListTile, l10n.users));
      expect(find.byType(SettingsServerUserPage), findsOneWidget);
      expect(find.text('Sam Okafor'), findsOneWidget);
    }, grow: true);

    screen('server-user-new', (run) async {
      await openSettings(run);
      await run.tap(find.widgetWithText(ListTile, l10n.users));
      await run.tapTooltip(l10n.userAdd);
      expect(find.byType(CreateUserPage), findsOneWidget);
    });

    screen('server-user-detail', (run) async {
      await openSettings(run);
      await run.tap(find.widgetWithText(ListTile, l10n.users));
      await run.tapText('Sam Okafor');
      expect(find.byType(SettingsUserPage), findsOneWidget);
    }, grow: true);

    screen('server-user-delete-confirmation', (run) async {
      await openSettings(run);
      await run.tap(find.widgetWithText(ListTile, l10n.users));
      await run.tester.drag(find.text('Sam Okafor'), const Offset(-600, 0));
      await run.settle();
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    screen('server-analytics', (run) async {
      await openSettings(run);
      await run.tap(find.widgetWithText(ListTile, 'Analytics'));
      expect(find.byType(AnalyticsPage), findsOneWidget);
    }, grow: true);

    screen('server-reports', (run) async {
      await openSettings(run);
      await run.tap(find.widgetWithText(ListTile, 'Reports'));
      expect(find.byType(ReportsListPage), findsOneWidget);
    }, grow: true);

    screen('household-leave-confirmation', (run) async {
      await openSettings(run);
      await run.tap(find.widgetWithText(ListTile, l10n.householdLeave));
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  // Declared last: by now every `screen` above has added its id.
  test('route coverage', () async {
    final discovered = [
      for (final spec in await GoRouterSource(app_router.router).discover())
        spec.id,
    ];
    expect(routeCoverage.keys.toSet(), discovered.toSet(),
        reason: 'The app\'s routes changed: update routeCoverage and '
            'README.md');
    for (final MapEntry(key: route, value: screens) in routeCoverage.entries) {
      expect(declaredScreens, containsAll(screens),
          reason: 'routeCoverage[$route] names a screen that does not exist');
    }
  });
}
