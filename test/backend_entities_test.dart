import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/entities.dart';

void main() {
  test('game totals accept native integers and legacy decimal strings', () {
    for (final total in [3, '3']) {
      final page = GamePage.fromJson({
        'games_total': total,
        'games': [],
        'categories': [],
        'hot_games': [],
      });
      expect(page.gamesTotal, '3');
    }
  });

  test('game category fields are retained rather than discarded', () {
    final category = GameCategory.fromJson({
      'name': 'Fixture category',
      'slug': 'fixture',
    });
    expect(category.name, 'Fixture category');
    expect(category.slug, 'fixture');
    expect(category.toJson(), {'name': 'Fixture category', 'slug': 'fixture'});
  });

  test('a missing game total is still a contract error', () {
    expect(
      () => GamePage.fromJson({'games': [], 'categories': [], 'hot_games': []}),
      throwsFormatException,
    );
  });
}
