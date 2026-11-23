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

const objetivosPerfil = [
  'Hipertrofia',
  'Emagrecimento',
  'Recomposição corporal',
  'Força',
  'Saúde e condicionamento',
];
const sexosPerfil = ['Masculino', 'Feminino', 'Outro'];
const niveisPerfil = ['Iniciante', 'Intermediário', 'Avançado'];

const circunferenciasMedidas = <String, String>{
  'pescoco': 'Pescoço',
  'ombros': 'Ombros',
  'peito': 'Peito',
  'abdomen': 'Abdômen',
  'quadril': 'Quadril',
  'bracoD': 'Braço direito',
  'bracoE': 'Braço esquerdo',
  'coxaD': 'Coxa direita',
  'coxaE': 'Coxa esquerda',
  'panturrilhaD': 'Panturrilha direita',
  'panturrilhaE': 'Panturrilha esquerda',
};

/// Idade em anos completos; atualiza sozinha conforme o tempo passa.
int idadeEm(int nascimentoMs, [DateTime? ref]) {
  final hoje = ref ?? DateTime.now();
  final n = DateTime.fromMillisecondsSinceEpoch(nascimentoMs);
  var idade = hoje.year - n.year;
  if (hoje.month < n.month || (hoje.month == n.month && hoje.day < n.day)) {
    idade--;
  }
  return idade;
}

