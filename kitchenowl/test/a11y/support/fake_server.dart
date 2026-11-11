/// A stand-in for the KitchenOwl backend, answering the app's REST requests
/// with JSON shaped like the real routes under `backend/app/controller/`.
///
/// The repository has no mock of its server, so this one was written for the
/// audit.  The data is a small household that looks like a real one: three
/// members, two shopping lists, eight recipes, a week of planned meals and
/// two months of expenses.  See `../README.md`, "What had to be faked".
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One answer of the [FakeServer].
class Reply {
  const Reply(this.status, this.body);

  Reply.json(Object? data, [this.status = 200]) : body = jsonEncode(data);

  static const Reply done = Reply(200, '{"msg":"DONE"}');
  static const Reply unauthorized = Reply(401, '{"msg":"Unauthorized"}');
  static const Reply notFound = Reply(404, '{"msg":"Not found"}');

  final int status;
  final String body;
}

/// What the server at the configured address is like.
enum ServerState {
  /// A current server with accounts on it.
  ready,

  /// A freshly installed server with no account yet: the app shows its
  /// onboarding page, which creates the first (admin) account.
  fresh,

  /// A server older than the app supports.
  tooOld,

  /// A server newer than the app supports.
  tooNew,
}

class FakeServer {
  FakeServer({
    this.state = ServerState.ready,
    this.populated = true,
    this.reachable = true,
    this.openRegistration = true,
    this.member = true,
    DateTime? now,
  }) : now = now ?? DateTime.now();

  /// The address the app is pointed at (its `URL` preference).
  static const String url = 'https://kitchen.example.org';

  /// The saved sign-in token of [me].
  static const String refreshToken = 'refresh-maria';
  static const String _accessToken = 'access-maria';

  /// The account the sign-in form accepts.
  static const String username = 'maria';
  static const String password = 'correct horse battery staple';

  /// Not final: a server can be upgraded while the app is open.
  ServerState state;

  /// False for a household that was just created: no items on the list, no
  /// recipes, no plan, no expenses.
  final bool populated;

  /// False when nothing answers at [url] (every request is refused).
  bool reachable;

  /// How long the server takes to answer, on the test's fake clock.  With no
  /// latency at all the sign-in finishes before the app's router has placed
  /// its first page, which no device does.
  Duration latency = const Duration(milliseconds: 30);

  final bool openRegistration;

  /// False for an account that belongs to no household yet.
  final bool member;

  /// Single sign-on providers the server offers on its sign-in page.  (Apple
  /// is left out: the app shows that button only when the HOST running the
  /// test is macOS or iOS, which would make the screen differ between
  /// machines.)
  final List<String> oidcProviders = const ['custom', 'google'];

  /// Whether the server has an AI model configured for "Generate recipe".
  final bool recipeGeneration = true;

  /// "Now" for every date in the data.  The app reads the real clock
  /// (`DateTime.now()`), so the data is laid out around the real date.
  final DateTime now;

  /// Requests the server had no answer for.  The harness reports them per
  /// screen: an entry means the screen was pumped with a failed request.
  final List<String> unhandled = [];

  /// Every request, in order (`METHOD /path?query`).
  final List<String> requests = [];

  // ---------------------------------------------------------------- data

  static const int householdId = 1;

  int _ms(DateTime t) => t.toUtc().millisecondsSinceEpoch;

  DateTime get _today => DateTime(now.year, now.month, now.day, 12);

  Map<String, Object?> _member(int id, String username, String name,
          {bool owner = false, bool admin = false, double balance = 0}) =>
      {
        'id': id,
        'username': username,
        'name': name,
        'photo': 'user-$id.png',
        'owner': owner,
        'admin': admin,
        'expense_balance': balance,
      };

  late final List<Map<String, Object?>> members = [
    _member(1, 'maria', 'Maria Jensen',
        owner: true, admin: true, balance: 48.5),
    _member(2, 'jonas', 'Jonas Jensen', admin: true, balance: -31.25),
    _member(3, 'aiko', 'Aiko Tanaka', balance: -17.25),
  ];

  late final Map<String, Object?> me = {
    'id': 1,
    'username': 'maria',
    'name': 'Maria Jensen',
    'email': 'maria@example.org',
    'email_verified': true,
    'photo': 'user-1.png',
    'admin': true,
    'oidc_links': <String>[],
    'tokens': [
      {
        'id': 11,
        'name': 'Pixel 8',
        'type': 'refresh',
        'created_at': _ms(_today.subtract(const Duration(days: 40))),
        'last_used_at': _ms(_today),
      },
      {
        'id': 12,
        'name': 'Firefox on Linux',
        'type': 'refresh',
        'created_at': _ms(_today.subtract(const Duration(days: 12))),
        'last_used_at': _ms(_today.subtract(const Duration(days: 2))),
      },
      {
        'id': 13,
        'name': 'Home Assistant',
        'type': 'llt',
        'created_at': _ms(_today.subtract(const Duration(days: 90))),
        'last_used_at': _ms(_today.subtract(const Duration(days: 1))),
      },
    ],
  };

  /// Every account on the server, for the admin's user list.
  late final List<Map<String, Object?>> users = [
    me,
    {
      'id': 2,
      'username': 'jonas',
      'name': 'Jonas Jensen',
      'email': 'jonas@example.org',
      'email_verified': true,
      'photo': 'user-2.png',
      'admin': false,
    },
    {
      'id': 3,
      'username': 'aiko',
      'name': 'Aiko Tanaka',
      'email': 'aiko@example.org',
      'email_verified': false,
      'photo': 'user-3.png',
      'admin': false,
    },
    {
      'id': 4,
      'username': 'sam',
      'name': 'Sam Okafor',
      'email': 'sam@example.org',
      'email_verified': true,
      'photo': null,
      'admin': false,
    },
  ];

