import 'dart:convert';
import 'dart:math';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

typedef Json = Map<String, dynamic>;

String novoId(String prefixo) {
  final random = Random.secure();
  final partes = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  return '${prefixo}_$partes';
}

class Banco {
  Banco._();

  static final Banco instancia = Banco._();

  Future<Database>? _abertura;

  Future<Database> get database async {
    try {
      return await (_abertura ??= _abrir());
    } catch (_) {
      _abertura = null;
      rethrow;
    }
  }

  Future<Database> _abrir() async {
    final pasta = await getDatabasesPath();

    return openDatabase(
      join(pasta, 'ficha_treino.db'),
      version: 2,
      onUpgrade: (db, anterior, atual) async {
        if (anterior < 2) await _criarTabelasGravacoes(db);
      },
      onCreate: (db, version) async {
        await _criarTabelasGravacoes(db);
        await db.execute('''
          CREATE TABLE fichas (
            id TEXT PRIMARY KEY,
            nome TEXT NOT NULL,
            conteudo TEXT NOT NULL,
            atualizado INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE resultados (
            id TEXT PRIMARY KEY,
            inicio INTEGER NOT NULL,
            conteudo TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE configuracao (
            chave TEXT PRIMARY KEY,
            valor INTEGER NOT NULL
          )
        ''');

        await db.insert('configuracao', {
          'chave': 'revisao_fichas',
          'valor': 1,
        });

        // Fichas iniciais com os mesmos IDs da migração do relógio.
        for (final ficha in _fichasIniciais()) {
          await db.insert('fichas', {
            'id': ficha['id'],
            'nome': ficha['nome'],
            'conteudo': jsonEncode(ficha),
            'atualizado': DateTime.now().millisecondsSinceEpoch,
          });
        }
      },
    );
  }