num? _numeroValidado(dynamic v, String campo, num min, num max,
    {bool opcional = false}) {
  if (v == null || (v is String && v.trim().isEmpty)) {
    if (opcional) return null;
    throw Exception('$campo é obrigatório.');
  }
  final n = v is num ? v : num.tryParse(v.toString().replaceAll(',', '.'));
  if (n == null || !n.isFinite || n < min || n > max) {
    throw Exception('$campo inválido (use entre $min e $max).');
  }
  return double.parse(n.toStringAsFixed(1));
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
      version: 3,
      onUpgrade: (db, antiga, nova) async {
        await _criarMedidas(db);
        await _criarPerfil(db);
      },
      onCreate: (db, version) async {
        await _criarMedidas(db);
        await _criarPerfil(db);

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

  Future<void> _criarMedidas(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS medidas (
        id TEXT PRIMARY KEY,
        data INTEGER NOT NULL,
        conteudo TEXT NOT NULL
      )
    ''');
  }

  Future<void> _criarPerfil(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS perfil (
        id INTEGER PRIMARY KEY,
        conteudo TEXT NOT NULL
      )
    ''');
  }

  // ---------- Medidas corporais ----------

  Future<List<Json>> listarMedidas() async {
    final db = await database;
    final linhas = await db.query('medidas', orderBy: 'data ASC, id ASC');
    return linhas
        .map((l) => Json.from(jsonDecode(l['conteudo'] as String) as Map))
        .toList();
  }

  /// Valida e grava (insere ou substitui pelo mesmo id).
  Future<Json> salvarMedida(Json recebida) async {
    final data = recebida['data'];
    if (data is! int || data <= 0) throw Exception('Data inválida.');
    final peso = _numeroValidado(recebida['pesoKg'], 'Peso', 20, 400)!;
    final gordura = _numeroValidado(recebida['gorduraPct'], '% de gordura', 2, 70,
        opcional: true);
    final cintura =
        _numeroValidado(recebida['cinturaCm'], 'Cintura', 30, 250, opcional: true);

    final circ = <String, double>{};
    final recebidas = recebida['circunferenciasCm'];
    if (recebidas is Map) {
      for (final chave in circunferenciasMedidas.keys) {
        final v = _numeroValidado(
            recebidas[chave], circunferenciasMedidas[chave]!, 10, 250,
            opcional: true);
        if (v != null) circ[chave] = v.toDouble();
      }
    }

    final obs = (recebida['observacao'] as String? ?? '').trim();
    if (obs.length > 300) throw Exception('Observação muito longa.');

    final medida = <String, dynamic>{
      'versao': 1,
      'id': (recebida['id'] as String?) ?? novoId('medida'),
      'data': data,
      'pesoKg': peso,
      if (gordura != null) 'gorduraPct': gordura,
      if (gordura != null)
        'massaMagraKg':
            double.parse((peso * (1 - gordura / 100)).toStringAsFixed(1)),
      if (cintura != null) 'cinturaCm': cintura,
      if (circ.isNotEmpty) 'circunferenciasCm': circ,
      if (obs.isNotEmpty) 'observacao': obs,
    };

    final db = await database;
    await db.insert(
      'medidas',
      {'id': medida['id'], 'data': data, 'conteudo': jsonEncode(medida)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return medida;
  }

  Future<void> excluirMedida(String id) async {
    final db = await database;
    await db.delete('medidas', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Perfil ----------

  Future<Json?> obterPerfil() async {
    final db = await database;
    final linhas = await db.query('perfil', where: 'id = 1');
    if (linhas.isEmpty) return null;
    return Json.from(jsonDecode(linhas.first['conteudo'] as String) as Map);
  }

  Future<Json> salvarPerfil(Json r) async {
    final nome = (r['nome'] as String? ?? '').trim();
    if (nome.length > 60) throw Exception('Nome muito longo.');

    final nasc = r['nascimento'];
    if (nasc is! int ||
        nasc >= DateTime.now().millisecondsSinceEpoch ||
        DateTime.fromMillisecondsSinceEpoch(nasc).year < 1900) {
      throw Exception('Informe a data de nascimento.');
    }

    String? escolha(dynamic v, List<String> validos, String campo) {
      if (v == null || (v is String && v.isEmpty)) return null;
      if (v is! String || !validos.contains(v)) {
        throw Exception('$campo inválido.');
      }
      return v;
    }

    final sexo = escolha(r['sexo'], sexosPerfil, 'Sexo');
    final objetivo = escolha(r['objetivo'], objetivosPerfil, 'Objetivo');
    final nivel = escolha(r['nivel'], niveisPerfil, 'Nível');
    final altura = _numeroValidado(r['alturaCm'], 'Altura', 100, 250)!;
    final pesoMeta =
        _numeroValidado(r['pesoMetaKg'], 'Peso meta', 20, 400, opcional: true);
    final gorduraMeta = _numeroValidado(
        r['gorduraMetaPct'], '% de gordura meta', 2, 70, opcional: true);
    final dias = r['diasPorSemana'];
    if (dias != null && (dias is! int || dias < 1 || dias > 7)) {
      throw Exception('Dias por semana inválido.');
    }
    final obs = (r['observacoes'] as String? ?? '').trim();
    if (obs.length > 500) throw Exception('Observações muito longas.');

    final perfil = <String, dynamic>{
      'versao': 1,
      if (nome.isNotEmpty) 'nome': nome,
      'nascimento': nasc,
      if (sexo != null) 'sexo': sexo,
      'alturaCm': altura,
      if (objetivo != null) 'objetivo': objetivo,
      if (nivel != null) 'nivel': nivel,
      if (dias != null) 'diasPorSemana': dias,
      if (pesoMeta != null) 'pesoMetaKg': pesoMeta,
      if (gorduraMeta != null) 'gorduraMetaPct': gorduraMeta,
      if (obs.isNotEmpty) 'observacoes': obs,
      'atualizado': DateTime.now().millisecondsSinceEpoch,
    };

    final db = await database;
    await db.insert(
      'perfil',
      {'id': 1, 'conteudo': jsonEncode(perfil)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return perfil;
  }

  // ---------- Pacote para a IA ----------

  /// Dados estruturados para o agente de IA (não envia o banco inteiro).
  Future<Json> exportarParaIA(
      {int diasTreinos = 120, int maxMedidas = 200}) async {
    final corte = DateTime.now()
        .subtract(Duration(days: diasTreinos))
        .millisecondsSinceEpoch;
    final resultados = (await listarResultados()).where((r) {
      final i = r['inicio'];
      return i is num && i >= corte;
    }).toList();
    final medidas = await listarMedidas();
    final fichas = await listarFichas();
    final perfil = await obterPerfil();
    return {
      'versao': 1,
      'geradoEm': DateTime.now().toUtc().toIso8601String(),
      'perfil': perfil == null
          ? null
          : {...perfil, 'idade': idadeEm(perfil['nascimento'] as int)},
      'fichas': fichas,
      'treinos': resultados,
      'medidas': medidas.length > maxMedidas
          ? medidas.sublist(medidas.length - maxMedidas)
          : medidas,
    };
  }

  Future<List<Json>> listarFichas() async {
    final db = await database;

    final linhas = await db.query(
      'fichas',
      orderBy: 'atualizado ASC, id ASC',
    );

    return linhas.map((linha) {
      return Json.from(
        jsonDecode(linha['conteudo'] as String) as Map,
      );
    }).toList();
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
        final quantidade = Sqflite.firstIntValue(
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
        await tx.insert('fichas', {
          'id': ficha['id'],
          ...valores,
        });
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
    });
  }

  Future<List<Json>> listarResultados() async {
    final db = await database;

    final linhas = await db.query(
      'resultados',
      orderBy: 'inicio DESC',
    );

    return linhas.map((linha) {
      return Json.from(
        jsonDecode(linha['conteudo'] as String) as Map,
      );
    }).toList();
  }

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
          Json.from(
            jsonDecode(
              existentes.single['conteudo'] as String,
            ) as Map,
          ),
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

    // A confirmação só é enviada após concluir a transação.
    return {
      'versao': 1,
      'persistido': true,
      'resultadoId': resultado['id'],
      'seriesPersistidas':
          (resultado['seriesRealizadas'] as List?)?.length ?? 0,
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
      if (item is! Map) {
        throw Exception('Carga inválida.');
      }

      final carga = item['ultimaCarga'];

      if (carga != null &&
          (carga is! num ||
              !carga.isFinite ||
              carga < 0 ||
              carga > 500)) {
        throw Exception('Valor da carga inválido.');
      }

      cargas.add({
        'exercicioId': item['exercicioId'] == null
            ? null
            : texto(item['exercicioId'], 'ID do exercício'),
        'exercicioNome': texto(
          item['exercicioNome'],
          'nome do exercício',
        ),
        'ultimaCarga':
            carga == null ? null : (carga as num).toDouble(),
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
        if (s is! Map) {
          throw Exception('Série inválida.');
        }

        final exId = texto(
          s['exercicioId'],
          'exercício da série',
        );

        final numero = inteiro(
          s['serie'],
          'número da série',
        );

        final peso = s['carga'];
        final motivo = s['motivo'];

        if (numero < 1 ||
            numero > 50 ||
            !chaves.add('$exId:$numero') ||
            peso is! num ||
            !peso.isFinite ||
            peso < 0 ||
            peso > 500 ||
            (motivo != 'pausa' && motivo != 'coroa' && motivo != 'botao')) {
          throw Exception('Dados da série inválidos.');
        }

        series.add({
          'exercicioId': exId,
          'exercicioNome': texto(
            s['exercicioNome'],
            'nome do exercício',
          ),
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
      if (r.containsKey('seriesRealizadas'))
        'seriesRealizadas': series,
      'versao': 1,
      'id': texto(r['id'], 'ID'),
      'fichaId': texto(r['fichaId'], 'ID da ficha'),
      'fichaNome': texto(r['fichaNome'], 'nome da ficha'),
      'inicio': inicio,
      'fim': fim,
      'duracaoMs': duracao,
      'seriesConcluidas': inteiro(
        r['seriesConcluidas'],
        'séries',
      ),
      'exerciciosConcluidos': inteiro(
        r['exerciciosConcluidos'],
        'exercícios',
      ),
      'cargas': cargas,
      'estado': 'sincronizado',
    };
  }

  Future<Json> exportarFichas() async {
    final db = await database;

    return db.transaction((tx) async {
      final linhas = await tx.query(
        'fichas',
        orderBy: 'atualizado ASC, id ASC',
      );

      if (linhas.isEmpty) {
        throw Exception(
          'Crie uma ficha antes de enviar ao relógio.',
        );
      }

      final revisao = await tx.query(
        'configuracao',
        where: 'chave = ?',
        whereArgs: ['revisao_fichas'],
      );

      return {
        'versao': 1,
        'revisao': revisao.single['valor'],
        'fichas': linhas.map((linha) {
          return jsonDecode(linha['conteudo'] as String);
        }).toList(),
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

    if (nome is! String ||
        nome.trim().isEmpty ||
        nome.length > 100) {
      throw Exception('Informe um nome de até 100 caracteres.');
    }

    if (exercicios is! List ||
        exercicios.isEmpty ||
        exercicios.length > 40) {
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

      if (exNome is! String ||
          exNome.trim().isEmpty ||
          exNome.length > 100) {
        throw Exception('Informe o nome de cada exercício.');
      }

      if (series is! int || series < 1 || series > 50) {
        throw Exception('Use de 1 a 50 séries.');
      }

      if (reps is! int || reps < 1 || reps > 200) {
        throw Exception('Use de 1 a 200 repetições.');
      }

      if (carga is! num ||
          !carga.isFinite ||
          carga < 0 ||
          carga > 500) {
        throw Exception('A carga deve ficar entre 0 e 500 kg.');
      }

      if (descanso is! int ||
          descanso < 5 ||
          descanso > 3600) {
        throw Exception(
          'O descanso deve ficar entre 5 e 3600 segundos.',
        );
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
          exercicio(
            'peito_ex_1', 'SUPINO RETO', 4, 10, 20, 60,
          ),
          exercicio(
            'peito_ex_2', 'SUPINO INCLINADO', 3, 10, 16, 60,
          ),
          exercicio(
            'peito_ex_3', 'TRÍCEPS CORDA', 3, 10, 25, 45,
          ),
        ],
      },
      {
        'id': 'costas',
        'nome': 'COSTAS',
        'exercicios': [
          exercicio(
            'costas_ex_1', 'PUXADA FRENTE', 4, 10, 40, 60,
          ),
          exercicio(
            'costas_ex_2', 'REMADA CURVADA', 3, 12, 30, 60,
          ),
          exercicio(
            'costas_ex_3', 'ROSCA DIRETA', 3, 12, 12, 45,
          ),
        ],
      },
      {
        'id': 'perna',
        'nome': 'PERNA',
        'exercicios': [
          exercicio(
            'perna_ex_1', 'AGACHAMENTO', 4, 10, 40, 90,
          ),
          exercicio(
            'perna_ex_2', 'LEG PRESS', 4, 12, 100, 90,
          ),
          exercicio(
            'perna_ex_3', 'CADEIRA EXTENSORA', 3, 12, 35, 60,
          ),
        ],
      },
    ];
  }
}