  Map<String, Object?> _category(int id, String name, int ordering) =>
      {'id': id, 'name': name, 'ordering': ordering};

  late final List<Map<String, Object?>> categories = populated
      ? [
          _category(1, 'Fruits and vegetables', 0),
          _category(2, 'Bread and pastries', 1),
          _category(3, 'Dairy', 2),
          _category(4, 'Meat and fish', 3),
          _category(5, 'Pantry', 4),
          _category(6, 'Beverages', 5),
          _category(7, 'Household', 6),
        ]
      : [];

  Map<String, Object?>? _categoryById(int? id) =>
      id == null ? null : categories.firstWhere((c) => c['id'] == id);

  Map<String, Object?> _item(int id, String name, String? icon, int? category,
          {int ordering = 0}) =>
      {
        'id': id,
        'name': name,
        'icon': icon,
        'ordering': ordering,
        'default': icon != null,
        'default_key': icon,
        'category': _categoryById(category),
      };

  /// Every item the household knows.
  late final List<Map<String, Object?>> items = populated
      ? [
          _item(1, 'Tomatoes', 'tomato', 1),
          _item(2, 'Bananas', 'banana', 1),
          _item(3, 'Onions', 'onion', 1),
          _item(4, 'Garlic', 'garlic', 1),
          _item(5, 'Carrots', 'carrot', 1),
          _item(6, 'Lemons', 'citrus', 1),
          _item(7, 'Sourdough bread', 'bread', 2),
          _item(8, 'Croissants', 'croissant', 2),
          _item(9, 'Milk', 'milk_carton', 3),
          _item(10, 'Butter', 'butter', 3),
          _item(11, 'Eggs', 'eggs', 3),
          _item(12, 'Parmesan', 'cheese', 3),
          _item(13, 'Chicken thighs', 'chicken', 4),
          _item(14, 'Salmon fillet', 'fish_fillet', 4),
          _item(15, 'Spaghetti', 'pasta', 5),
          _item(16, 'Rice', 'grains_of_rice', 5),
          _item(17, 'Flour', 'flour', 5),
          _item(18, 'Olive oil', 'olive_oil', 5),
          _item(19, 'Red lentils', 'lentil', 5),
          _item(20, 'Coconut milk', 'coconut_milk', 5),
          _item(21, 'Coffee beans', 'coffee_beans', 6),
          _item(22, 'Sparkling water', 'water', 6),
          _item(23, 'Dish soap', 'soap_dispenser', 7),
          _item(24, 'Toilet paper', 'toilet_paper', 7),
          _item(25, 'Basil', 'basil', 1),
          _item(26, 'Ginger', 'ginger', 1),
          _item(27, 'Birthday candles', 'candle', null),
        ]
      : [];

  Map<String, Object?> _itemById(int id) =>
      items.firstWhere((i) => i['id'] == id);

  Map<String, Object?> _onList(int id, String description,
          {int by = 1, int hoursAgo = 3}) =>
      {
        ..._itemById(id),
        'description': description,
        'created_by': by,
        'created_at': _ms(now.subtract(Duration(hours: hoursAgo))),
      };

  Map<String, Object?> _recent(int id, [String description = '']) =>
      {..._itemById(id), 'description': description};

  late final List<Map<String, Object?>> shoppingLists = [
    {
      'id': 1,
      'name': 'Groceries',
      'items': populated
          ? [
              _onList(1, '6'),
              _onList(2, '1 bunch', by: 2),
              _onList(3, '1 kg'),
              _onList(7, '', by: 3, hoursAgo: 26),
              _onList(9, '2 l', by: 2),
              _onList(11, '12'),
              _onList(12, '200 g'),
              _onList(13, '800 g', by: 2, hoursAgo: 50),
              _onList(15, '500 g'),
              _onList(18, ''),
              _onList(21, '250 g, whole beans', by: 3),
              _onList(23, ''),
              // A pasted product link: the app offers "Open URL" for it.
              _onList(27, 'https://shop.example.org/candles', by: 2),
            ]
          : <Object>[],
      'recentItems': populated
          ? [
              _recent(5),
              _recent(10, '250 g'),
              _recent(16, '1 kg'),
              _recent(6),
              _recent(22, '6 bottles'),
              _recent(4),
              _recent(17),
              _recent(24),
              _recent(14, '2'),
            ]
          : <Object>[],
    },
    if (populated)
      {
        'id': 2,
        'name': 'Hardware store',
        'items': [
          {
            'id': 40,
            'name': 'Wood screws',
            'icon': null,
            'ordering': 0,
            'default': false,
            'default_key': null,
            'category': null,
            'description': '4 x 40 mm',
            'created_by': 2,
            'created_at': _ms(now.subtract(const Duration(days: 2))),
          },
        ],
        'recentItems': <Object>[],
      },
  ];

  Map<String, Object?> _tag(int id, String name) => {'id': id, 'name': name};

  late final List<Map<String, Object?>> tags = populated
      ? [
          _tag(1, 'Vegetarian'),
          _tag(2, 'Quick'),
          _tag(3, 'Dinner'),
          _tag(4, 'Baking'),
          _tag(5, 'Soup'),
          _tag(6, 'Breakfast'),
        ]
      : [];