  Future<void> _criarTabelasGravacoes(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS gravacoes (
      id TEXT PRIMARY KEY, inicio INTEGER NOT NULL, nome TEXT NOT NULL,
      hash TEXT NOT NULL, conteudo TEXT NOT NULL, rotulos TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS gravacao_partes (
      id TEXT NOT NULL, indice INTEGER NOT NULL, total INTEGER NOT NULL,
      tamanho INTEGER NOT NULL, hash TEXT NOT NULL, conteudo TEXT NOT NULL,
      PRIMARY KEY (id, indice)
    )''');
  }

  Future<List<Json>> listarFichas() async {
    final db = await database;

    final linhas = await db.query('fichas', orderBy: 'atualizado ASC, id ASC');

    return linhas
        .map(
          (linha) => Json.from(jsonDecode(linha['conteudo'] as String) as Map),
        )
        .toList();
  }

  Future<void> salvarFicha(Json ficha) async {
    _validarFicha(ficha);

    final db = await database;

    await db.transaction((tx) async {
      final existente = await tx.query(
        'fichas',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [ficha['id']],
      );

      if (existente.isEmpty) {
        final quantidade =
            Sqflite.firstIntValue(
              await tx.rawQuery('SELECT COUNT(*) FROM fichas'),
            ) ??
            0;

        if (quantidade >= 20) {
          throw Exception('O limite é de 20 fichas.');
        }
      }

      final valores = <String, Object?>{
        'nome': ficha['nome'],
        'conteudo': jsonEncode(ficha),
        'atualizado': DateTime.now().millisecondsSinceEpoch,
      };

      if (existente.isEmpty) {
        await tx.insert('fichas', {'id': ficha['id'], ...valores});
      } else {
        await tx.update(
          'fichas',
          valores,
          where: 'id = ?',
          whereArgs: [ficha['id']],
        );
      }

      await tx.rawUpdate('''
        UPDATE configuracao
        SET valor = valor + 1
        WHERE chave = 'revisao_fichas'
      ''');
    });
  }

  Future<void> excluirFicha(String id) async {
    final db = await database;

    await db.transaction((tx) async {
      final removidas = await tx.delete(
        'fichas',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (removidas > 0) {
        await tx.rawUpdate('''
          UPDATE configuracao
          SET valor = valor + 1
          WHERE chave = 'revisao_fichas'
        ''');
      }

      // O histórico não é apagado ao excluir uma ficha.
    });
  }

  Future<List<Json>> listarResultados() async {
    final db = await database;

    final linhas = await db.query('resultados', orderBy: 'inicio DESC');

    return linhas
        .map(
          (linha) => Json.from(jsonDecode(linha['conteudo'] as String) as Map),
        )
        .toList();
  }

  // Retorna a confirmação somente depois do commit da transação.
  Future<Json> salvarResultado(Json recebido) async {
    final resultado = _normalizarResultado(recebido);
    final db = await database;
    final conteudo = jsonEncode(resultado);
    await db.transaction((tx) async {
      final existentes = await tx.query(
        'resultados',
        where: 'id = ?',
        whereArgs: [resultado['id']],
      );
      if (existentes.isNotEmpty) {
        final anterior = _normalizarResultado(
          Json.from(jsonDecode(existentes.single['conteudo'] as String) as Map),
        );
        if (jsonEncode(anterior) != conteudo) {
          throw Exception(
            'Mesmo ID recebido com outro conteúdo. Nada alterado.',
          );
        }
        return;
      }
      await tx.insert('resultados', {
        'id': resultado['id'],
        'inicio': resultado['inicio'],
        'conteudo': conteudo,
      });
    });
    return {
      'versao': 1, 'persistido': true, 'resultadoId': resultado['id'],
      'seriesPersistidas': (resultado['seriesRealizadas'] as List?)?.length ?? 0,
    };
  }

  Json _normalizarResultado(Json r) {
    String texto(dynamic v, String campo) {
      if (v is! String || v.trim().isEmpty || v.length > 100) {
        throw Exception('Resultado: $campo inválido.');
      }
      return v;
    }

    int inteiro(dynamic v, String campo) {
      if (v is! num ||
          !v.isFinite ||
          v < 0 ||
          v > 8640000000000000 ||
          v != v.truncateToDouble()) {
        throw Exception('Resultado: $campo inválido.');
      }
      return v.toInt();
    }

    if (r['versao'] != null && r['versao'] != 1) {
      throw Exception('Versão de resultado não suportada.');
    }
    final inicio = inteiro(r['inicio'], 'início');
    final fim = inteiro(r['fim'], 'fim');
    final duracao = inteiro(r['duracaoMs'], 'duração');
    if (fim < inicio || duracao != fim - inicio) {
      throw Exception('Horários do resultado são inconsistentes.');
    }
    final lista = r['cargas'];
    if (lista is! List || lista.length > 40) {
      throw Exception('Lista de cargas inválida.');
    }
    final cargas = <Json>[];
    for (final item in lista) {
      if (item is! Map) throw Exception('Carga inválida.');
      final carga = item['ultimaCarga'];
      if (carga != null &&
          (carga is! num || !carga.isFinite || carga < 0 || carga > 500)) {
        throw Exception('Valor da carga inválido.');
      }
      cargas.add({
        // Resultados antigos podem não ter o ID do exercício.
        'exercicioId': item['exercicioId'] == null
            ? null
            : texto(item['exercicioId'], 'ID do exercício'),
        'exercicioNome': texto(item['exercicioNome'], 'nome do exercício'),
        'ultimaCarga': carga == null ? null : (carga as num).toDouble(),
      });
    }
    final series = <Json>[];
    if (r.containsKey('seriesRealizadas')) {
      final listaSeries = r['seriesRealizadas'];
      if (listaSeries is! List || listaSeries.length > 2000) {
        throw Exception('Lista de séries inválida.');
      }
      final chaves = <String>{};
      for (final s in listaSeries) {
        if (s is! Map) throw Exception('Série inválida.');
        final exId = texto(s['exercicioId'], 'exercício da série');
        final numero = inteiro(s['serie'], 'número da série');
        final peso = s['carga'];
        final motivo = s['motivo'];
        if (numero < 1 || numero > 50 ||
            !chaves.add('$exId:$numero') || peso is! num ||
            !peso.isFinite || peso < 0 || peso > 500 ||
            (motivo != 'pausa' && motivo != 'coroa')) {
          throw Exception('Dados da série inválidos.');
        }
        series.add({
          'exercicioId': exId,
          'exercicioNome': texto(s['exercicioNome'], 'nome do exercício'),
          'serie': numero,
          'meta': inteiro(s['meta'], 'meta'),
          'repeticoes': inteiro(s['repeticoes'], 'repetições'),
          'carga': peso.toDouble(),
          'fim': inteiro(s['fim'], 'fim da série'),
          'motivo': motivo,
        });
      }
    }
    return {
      if (r.containsKey('seriesRealizadas')) 'seriesRealizadas': series,
      'versao': 1,
      'id': texto(r['id'], 'ID'),
      'fichaId': texto(r['fichaId'], 'ID da ficha'),
      'fichaNome': texto(r['fichaNome'], 'nome da ficha'),
      'inicio': inicio,
      'fim': fim,
      'duracaoMs': duracao,
      'seriesConcluidas': inteiro(r['seriesConcluidas'], 'séries'),
      'exerciciosConcluidos': inteiro(r['exerciciosConcluidos'], 'exercícios'),
      'cargas': cargas,
      'estado': 'sincronizado',
    };
  }

  // Lê fichas e revisão em uma mesma transação.
  Future<Json> exportarFichas() async {
    final db = await database;

    return db.transaction((tx) async {
      final linhas = await tx.query(
        'fichas',
        orderBy: 'atualizado ASC, id ASC',
      );

      if (linhas.isEmpty) {
        throw Exception('Crie uma ficha antes de enviar ao relógio.');
      }

      final revisao = await tx.query(
        'configuracao',
        where: 'chave = ?',
        whereArgs: ['revisao_fichas'],
      );

      return {
        'versao': 1,
        'revisao': revisao.single['valor'],
        'fichas': linhas
            .map((linha) => jsonDecode(linha['conteudo'] as String))
            .toList(),
      };
    });
  }

  void _validarFicha(Json ficha) {
    final id = ficha['id'];
    final nome = ficha['nome'];
    final exercicios = ficha['exercicios'];

    if (id is! String || id.isEmpty || id.length > 100) {
      throw Exception('Identificador da ficha inválido.');
    }

    if (nome is! String || nome.trim().isEmpty || nome.length > 100) {
      throw Exception('Informe um nome de até 100 caracteres.');
    }

    if (exercicios is! List || exercicios.isEmpty || exercicios.length > 40) {
      throw Exception('A ficha deve ter de 1 a 40 exercícios.');
    }

    final ids = <String>{};

    for (final item in exercicios) {
      final e = Json.from(item as Map);

      final exId = e['id'];
      final exNome = e['nome'];
      final series = e['series'];
      final reps = e['reps'];
      final carga = e['carga'];
      final descanso = e['descanso'];

      if (exId is! String ||
          exId.isEmpty ||
          exId.length > 100 ||
          !ids.add(exId)) {
        throw Exception('Identificador de exercício inválido.');
      }

      if (exNome is! String || exNome.trim().isEmpty || exNome.length > 100) {
        throw Exception('Informe o nome de cada exercício.');
      }

      if (series is! int || series < 1 || series > 50) {
        throw Exception('Use de 1 a 50 séries.');
      }

      if (reps is! int || reps < 1 || reps > 200) {
        throw Exception('Use de 1 a 200 repetições.');
      }

      if (carga is! num || !carga.isFinite || carga < 0 || carga > 500) {
        throw Exception('A carga deve ficar entre 0 e 500 kg.');
      }

      if (descanso is! int || descanso < 5 || descanso > 3600) {
        throw Exception('O descanso deve ficar entre 5 e 3600 segundos.');
      }
    }
  }

  List<Json> _fichasIniciais() {
    Json exercicio(
      String id,
      String nome,
      int series,
      int reps,
      num carga,
      int descanso,
    ) {
      return {
        'id': id,
        'nome': nome,
        'series': series,
        'reps': reps,
        'carga': carga,
        'descanso': descanso,
      };
    }

    return [
      {
        'id': 'peito',
        'nome': 'PEITO',
        'exercicios': [
          exercicio('peito_ex_1', 'SUPINO RETO', 4, 10, 20, 60),
          exercicio('peito_ex_2', 'SUPINO INCLINADO', 3, 10, 16, 60),
          exercicio('peito_ex_3', 'TRÍCEPS CORDA', 3, 10, 25, 45),
        ],
      },
      {
        'id': 'costas',
        'nome': 'COSTAS',
        'exercicios': [
          exercicio('costas_ex_1', 'PUXADA FRENTE', 4, 10, 40, 60),
          exercicio('costas_ex_2', 'REMADA CURVADA', 3, 12, 30, 60),
          exercicio('costas_ex_3', 'ROSCA DIRETA', 3, 12, 12, 45),
        ],
      },
      {
        'id': 'perna',
        'nome': 'PERNA',
        'exercicios': [
          exercicio('perna_ex_1', 'AGACHAMENTO', 4, 10, 40, 90),
          exercicio('perna_ex_2', 'LEG PRESS', 4, 12, 100, 90),
          exercicio('perna_ex_3', 'CADEIRA EXTENSORA', 3, 12, 35, 60),
        ],
      },
    ];
  }
}
