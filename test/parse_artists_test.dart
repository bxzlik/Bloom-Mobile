/// Разбор строки артистов: где режем, а где имя оставляем целым.
library;

import 'package:bloom/shared/util/artists.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('символы и слова-связки режут строку', () {
    expect(parseArtists('Artist A, Artist B feat. Artist C'), [
      'Artist A',
      'Artist B',
      'Artist C',
    ]);
    expect(parseArtists('A & B'), ['A', 'B']);
    expect(parseArtists('A; B × C'), ['A', 'B', 'C']);
    expect(parseArtists('Sasha x Digweed'), ['Sasha', 'Digweed']);
    expect(parseArtists('Один и Другой'), ['Один', 'Другой']);
  });

  test('слово внутри имени именем и остаётся', () {
    // Связки режут только между пробелами: иначе от «Andrew» осталось бы
    // «ew», а «Fixt» превратился бы в «Fi».
    expect(parseArtists('Andrew Fixt'), ['Andrew Fixt']);
    expect(parseArtists('Sandwith'), ['Sandwith']);
  });

  test('один артист возвращается одним куском', () {
    expect(parseArtists('AC/DC'), ['AC/DC']);
    expect(parseArtists('  Onda  '), ['Onda']);
  });

  test('пустая строка — пустой список, из одних разделителей — как есть', () {
    expect(parseArtists(null), isEmpty);
    expect(parseArtists('   '), isEmpty);
    expect(parseArtists('&'), ['&']);
  });
}