  Map<String, Object?> _tagById(int id) =>
      tags.firstWhere((t) => t['id'] == id);

  Map<String, Object?> _recipeItem(int id, String description,
          {bool optional = false}) =>
      {..._itemById(id), 'description': description, 'optional': optional};

  Map<String, Object?> _recipe(
    int id,
    String name, {
    required String description,
    required List<Map<String, Object?>> items,
    required List<int> tags,
    int prep = 0,
    int cook = 0,
    int yields = 4,
    String source = '',
    bool photo = true,
    int visibility = 0,
    List<int> plannedInDays = const [],
  }) =>
      {
        'id': id,
        'name': name,
        'description': description,
        'time': prep + cook,
        'prep_time': prep,
        'cook_time': cook,
        'yields': yields,
        'source': source,
        'photo': photo ? 'recipe-$id.png' : null,
        'photo_hash': null,
        'visibility': visibility,
        'household_id': householdId,
        'planned': plannedInDays.isNotEmpty,
        'planned_cooking_dates': [
          for (final d in plannedInDays) _ms(_utcDay(d)),
        ],
        'items': items,
        'tags': [for (final t in tags) _tagById(t)],
      };

  DateTime _utcDay(int inDays) {
    final d = _today.add(Duration(days: inDays));
    return DateTime.utc(d.year, d.month, d.day);
  }

  late final List<Map<String, Object?>> recipes = populated
      ? [
          _recipe(
            1,
            'Spaghetti al pomodoro',
            description: 'A weeknight classic. The sauce is ready by the '
                'time the pasta is.\n\n'
                '1. Bring a large pot of salted water to the boil and cook '
                'the @spaghetti until al dente.\n'
                '2. Meanwhile, warm the @olive_oil in a wide pan and soften '
                'the sliced @garlic for one minute.\n'
                '3. Add the chopped @tomatoes and simmer for **10 minutes**, '
                'crushing them with a spoon.\n'
                '4. Toss the pasta with the sauce, a ladle of pasta water '
                'and the torn @basil.\n'
                '5. Serve with grated @parmesan.',
            items: [
              _recipeItem(15, '400 g'),
              _recipeItem(1, '800 g'),
              _recipeItem(4, '3 cloves'),
              _recipeItem(18, '3 tbsp'),
              _recipeItem(25, '1 handful'),
              _recipeItem(12, '50 g', optional: true),
            ],
            tags: [1, 2, 3],
            prep: 10,
            cook: 15,
            source: 'https://www.example.org/recipes/spaghetti-al-pomodoro',
            visibility: 2,
            plannedInDays: [0],
          ),
          _recipe(
            2,
            'Red lentil dal',
            description: 'Mild, creamy and better the next day.\n\n'
                '1. Fry the diced @onions, @garlic and grated @ginger in a '
                'little oil until soft.\n'
                '2. Add the rinsed @red_lentils, the @coconut_milk and 500 ml '
                'of water.\n'
                '3. Simmer for 20 minutes, stirring now and then.\n'
                '4. Season with salt and the juice of the @lemons. Serve '
                'with @rice.',
            items: [
              _recipeItem(19, '300 g'),
              _recipeItem(20, '400 ml'),
              _recipeItem(3, '2'),
              _recipeItem(4, '2 cloves'),
              _recipeItem(26, '1 thumb'),
              _recipeItem(6, '1'),
              _recipeItem(16, '300 g', optional: true),
            ],
            tags: [1, 3, 5],
            prep: 10,
            cook: 25,
            plannedInDays: [1],
          ),
          _recipe(
            3,
            'Lemon roast chicken',
            description: '1. Heat the oven to 200 °C.\n'
                '2. Rub the @chicken_thighs with @olive_oil, salt and '
                'pepper.\n'
                '3. Roast with the halved @lemons, the @carrots and the '
                '@onions for 45 minutes.\n'
                '4. Rest for 5 minutes before serving.',
            items: [
              _recipeItem(13, '800 g'),
              _recipeItem(6, '2'),
              _recipeItem(5, '4'),
              _recipeItem(3, '2'),
              _recipeItem(18, '2 tbsp'),
            ],
            tags: [3],
            prep: 15,
            cook: 45,
            plannedInDays: [3],
          ),
          _recipe(
            4,
            'Banana bread',
            description: 'For the bananas nobody ate.\n\n'
                '1. Mash the @bananas and stir in the melted @butter and '
                'the @eggs.\n'
                '2. Fold in the @flour with a pinch of salt and a teaspoon '
                'of baking soda.\n'
                '3. Bake in a loaf tin at 175 °C for 55 minutes.',
            items: [
              _recipeItem(2, '3, very ripe'),
              _recipeItem(10, '80 g'),
              _recipeItem(11, '2'),
              _recipeItem(17, '250 g'),
            ],
            tags: [4, 6],
            prep: 15,
            cook: 55,
            yields: 10,
            source: 'Grandma Ingrid',
          ),
          _recipe(
            5,
            'Salmon with rice and ginger',
            description: '1. Cook the @rice.\n'
                '2. Sear the @salmon_fillet skin side down for 4 minutes, '
                'turn, and cook 2 minutes more.\n'
                '3. Finish with grated @ginger and a squeeze of @lemons.',
            items: [
              _recipeItem(14, '2'),
              _recipeItem(16, '200 g'),
              _recipeItem(26, '1 thumb'),
              _recipeItem(6, '1/2'),
            ],
            tags: [2, 3],
            prep: 5,
            cook: 20,
            yields: 2,
            plannedInDays: [4],
          ),
          _recipe(
            6,
            'Carrot and ginger soup',
            description: '1. Sweat the @onions in @butter.\n'
                '2. Add the sliced @carrots, the @ginger and 1 l of stock.\n'
                '3. Simmer until soft, then blend until smooth.',
            items: [
              _recipeItem(5, '600 g'),
              _recipeItem(26, '1 thumb'),
              _recipeItem(3, '1'),
              _recipeItem(10, '20 g'),
            ],
            tags: [1, 5],
            prep: 10,
            cook: 30,
            photo: false,
          ),
          _recipe(
            7,
            'Scrambled eggs on sourdough',
            description: '1. Whisk the @eggs with a splash of @milk.\n'
                '2. Melt the @butter over a low heat and stir the eggs '
                'gently until just set.\n'
                '3. Pile onto toasted @sourdough_bread.',
            items: [
              _recipeItem(11, '4'),
              _recipeItem(9, '2 tbsp'),
              _recipeItem(10, '10 g'),
              _recipeItem(7, '2 slices'),
            ],
            tags: [2, 6],
            prep: 2,
            cook: 5,
            yields: 2,
          ),
          _recipe(
            8,
            'Tomato and basil bruschetta',
            description: '1. Dice the @tomatoes and mix with torn @basil, '
                '@olive_oil and salt.\n'
                '2. Toast slices of @sourdough_bread and rub with @garlic.\n'
                '3. Spoon the tomatoes on top.',
            items: [
              _recipeItem(1, '4'),
              _recipeItem(25, '1 handful'),
              _recipeItem(7, '4 slices'),
              _recipeItem(4, '1 clove'),
              _recipeItem(18, '2 tbsp'),
            ],
            tags: [1, 2],
            prep: 10,
            photo: false,
          ),
        ]
      : [];

