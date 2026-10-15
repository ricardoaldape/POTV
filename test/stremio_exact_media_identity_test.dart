import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/addons/stremio_source_resolver.dart';

void main() {
  final results = <Map<String, Object?>>[
    {
      'name': 'El viaje',
      'imdb_id': 'tt1234567',
      'year': '1999',
    },
    {
      'name': 'El viaje',
      'imdb_id': 'tt7654321',
      'year': '2021',
    },
    {
      'name': 'Otra película',
      'imdb_id': 'tt9876543',
      'year': '2015',
    },
  ];

  test('never guesses the first Cinemeta search result', () {
    expect(
      StremioSourceResolver.exactCinemetaId(
        metas: results,
        title: 'Película inexistente',
      ),
      isNull,
    );
  });

  test('resolves exact title and matching release year', () {
    expect(
      StremioSourceResolver.exactCinemetaId(
        metas: results,
        title: '  EL VIAJE ',
        year: '1999',
      ),
      'tt1234567',
    );
    expect(
      StremioSourceResolver.exactCinemetaId(
        metas: results,
        title: 'El viaje',
        year: '2021',
      ),
      'tt7654321',
    );
  });

  test('ambiguous remakes need a year to prevent playing wrong film', () {
    expect(
      StremioSourceResolver.exactCinemetaId(
        metas: results,
        title: 'El viaje',
      ),
      isNull,
    );
  });

  test('rejects year mismatches and non-IMDb identifiers', () {
    expect(
      StremioSourceResolver.exactCinemetaId(
        metas: results,
        title: 'El viaje',
        year: '2009',
      ),
      isNull,
    );
    expect(
      StremioSourceResolver.exactCinemetaId(
        metas: [
          {'name': 'El viaje', 'id': 'tmdb:12345', 'year': '1999'},
        ],
        title: 'El viaje',
        year: '1999',
      ),
      isNull,
    );
  });
}
