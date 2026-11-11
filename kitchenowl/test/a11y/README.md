# Runtime accessibility audit (a11y-dogfood branch)

This directory is not part of upstream KitchenOwl. It is a dogfood of
[flutter-a11y](https://github.com/coryj627/flutter-a11y) (private): a widget
test that launches the real app against a fake of the KitchenOwl server, walks
to each screen as a user would, and records what `flutter_a11y_test` finds on
the rendered semantics tree.

The findings are meant to be labelled by people afterwards. So the test
**records** findings and never asserts on them: no rule is disabled, no screen
is skipped, and a screen with findings passes.

**This is not a browser run.** KitchenOwl ships for the web, Android and iOS.
Widget tests run on the Dart VM with Flutter's test renderer, not in a browser,
so nothing here exercises the DOM, the browser's accessibility tree or a real
screen reader. What the audit sees is Flutter's semantics tree, which is the
input to all of those. To cover the layout web users get, every screen is
audited in two windows: a phone and a desktop-browser-sized one (see
"Viewports").

## Run it

```sh
cd kitchenowl
flutter pub get            # needs read access to coryj627/flutter-a11y
flutter test test/a11y     # about 2.5 minutes
```

Outputs, both git-ignored (`.a11y/.gitignore`):

- `.a11y/flutter/runtime-findings.json`: the findings, in the format
  `a11y_check_flutter scan` reads.
- `.a11y/flutter/runtime-screens.json`: one entry per screen id with the view
  size it was audited at, how far its lists could still scroll, the finding
  count per rule, audit diagnostics, exceptions caught while the screen was
  pumped, requests the fake server had no answer for, text that was drawn in
  the test font, and notes on how the screen was reached.

Both files are merged into, not replaced: delete them before a run whose
numbers you want to quote (a screen id that no longer exists would otherwise
stay in them).

Options, as environment variables:

- `A11Y_SCREENSHOT_DIR=/some/dir` also writes a PNG of each screen as it was
  audited (and `<id>.NOT-REACHED.png` when a screen's steps fail). Use it to
  check by eye that a screen is the one its id says.
- `A11Y_TEST_FONT=ahem` skips loading real fonts, to compare with the default
  test font.

Two consecutive runs on one machine (macOS, Flutter 3.47.9) produced
byte-identical output files: 5,980 findings on 296 screen ids.

The dependencies are two git packages of flutter-a11y, pinned in
`pubspec.yaml` to tag `0.4.2`. Since 0.4.0 the packages read apps built on
`package:material_ui`, which this app is; the 0.3.0 tag does not. 0.4.1 keeps
a screen's findings when one of the audit's reflow passes is aborted (see
"Exceptions are recorded, not hidden"); 0.4.2 also names, as failures, the
passes not attempted after the view could not be restored (none here). Five packages the app already resolved transitively are named as dev
dependencies because the fakes import them (`file`, `flutter_cache_manager`,
and three plugin platform interfaces). `pubspec.lock` gained `auto_route`
(a dependency of `flutter_a11y_routes`) and the flutter-a11y packages; no
existing package changed version. No file under `lib/` and no existing test
was changed.

## How a screen is pumped

`screens_a11y_test.dart` has one `testWidgets` per screen id. Each one:

1. puts the device in a starting state (`Launch`): a server address and a
   sign-in token saved or not, the household last opened, any settings;
2. installs the fakes (next section) and pumps the real `App()` from
   `lib/app.dart`, so the theme, localizations, router and cubits are the
   app's;
3. reaches the screen with taps, long presses, drags and typed text;
4. calls `auditScreen`;
5. takes the app down.

Six ids are opened by a URL instead of a tap, because a link is how a user
gets there too: `reset-password` and `confirm-email` (links in an email),
`recipe-shared-link-signed-out` (a shared recipe), `page-not-found`, and
`tutorial` / `tutorial-recipes` (see "Not audited"). No screen is a stub and
no page is pushed by the test.

## What had to be faked

The repository has no mock of its server and no widget test that pumps a
screen. Everything in `support/` was written for this audit.

**The server (`support/fake_server.dart`, `support/fake_http.dart`).** The
seam is `dart:io`'s `HttpClient`, through `HttpOverrides.global`. It is the
lowest seam there is, and the only one that needs no change to `lib/`:
`ApiService` has a private constructor, keeps its instance in a private
static, builds its client itself (`IOClient(HttpClient())`), and its endpoints
are extension methods, which cannot be overridden. So the fake answers HTTP
requests with JSON shaped like the routes under `backend/app/controller/`
(checked against the app's `fromJson` factories, and against the backend's
handlers for the health and expense-overview routes). It was not checked
against a running backend.

The data is one household that looks like a real one: three members with
balances, a second household, two shopping lists (13 items in seven
categories, 9 recent items), 27 known items with icons, six tags, eight
recipes with ingredients, steps, tags, times and (six of them) a photo, five
planned meals, 13 expenses in four categories over two months, six community
recipes of four other households, three sessions, four server accounts, two
abuse reports and server analytics. `FakeServer(populated: false)` is the same
household just created, with nothing in it. Writes are acknowledged and not
stored: after "save" the app re-reads the same data.

Things about the fake that affect what is on screen:

- It answers after 30 ms of the test's fake clock. With no delay the sign-in
  finishes before the router has placed its first page, the app takes a
  different path (it lands on the household list and forgets the last
  household), and no device behaves like that.
- The signed-in user, Maria, is the household's owner and a **server
  administrator**, so the admin-only parts are on screen (server users,
  analytics, reports, "Advanced recipes control", edit and delete on other
  households' recipes).
- The server reports open registration, mandatory email (which is what shows
  "Forgot password?"), two single sign-on providers (a custom one and Google)
  and AI recipe generation. Apple sign-in is left out because the app shows
  that button only when the **host** running the test is macOS or iOS.
- **Dates are real.** The app reads `DateTime.now()`, which a widget test
  cannot replace, so the fake lays its data out around the real date: the
  plan starts today, expenses run back from today. Weekday names, "Today",
  dates and the month charts therefore change from day to day, and so does
  any finding whose text or fingerprint contains them. Runs on the same day
  are identical.
- There is no web socket. The app's live-update connection fails at once and
  it carries on with the refreshes it does when a page is opened.

**Images (`FakeImageCache`).** Every image goes through
`CachedNetworkImageProvider`, whose default cache manager needs sqflite, a
temporary directory and real file I/O. `CachedNetworkImageProvider
.defaultCacheManager` is a settable static, so the harness swaps in a manager
that answers any URL with a generated PNG: a two-colour diagonal gradient
chosen by the file name (480x320, or 96x96 for avatars). The engine still
decodes it. Consequences: a photo is a gradient, not food, so contrast
measured for text over a photo (a recipe's title, the buttons over it) is
contrast against that gradient; and blurhash placeholders are never shown.

**The device (`support/fake_platform.dart`).**

- `path_provider` and the files under it. The app keeps an offline copy of the
  user, households, lists and recipes in `dart:io` files. Real file I/O never
  completes on a widget test's fake clock, so an `IOOverrides` serves the
  app's cache and support directories from memory. This is what makes the
  offline screens work.
- `shared_preferences` (the test API of the package), `flutter_secure_storage`
  (its test API), `package_info_plus` (version 0.8.1, build 126),
  `device_info_plus`, `wakelock_plus`, the `dynamic_color` channel (no Material
  You palette) and the `url_launcher` channels (answered, nothing opens).
- The preferences store is created once per isolate, outside any test. The
  app's `PreferenceStorage` keeps a `Future<SharedPreferences>` for the life
  of the isolate; created inside a test it belongs to that test's fake-async
  zone and every later test hangs on the splash page waiting for it. Created
  outside, its listeners run when real time passes, which is why `settle()`
  lets a millisecond of real time pass between pumps.

**App globals reset between tests:** `ApiService` (disposed), `MemStorage`
(cleared), the router's location and `initialLocation`. `AuthCubit` is closed
at the end of each test so that it stops listening to the API client.

## Screens audited

149 screens and states. 147 are audited in both windows, 1 on the phone only
and 1 in the wide window only: 296 ids, each `<screen>@phone` or
`<screen>@wide`.

Of the 58 widget classes under `lib/pages/`, 57 are on screen in at least one
id; the one that is not is `LoginRedirectPage`. Of the 27 go_router routes,
26 have the page they build on screen in at least one id (`routeCoverage` in
the test file, checked against `GoRouterSource(router).discover()` by the
`route coverage` test, so a route added upstream fails until it is placed);
`/signin/redirect` does not. The routes are not pumped from that list: most
need a session, a household and data, and the app opens several of these
pages without the router on a phone (an `OpenContainer` transition).

First run and signing in

- `splash-loading`
- `sign-in` (a self-hosted server), `sign-in-default-server`,
  `sign-in-server-menu`, `sign-in-wrong-password` (with its snack bar)
- `server-setup`, `server-setup-empty-address-error`
- `sign-up`, `sign-up-validation-errors`
- `forgot-password`, `reset-password`, `confirm-email`
- `onboarding`, `onboarding-validation-errors` (first account on a new server)
- `tutorial`, `tutorial-recipes`

Connection states

- `server-unreachable`, `server-unreachable-menu`
- `unsupported-server-too-old`, `unsupported-app-too-old`,
  `unsupported-app-too-old-signed-in` (offers offline mode)
- `shopping-list-offline`, `recipes-offline`, `balances-offline`,
  `settings-offline` (the connection is lost while signed in; the app shows
  its cached copy)
- `recipes-loading` (placeholders while the server is slow)
- `page-not-found`

Households

- `household-chooser`, `household-chooser-empty`, `household-leave-sheet`
- `household-new`, `household-new-language-sheet`,
  `household-new-member-search`
- `household-more-sheet` (phone only: the "More" destination),
  `household-drawer` (wide only, at 800 px: see "Viewports")
- `household-about` (another household's public page)

Shopping list

- `shopping-list`, `shopping-list-empty`, `shopping-list-by-category`,
  `shopping-list-as-list`, `shopping-list-second-list`
- `shopping-list-search`, `shopping-list-search-new-item`
- `shopping-list-items-marked` (with "Remove item interaction: Confirm")
- `item-detail`, `item-link-sheet`, `item-menu`, `item-icon-selection`,
  `item-rename-dialog`, `item-merge-search`, `item-delete-confirmation`

Recipes

- `recipes`, `recipes-empty`, `recipes-as-cards`, `recipes-filtered-by-tag`,
  `recipes-search`, `recipes-search-no-results`, `recipes-add-menu`,
  `recipes-discover`
- `recipe-detail`, `recipe-detail-no-photo`, `recipe-detail-community`,
  `recipe-shared-link-signed-out`, `recipe-photo`
- `recipe-more-menu`, `recipe-report-dialog`, `recipe-delete-confirmation`
  (on another household's recipe)
- `recipe-choose-shopping-list-dialog`, `recipe-plan-date-picker`
- `recipe-cooking-first-step`, `recipe-cooking-second-step`
- `recipe-new`, `recipe-edit`, `recipe-edit-visibility-help`,
  `recipe-edit-new-tag-dialog`, `recipe-edit-add-ingredients`,
  `recipe-edit-ingredient`, `recipe-edit-unsaved-changes-dialog`,
  `recipe-edit-delete-confirmation`
- `recipe-add-from-url-dialog`, `recipe-import-from-url` (matching scraped
  ingredients to items), `recipe-import-review`
- `recipe-generate` (the prompt page)

Meal planner

- `planner`, `planner-empty`, `planner-add-items`, `planner-recent-recipes`,
  `planner-plan-date-picker`, `planner-recipe-from-plan`

Expenses

- `balances`, `balances-empty`, `balances-personal`, `balances-search`,
  `balances-category-filter`
- `expense-overview`, `expense-overview-category-month`
- `expense-detail`, `expense-detail-with-receipt`
- `expense-new`, `expense-new-validation-error`, `expense-edit`,
  `expense-date-picker`, `expense-time-picker`
- `expense-category-menu`, `expense-paid-by-menu` (in the wide window with
  their 320 px reflow pass aborted: see "Exceptions are recorded, not hidden")

Settings

- `settings` (one page: appearance, shopping-list options, household, server,
  about), `settings-without-household`
- `settings-account`, `settings-account-menu`,
  `settings-account-delete-confirmation`, `settings-password`,
  `settings-email`, `settings-linked-accounts`
- `settings-sessions`, `settings-session-sheet`, `settings-token-warning`,
  `settings-token-name-dialog`
- `household-members`, `household-member-sheet`,
  `household-member-report-dialog`, `household-member-add-search`,
  `household-member-remove-confirmation`, `household-leave-confirmation`
- `household-settings`, `household-settings-currency-picker`,
  `household-delete-confirmation`
- `household-items`, `household-item-detail`
- `household-shopping-lists`, `household-shopping-list-add-dialog`,
  `household-shopping-list-sheet`
- `household-categories`, `household-category-add-dialog`,
  `household-category-sheet`, `household-category-merge-dialog`,
  `household-category-delete-confirmation`
- `household-tags`, `household-tag-add-dialog`, `household-tag-sheet`
- `household-expense-categories`, `household-expense-category-new`,
  `household-expense-category-sheet`,
  `household-expense-category-color-dialog`
- `server-users`, `server-user-new`, `server-user-detail`,
  `server-user-delete-confirmation`, `server-analytics`, `server-reports`

### Not audited, with the reason

| Screen or state | Why |
|---|---|
| Single sign-on return (`/signin/redirect`, `LoginRedirectPage`) | Needs a round trip through an identity provider in a browser. |
| The tutorial as shown after onboarding | After the first account is created the app pushes `/tutorial` and, on the same state change, goes to the household list. In the harness the second navigation wins and the tutorial is never on screen. `tutorial` and `tutorial-recipes` are opened by URL instead; only two of its pages are audited. |
| Generated recipe (the answer of "Generate recipe with AI") | Needs a streamed response from a language model. The prompt page is audited. |
| Image pickers (recipe photo, receipt, household and profile picture), the import file picker and the import-options dialog behind it, export, share | Operating-system UI; `file_picker` and `image_picker` have no implementation under `flutter test` (`pickFile() has not been implemented.`). On a desktop host the app goes straight to the file picker, so its own "Camera / Gallery" dialog is not reachable either. |
| Open-source licenses | Flutter's own `LicensePage`. Not attempted. |
| Rename, merge and delete dialogs for tags, shopping lists and expense categories; budget dialog | Same widgets as the category ones that are audited. Not set up. |
| A household whose language can still be changed, in household settings | The fixture's household has a language, which the app then shows as fixed text. The language sheet is audited from "New household". |
| Swipe-to-delete backgrounds, snack bars other than "Wrong username or password", pull-to-refresh | Transient. Not set up. |
| The splash page's "taking longer than expected" state, an unverified email with "Resend verification email", linked single sign-on accounts, a household the user cannot administer, a non-admin user | Not in the fixture. |
| Tablet widths (600 to 950 px) | Only `household-drawer` is audited there. |
| Dark theme, accent colours, languages other than English, right-to-left | Light theme and English only. |
| iOS and web rendering | Every screen is pumped as Android (the test default), on the VM. Code behind `kIsWeb` is not reached: on the web the app has no server setup page, no "Switch server", and no "Keep screen on" or "Force offline mode" settings. Those are audited here as the mobile app shows them. |

## Harness decisions that affect findings

**Viewports.** Two, with distinct ids:

- `@phone`: 412x915 logical px at device pixel ratio 3, the same as
  `tool/score_realapps_runtime` in flutter-a11y.
- `@wide`: 1280x800 at device pixel ratio 1, a desktop browser window. The app
  switches layout by width (`responsive_builder`: below 600 px a bottom
  navigation bar, from 950 px an extended navigation rail, two-column recipe
  page, pie chart beside the expense list). `responsive_builder` decides by
  the window's **width** on the web and on desktop hosts, and by its shortest
  side on phones; the test host is a desktop, so the wide window gets the
  layout the web gets.

`household-drawer@wide` is audited at 800x800: the drawer exists only between
600 and 950 px, where the rail is collapsed behind a menu button.

**Growing the view over lazy lists.** For the full-page screens declared with
`grow: true` the view's height is increased until no vertical scrollable has
anything left to scroll (at most 6000 px), so a lazily built list or grid is
in the semantics tree in full. Dialogs, sheets, menus and search states are
audited at the window's own height, because their size and position depend on
it. The shopping list is a `NestedScrollView`, whose header can always be
scrolled away however tall the view is; growing stops when it no longer
helps, and those ids keep `remainingScrollPx` of 78 (phone) or 46 (wide),
which is that header and not missing content. Horizontal rows (the planner's
"Recent" and "Suggested", the discover page) are not grown: cards beyond the
window's width are not audited.

**Real fonts.** `flutter_test_config.dart` loads the fonts declared in
`pubspec.yaml` (Roboto in twelve styles, and the item icon font) plus
MaterialIcons from the Flutter SDK's cache.

**Chip labels are given Roboto.** The app's theme sets
`chipTheme.labelStyle: TextStyle(color: ...)`, with no font family, and a
chip replaces the inherited text style with it. On Android and in Flutter's
web renderer text without a family is drawn in the platform default, Roboto.
Under `flutter test` the default is the engine's built-in test font (every
glyph a 1 em square), and no font loaded at run time can take its place:
registering Roboto as `FlutterTest` or `Ahem` changes text that asks for those
names, not text that asks for none. Every chip in the app (tags, times,
ingredient chips in recipe steps, shopping-list tabs, filters) was drawn as a
row of squares. So the harness wraps the app in a `ChipTheme` holding the
app's own light chip theme with `fontFamily: 'Roboto'` added and nothing else
changed (`withDeviceChipFont`). This is the one place the harness puts a
widget above `App()`.

Two screens still have text in the test font, listed under `textInTestFont`
in `runtime-screens.json`: `server-reports` (the date, author and reason of
each report) and `recipe-edit-visibility-help` (the dialog's body). Both are
bare `RichText` widgets with no style at all. An overflow finding on that
text needs a second look; a contrast finding does not depend on the font.
(In the app that text is also white on a light surface, `RichText`'s default
colour, which is a defect of the app and not of the harness.)

**Real shadows.** `flutter test` draws every shadow as a solid black outline
(`debugDisableShadows`), which puts a black ring round every card, menu, sheet
and floating button. The harness turns that off, so contrast is measured
against what the app paints.

**No debug banner.** `WidgetsApp.debugAllowBannerOverride = false` (the app
also turns it off itself).

**Audit configuration.** `A11yAuditConfig(platform: null, reflow: true,
sourceRoots: ['<checkout>/lib/'])`: library defaults, both platform tap-target
guidelines (so a control under 44 px is reported twice, in both windows), the
200 % text scale and 320 px reflow passes, and attribution restricted to the
app's `lib/` so a finding is never attributed to this harness. The wide window
is audited with the touch guidelines too: the web app is used on touch
screens, and dropping the rule there would be weakening the audit.

**Exceptions are recorded, not hidden.** While a screen is reached and
audited the harness collects what the framework reports
(`FlutterError.onError`) and stores it on the screen's entry in
`runtime-screens.json` under `exceptions`, then audits anyway.

The same key holds the audit's aborted reflow passes, one entry each, as
`reflow pass aborted (<pass>): <error>`. When the app raises an error that is
not an overflow while `auditScreen` re-lays the screen out at 200 % text or at
320 px, flutter-a11y (from 0.4.1) aborts that pass, runs the others and throws
`A11yReflowException`; the harness keeps `exception.result` as the screen's
result (it is already in `runtime-findings.json`) and logs
`exception.failures`. The aborted pass contributes no finding, so its rule is
unchecked on that screen; the screen's `diagnostics` then include
`reflow-pass-aborted`. Any other exception from `auditScreen` still fails the
test. Two ids have an aborted pass: `expense-category-menu@wide` and
`expense-paid-by-menu@wide`. Their 320 px pass narrows the 1280x800 window to
portrait, Material's `DropdownButton` dismisses its open menu when the
orientation changes, from inside `build`, and the framework asserts
(`setState() or markNeedsBuild() called during build`, from
`_DropdownButtonState.build` → `_removeDropdownRoute` →
`NavigatorState.removeRoute`). Until 0.4.0 that error left `auditScreen` with
nothing recorded and the two ids were not audited. On the phone the window
stays portrait and both menus are audited in full.

Apart from those two, no screen recorded an exception, and no request went
unanswered. A failure to *reach* a screen (a
finder that matches nothing) does fail the test: that is a broken harness, not
evidence about the screen.

**Long presses.** On an item card the name is wrapped in a `Tooltip`, whose
long press wins over the card's: holding the name shows a tooltip with the
name, holding the picture opens the item. The harness holds the picture.

## Things about the app that got in the way

- No seam for the API client, the image cache manager aside (see above).
- Singletons that outlive the widget tree: `ApiService`, `MemStorage`,
  `PreferenceStorage`, `TempStorage`, the top-level `router` and
  `initialLocation`. The cubits `App` creates are never closed.
- `PreferenceStorage` caches a future (see "What had to be faked").
- `DateTime.now()` is read directly.
- Host checks (`Platform.isIOS || Platform.isMacOS`, `Platform.isAndroid`)
  decide what is on screen, so a widget test shows what the **host** would.
  With this fixture the only visible case is the Apple sign-in button, which
  the fake server does not offer.

## Not verified

- **Linux.** The audit was written and run on macOS only.
  `device_info_plus` picks its model class by host, and the fake answers
  differently on Linux; `responsive_builder` treats macOS, Linux and Windows
  hosts alike. The workflow below runs on `ubuntu-latest` and has never run.
- **The CLI.** `a11y_check_flutter scan` was not run against these files.
- **The fake against a real backend.** See "What had to be faked".

## CI

`.github/workflows/a11y-check-flutter.yml` (at the repository root, with
`working-directory: kitchenowl`) and `.a11y/a11y-check-flutter.yaml` are
prepared and have never run: nothing on this branch has been pushed, and no
`.a11y/flutter/baseline.json` has been accepted. With the config's
`fail_at: info` and no baseline, expect the first scan to fail on every
finding until a baseline is committed. Because the fixture's dates follow the
real date, a baseline made on one day will not match a run on another for the
findings whose text contains a date.