  Map<String, Object?> _recipeById(int id) =>
      recipes.firstWhere((r) => r['id'] == id);

  /// The plan: one meal on four of the next five days, and one without a day.
  late final List<Map<String, Object?>> plans = populated
      ? [
          {
            'recipe': _recipeById(1),
            'cooking_date': _ms(_utcDay(0)),
            'yields': 4
          },
          {
            'recipe': _recipeById(2),
            'cooking_date': _ms(_utcDay(1)),
            'yields': 4
          },
          {
            'recipe': _recipeById(3),
            'cooking_date': _ms(_utcDay(3)),
            'yields': 6
          },
          {
            'recipe': _recipeById(5),
            'cooking_date': _ms(_utcDay(4)),
            'yields': 2
          },
          {
            'recipe': _recipeById(7),
            'cooking_date': -86400000,
            'yields': null,
          },
        ]
      : [];

  Map<String, Object?> _expenseCategory(int id, String name, int color,
          [double? budget]) =>
      {'id': id, 'name': name, 'color': color, 'budget': budget};

  late final List<Map<String, Object?>> expenseCategories = populated
      ? [
          _expenseCategory(1, 'Groceries', 0xFF2E7D32, 600),
          _expenseCategory(2, 'Household', 0xFF1565C0, 150),
          _expenseCategory(3, 'Eating out', 0xFFEF6C00),
          _expenseCategory(4, 'Utilities', 0xFF6A1B9A, 250),
        ]
      : [];

  Map<String, Object?> _expense(
    int id,
    String name,
    double amount, {
    required int daysAgo,
    required int paidBy,
    int? category,
    List<int> paidFor = const [1, 2, 3],
    String? description,
    bool photo = false,
    bool excluded = false,
  }) =>
      {
        'id': id,
        'name': name,
        'amount': amount,
        'description': description,
        'photo': photo ? 'receipt-$id.png' : null,
        'photo_hash': null,
        'exclude_from_statistics': excluded,
        'category': category == null
            ? null
            : expenseCategories.firstWhere((c) => c['id'] == category),
        'date': _ms(_today.subtract(Duration(days: daysAgo))),
        'paid_by_id': paidBy,
        'paid_for': [
          for (final id in paidFor) {'id': id, 'factor': 1},
        ],
        'household_id': householdId,
      };

  late final List<Map<String, Object?>> expenses = populated
      ? [
          _expense(1, 'Weekly shop', 84.37,
              daysAgo: 0,
              paidBy: 1,
              category: 1,
              description: 'Saturday market and the supermarket',
              photo: true),
          _expense(2, 'Bakery', 12.8, daysAgo: 1, paidBy: 2, category: 1),
          _expense(3, 'Pizza night', 46.5, daysAgo: 2, paidBy: 3, category: 3),
          _expense(4, 'Dishwasher tablets', 9.99,
              daysAgo: 4, paidBy: 1, category: 2),
          _expense(5, 'Electricity', 92.0, daysAgo: 6, paidBy: 2, category: 4),
          _expense(6, 'Weekly shop', 71.14, daysAgo: 7, paidBy: 1, category: 1),
          _expense(7, 'Farmers market', 23.6,
              daysAgo: 9, paidBy: 3, category: 1, paidFor: [1, 3]),
          _expense(8, 'Jonas pays back Maria', 20.0,
              daysAgo: 11, paidBy: 2, paidFor: [1], excluded: true),
          _expense(9, 'Weekly shop', 78.02,
              daysAgo: 14, paidBy: 2, category: 1),
          _expense(10, 'Internet', 39.9, daysAgo: 20, paidBy: 1, category: 4),
          _expense(11, 'Sushi', 58.4, daysAgo: 24, paidBy: 1, category: 3),
          _expense(12, 'Weekly shop', 66.75,
              daysAgo: 35, paidBy: 3, category: 1),
          _expense(13, 'Cleaning supplies', 18.3,
              daysAgo: 41, paidBy: 2, category: 2),
        ]
      : [];

  late final Map<String, Object?> household = {
    'id': householdId,
    'name': 'Jensen family',
    'photo': 'household-1.png',
    'photo_hash': null,
    'language': 'en',
    'currency': 'en_US',
    'planner_feature': true,
    'expenses_feature': true,
    'description': 'Recipes we actually cook, for four hungry people.',
    'link': 'https://jensen.example.org',
    'verified': false,
    'view_ordering': ['items', 'recipes', 'planner', 'balances'],
    'member': members,
    'default_shopping_list': {'id': 1, 'name': 'Groceries'},
  };

  late final List<Map<String, Object?>> households = [
    household,
    {
      'id': 2,
      'name': 'Lake cabin',
      'photo': null,
      'photo_hash': null,
      'language': 'en',
      'currency': null,
      'planner_feature': true,
      'expenses_feature': false,
      'view_ordering': ['items', 'recipes', 'planner', 'balances'],
      'member': [members[0], members[2]],
      'default_shopping_list': {'id': 20, 'name': 'Shopping list'},
    },
  ];

  /// A public recipe of another household, as the discover page lists them.
  Map<String, Object?> _communityRecipe(int id, String name, String household,
          {List<String> tags = const [],
          bool curated = false,
          int time = 30}) =>
      {
        'id': id,
        'name': name,
        'description': '1. Prepare everything.\n2. Cook and serve.',
        'time': time,
        'prep_time': 10,
        'cook_time': time - 10,
        'yields': 4,
        'source': '',
        'photo': 'community-$id.png',
        'photo_hash': null,
        'visibility': 2,
        'household_id': _communityHousehold(household)['id'],
        'server_curated': curated,
        'items': <Object>[],
        'tags': [
          for (final (i, t) in tags.indexed)
            {'id': 500 + id * 10 + i, 'name': t},
        ],
        'household': _communityHousehold(household),
      };

  /// The households behind the community recipes.  The backend sends only
  /// these public fields of a household the user is not a member of.
  Map<String, Object?> _communityHousehold(String name) => const {
        'The Green Kitchen': {
          'id': 201,
          'name': 'The Green Kitchen',
          'photo': 'household-201.png',
          'description': 'Seasonal vegetarian cooking, tested twice.',
          'link': 'https://greenkitchen.example.org',
          'verified': true,
        },
        'Noodle House': {'id': 202, 'name': 'Noodle House', 'photo': null},
        'Budget Bites': {
          'id': 203,
          'name': 'Budget Bites',
          'photo': null,
          'description': 'Dinner for four for under ten euros.',
        },
        'Bread Club': {'id': 204, 'name': 'Bread Club', 'photo': null},
      }[name]!;

  late final List<Map<String, Object?>> community = [
    _communityRecipe(101, 'Shakshuka', 'The Green Kitchen',
        tags: ['Breakfast', 'Vegetarian'], curated: true),
    _communityRecipe(102, 'Miso ramen', 'Noodle House',
        tags: ['Soup'], time: 60),
    _communityRecipe(103, 'Apple crumble', 'The Green Kitchen',
        tags: ['Dessert'], curated: true, time: 50),
    _communityRecipe(104, 'Chickpea curry', 'Budget Bites',
        tags: ['Vegan', 'Dinner']),
    _communityRecipe(105, 'Focaccia', 'Bread Club',
        tags: ['Baking'], time: 120),
    _communityRecipe(106, 'Greek salad', 'Budget Bites',
        tags: ['Quick'], time: 15),
  ];

  // ------------------------------------------------------------- routing

  Reply handle(String method, Uri uri,
      {String? authorization, String body = ''}) {
    final path = uri.path.startsWith('/api') ? uri.path.substring(4) : uri.path;
    requests.add('$method ${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}');
    final reply = _route(method, path, uri, authorization, body);
    if (reply == null) {
      unhandled
          .add('$method ${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}');
      return Reply.notFound;
    }
    return reply;
  }

  Map<String, Object?> get _tokens =>
      {'access_token': _accessToken, 'refresh_token': refreshToken};

  Reply? _route(
      String method, String path, Uri uri, String? auth, String body) {
    final q = uri.queryParameters;
    final get = method == 'GET';

    // The socket.io endpoint for live updates: no web socket here, the app
    // falls back to refreshing when a page is opened.
    if (uri.path.startsWith('/socket.io')) return Reply.notFound;

    if (path.startsWith('/health/')) {
      if (path.endsWith('/supported-languages')) {
        return Reply.json({
          'en': 'English',
          'de': 'Deutsch',
          'es': 'Español',
          'fr': 'Français',
          'nb_NO': 'Norsk bokmål',
          'pt_BR': 'Português (Brasil)',
        });
      }
      return Reply.json({
        'msg': 'OK',
        'version': state == ServerState.tooOld ? 90 : 126,
        'min_frontend_version': state == ServerState.tooNew ? 900 : 71,
        'oidc_provider': oidcProviders,
        if (recipeGeneration) 'llm_recipe_generation': true,
        'privacy_policy': '$url/privacy',
        'terms': '$url/terms',
        if (openRegistration) 'open_registration': true,
        'email_mandatory': true,
      });
    }

    if (path == '/onboarding') {
      if (get) return Reply.json({'onboarding': state == ServerState.fresh});
      return Reply.json(_tokens);
    }

    if (path == '/auth/refresh') {
      return auth == 'Bearer $refreshToken'
          ? Reply.json(_tokens)
          : Reply.unauthorized;
    }
    if (path == '/auth' && method == 'POST') {
      final credentials = jsonDecode(body) as Map<String, Object?>;
      return credentials['username'] == username &&
              credentials['password'] == password
          ? Reply.json(_tokens)
          : Reply.unauthorized;
    }
    if (path == '/auth/signup') {
      return const Reply(400, '{"msg":"Username already taken"}');
    }
    if (path == '/user/forgot-password' ||
        path == '/user/reset-password' ||
        path == '/user/confirm-mail') {
      return Reply.done;
    }

    // A recipe that is public or shared by link can be read by anyone.
    final shared = RegExp(r'^/recipe/(\d+)$').firstMatch(path);
    if (shared != null && method == 'GET' && auth != 'Bearer $_accessToken') {
      final found = [...recipes, ...community].where((r) =>
          r['id'] == int.parse(shared.group(1)!) && r['visibility'] != 0);
      return found.isEmpty ? Reply.unauthorized : Reply.json(found.first);
    }

    // Everything below needs the access token.
    if (auth != 'Bearer $_accessToken') return Reply.unauthorized;

    if (path == '/auth/llt') return Reply.json({'longlived_token': 'llt-new'});

    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final int? id = segments.length > 1 ? int.tryParse(segments[1]) : null;

    switch (segments.first) {
      case 'user':
        if (!get) return Reply.done;
        if (segments.length == 1) return Reply.json(me);
        if (segments[1] == 'all') return Reply.json(users);
        if (segments[1] == 'search') {
          final query = (q['query'] ?? '').toLowerCase();
          return Reply.json([
            for (final u in users)
              if ('${u['name']} ${u['username']}'
                      .toLowerCase()
                      .contains(query) &&
                  u['id'] != 1)
                u,
          ]);
        }
        if (id != null) {
          return Reply.json(
              users.firstWhere((u) => u['id'] == id, orElse: () => users.last));
        }
      case 'household':
        if (segments.length == 1) {
          if (get) return Reply.json(member ? households : <Object>[]);
          // A household was created: answer with a new, empty one.
          final created = jsonDecode(body) as Map<String, Object?>;
          return Reply.json({
            ...households.last,
            'id': 3,
            'name': created['name'],
          });
        }
        if (segments.length == 2) {
          if (!get) return Reply.done;
          final found = [
            ...households,
            for (final r in community) r['household']! as Map<String, Object?>,
          ].where((h) => h['id'] == id);
          return found.isEmpty ? Reply.notFound : Reply.json(found.first);
        }
        return _householdRoute(method, segments.sublist(2), uri, body, id!);
      case 'shoppinglist':
        return Reply.done;
      case 'item':
        if (!get) return Reply.done;
        if (id != null && segments.length == 2)
          return Reply.json(_itemById(id));
        if (id != null && segments[2] == 'recipes') {
          return Reply.json([
            for (final r in recipes)
              if ((r['items']! as List).any((i) => (i as Map)['id'] == id)) r,
          ]);
        }
      case 'category':
        return Reply.done;
      case 'tag':
        if (!get) return Reply.done;
        if (id != null && segments.length == 2) return Reply.json(_tagById(id));
        if (id != null && segments[2] == 'recipes') {
          return Reply.json([
            for (final r in recipes)
              if ((r['tags']! as List).any((t) => (t as Map)['id'] == id)) r,
          ]);
        }
      case 'recipe':
        if (id != null) {
          if (!get) return Reply.done;
          final all = [...recipes, ...community];
          final found = all.where((r) => r['id'] == id);
          return found.isEmpty ? Reply.notFound : Reply.json(found.first);
        }
        if (segments.length > 1 && segments[1] == 'discover') {
          if (segments.length == 2) {
            return Reply.json({
              'popular_tags': [
                'Vegetarian',
                'Dinner',
                'Quick',
                'Baking',
                'Soup'
              ],
              'curated':
                  community.where((r) => r['server_curated'] == true).toList(),
              'popular': community.sublist(1, 5),
              'newest': community.reversed.take(4).toList(),
            });
          }
          final page = int.tryParse(segments.last) ?? 0;
          return Reply.json(page == 0 ? community : <Object>[]);
        }
        if (segments.length > 1 &&
            (segments[1] == 'search' || segments[1] == 'search-tag')) {
          final query = (q['query'] ?? q['tag'] ?? '').toLowerCase();
          if ((int.tryParse(q['page'] ?? '0') ?? 0) > 0) {
            return Reply.json(<Object>[]);
          }
          return Reply.json([
            for (final r in community)
              if (segments[1] == 'search'
                  ? '${r['name']}'.toLowerCase().contains(query)
                  : (r['tags']! as List).any(
                      (t) => '${(t as Map)['name']}'.toLowerCase() == query))
                r,
          ]);
        }
      case 'expense':
        if (segments.length > 1 && segments[1] == 'categories')
          return Reply.done;
        if (id != null) {
          if (!get) return Reply.done;
          final found = expenses.where((e) => e['id'] == id);
          return found.isEmpty ? Reply.notFound : Reply.json(found.first);
        }
      case 'report':
        if (!get) return Reply.done;
        return Reply.json([
          {
            'id': 1,
            'description': 'The photo is not the dish in the recipe.',
            'created_at': _ms(_today.subtract(const Duration(days: 1))),
            'created_by': users[3],
            'recipe': community[1],
          },
          {
            'id': 2,
            'description': 'Sends unwanted invitations.',
            'created_at': _ms(_today.subtract(const Duration(days: 3))),
            'created_by': users[1],
            'user': users[3],
          },
        ]);
      case 'analytics':
        return Reply.json({
          'users': {
            'total': 4,
            'verified': 3,
            'linked_account': 1,
            'online': 2,
            'active': 3,
            'dau': 2,
            'wau': 3,
            'old': 2,
            'old_active': 1,
          },
          'free_storage': 52 * 1024 * 1024 * 1024,
          'available_storage': 128 * 1024 * 1024 * 1024,
          'households': {
            'total': 3,
            'expense_feature': 2,
            'planner_feature': 3,
          },
        });
      case 'upload':
        return Reply.json({'filename': 'upload.png'});
      case 'auth':
        return Reply.done;
    }
    return get ? null : Reply.done;
  }

  Reply? _householdRoute(
      String method, List<String> rest, Uri uri, String body, int household) {
    final q = uri.queryParameters;
    final get = method == 'GET';
    final mine = household == householdId;
    List<T> own<T>(List<T> data) => mine ? data : <T>[];

    switch (rest.first) {
      case 'member':
        return Reply.done;
      case 'shoppinglist':
        if (!get) return Reply.done;
        if (!mine) {
          return Reply.json([
            {
              'id': 20,
              'name': 'Shopping list',
              'items': <Object>[],
              'recentItems': <Object>[],
            },
          ]);
        }
        final limit = int.tryParse(q['recent_limit'] ?? '') ?? 9;
        return Reply.json([
          for (final list in shoppingLists)
            {
              ...list,
              'recentItems':
                  (list['recentItems']! as List).take(limit).toList(),
            },
        ]);
      case 'item':
        if (!get) return Reply.done;
        if (rest.length > 1 && rest[1] == 'search') {
          final query = (q['query'] ?? '').toLowerCase();
          return Reply.json([
            for (final i in own(items))
              if ('${i['name']}'.toLowerCase().contains(query)) i,
          ]);
        }
        return Reply.json(own(items));
      case 'category':
        return get ? Reply.json(own(categories)) : Reply.done;
      case 'tag':
        return get ? Reply.json(own(tags)) : Reply.done;
      case 'recipe':
        if (rest.length == 1) {
          if (get) return Reply.json(own(recipes));
          // A recipe was saved: answer with it, as the backend does.
          return Reply.json({
            ...jsonDecode(body) as Map<String, Object?>,
            'id': 90,
            'household_id': household,
          });
        }
        switch (rest[1]) {
          case 'filter':
            final filter =
                ((jsonDecode(body) as Map)['filter'] as List).cast<Map>();
            final wanted = {for (final t in filter) t['id']};
            return Reply.json([
              for (final r in own(recipes))
                if ((r['tags']! as List)
                    .any((t) => wanted.contains((t as Map)['id'])))
                  r,
            ]);
          case 'search':
            final query = (q['query'] ?? '').toLowerCase();
            final found = [
              for (final r in own(recipes))
                if ('${r['name']}'.toLowerCase().contains(query)) r,
            ];
            return q.containsKey('only_ids')
                ? Reply.json([for (final r in found) r['id']])
                : Reply.json(found);
          case 'newest':
            // Also asked for other households, on their "about" page.
            return Reply.json(rest.last != '0'
                ? <Object>[]
                : mine
                    ? recipes.reversed.toList()
                    : [
                        for (final r in community)
                          if (r['household_id'] == household) r,
                      ]);
          case 'scrape':
            return _scrape();
        }
      case 'planner':
        if (!get) return Reply.done;
        if (rest.length == 1) return Reply.json(own(plans));
        final paged = rest.length > 2 && rest[2] != '0';
        switch (rest[1]) {
          case 'recent-recipes':
            return Reply.json(paged || !populated
                ? <Object>[]
                : [
                    for (final id in [4, 6, 8, 1]) _recipeById(id)
                  ]);
          case 'suggested-recipes':
          case 'refresh-suggested-recipes':
            return Reply.json(paged || !populated
                ? <Object>[]
                : [
                    for (final id in [6, 4, 8]) _recipeById(id)
                  ]);
        }
      case 'expense':
        if (rest.length == 1) {
          if (!get) return Reply.done;
          return Reply.json(_expensePage(uri));
        }
        if (rest[1] == 'categories') {
          return get ? Reply.json(own(expenseCategories)) : Reply.done;
        }
        if (rest[1] == 'overview') return Reply.json(_overview(uri));
      case 'import':
      case 'export':
        return Reply.json(<String, Object>{});
    }
    return get ? null : Reply.done;
  }

  /// The expense list, 30 to a page like the backend, newest first.
  List<Map<String, Object?>> _expensePage(Uri uri) {
    final params = uri.queryParametersAll;
    final startAfter =
        int.tryParse(uri.queryParameters['startAfterDate'] ?? '');
    final endBefore = int.tryParse(uri.queryParameters['endBeforeDate'] ?? '');
    final search = (uri.queryParameters['search'] ?? '').toLowerCase();
    final filter = params['filter'] ?? const [];
    final personal = uri.queryParameters['view'] == '1';
    return [
      for (final e in expenses)
        if ((startAfter == null || (e['date']! as int) < startAfter) &&
            (endBefore == null || (e['date']! as int) > endBefore) &&
            '${e['name']}'.toLowerCase().contains(search) &&
            (filter.isEmpty ||
                filter.contains('${(e['category'] as Map?)?['id'] ?? ''}')) &&
            (!personal ||
                (e['paid_for']! as List).any((p) => (p as Map)['id'] == 1)))
          e,
    ].take(30).toList();
  }

  /// Totals per category and per day for each of the last `steps` frames.
  Map<String, Object?> _overview(Uri uri) {
    final frame = int.tryParse(uri.queryParameters['frame'] ?? '') ?? 2;
    final steps = int.tryParse(uri.queryParameters['steps'] ?? '') ?? 5;
    final page = int.tryParse(uri.queryParameters['page'] ?? '') ?? 0;
    final day0 = DateTime(now.year, now.month, now.day);

    (DateTime, DateTime) bounds(int ago) {
      switch (frame) {
        case 0:
          final start = day0.subtract(Duration(days: ago));
          return (start, start.add(const Duration(days: 1)));
        case 1:
          final monday =
              day0.subtract(Duration(days: day0.weekday - 1 + 7 * ago));
          return (monday, monday.add(const Duration(days: 7)));
        case 3:
          return (DateTime(now.year - ago), DateTime(now.year - ago + 1));
        default:
          return (
            DateTime(now.year, now.month - ago),
            DateTime(now.year, now.month - ago + 1),
          );
      }
    }

    String two(int n) => n.toString().padLeft(2, '0');

    return {
      for (var ago = page * steps; ago < (page + 1) * steps; ago++)
        '$ago': () {
          final (start, end) = bounds(ago);
          final byCategory = <String, double>{};
          final bySubframe = <String, double>{};
          for (final e in expenses) {
            if (e['exclude_from_statistics'] == true) continue;
            final date = DateTime.fromMillisecondsSinceEpoch(e['date']! as int);
            if (date.isBefore(start) || !date.isBefore(end)) continue;
            final category = '${(e['category'] as Map?)?['id'] ?? -1}';
            final amount = e['amount']! as double;
            byCategory[category] = (byCategory[category] ?? 0) + amount;
            final key = frame == 3
                ? '${date.year}-${two(date.month)}'
                : '${date.year}-${two(date.month)}-${two(date.day)}';
            bySubframe[key] = (bySubframe[key] ?? 0) + amount;
          }
          return {'by_category': byCategory, 'by_subframe': bySubframe};
        }(),
    };
  }

  /// What the backend's scraper returns for a recipe web page.
  Reply _scrape() => Reply.json({
        'recipe': {
          'name': 'Creamy mushroom risotto',
          'description': '1. Soften the onion in butter.\n'
              '2. Toast the rice, then add the stock a ladle at a time.\n'
              '3. Stir in the mushrooms and the parmesan.',
          'time': 40,
          'prep_time': 10,
          'cook_time': 30,
          'yields': 4,
          'source': 'https://www.example.org/recipes/mushroom-risotto',
          'photo': 'https://www.example.org/images/mushroom-risotto.png',
          'items': <Object>[],
          'tags': <Object>[],
        },
        'items': {
          '1 onion, finely chopped': _recipeItem(3, '1'),
          '300 g risotto rice': _recipeItem(16, '300 g'),
          '50 g butter': _recipeItem(10, '50 g'),
          '250 g chestnut mushrooms': null,
          '60 g parmesan, grated': _recipeItem(12, '60 g'),
        },
      });
}

// --------------------------------------------------------------- images

/// The picture the fake image cache serves for [url]: a soft two-colour
/// gradient chosen by the file name, so photos are distinguishable and every
/// run draws the same pixels.  Returns null for a URL the server would not
/// have.
Uint8List? fakeImageFor(String url) {
  final name = Uri.parse(url).pathSegments.lastOrNull ?? url;
  return _images.putIfAbsent(name, () {
    var hash = 0;
    for (final unit in name.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    const palettes = [
      [0xC8553D, 0xF2B880],
      [0x5B8E7D, 0xF4E285],
      [0x8E5572, 0xF2D0A4],
      [0x3D5A80, 0x98C1D9],
      [0xBC4B51, 0xF4A259],
      [0x606C38, 0xDDA15E],
    ];
    final palette = palettes[hash % palettes.length];
    final portrait = name.startsWith('user-');
    return _gradientPng(
      portrait ? 96 : 480,
      portrait ? 96 : 320,
      palette[0],
      palette[1],
    );
  });
}

final Map<String, Uint8List> _images = {};

/// An RGB PNG of a diagonal gradient from [from] to [to].
Uint8List _gradientPng(int width, int height, int from, int to) {
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // filter: none
    for (var x = 0; x < width; x++) {
      final t = (x / width + y / height) / 2;
      for (final shift in [16, 8, 0]) {
        final a = (from >> shift) & 0xff;
        final b = (to >> shift) & 0xff;
        raw.addByte((a + (b - a) * t).round());
      }
    }
  }

  final png = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final body = [...ascii.encode(type), ...data];
    png
      ..add(_uint32(data.length))
      ..add(body)
      ..add(_uint32(_crc32(body)));
  }

  chunk('IHDR', [..._uint32(width), ..._uint32(height), 8, 2, 0, 0, 0]);
  chunk('IDAT', zlib.encode(raw.takeBytes()));
  chunk('IEND', const []);
  return png.takeBytes();
}

List<int> _uint32(int value) => [
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ];

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xffffffff;
}
