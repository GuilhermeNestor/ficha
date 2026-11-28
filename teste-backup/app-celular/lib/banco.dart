import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'ia_nucleo.dart';

typedef Json = Map<String, dynamic>;

String novoId(String prefixo) {
  final random = Random.secure();

  final partes = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  return '${prefixo}_$partes';
}

/// Poses das fotos de evolução.
const vistasFoto = <String, String>{
  'frente': 'Frente',
  'lado': 'Lado',
  'costas': 'Costas',
};

final _nomeFoto = RegExp(r'^foto_[0-9a-f]{32}\.jpg$');

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
  'antebracoD': 'Antebraço direito',
  'antebracoE': 'Antebraço esquerdo',
  'punho': 'Punho',
  'gluteo': 'Glúteo',
  'tornozelo': 'Tornozelo',
};

/// Dobras cutâneas (mm) do protocolo Jackson & Pollock de 7 dobras.
const dobrasCutaneasMedidas = <String, String>{
  'peitoral': 'Peitoral',
  'axilarMedia': 'Axilar média',
  'triceps': 'Tríceps',
  'subescapular': 'Subescapular',
  'abdominal': 'Abdominal',
  'suprailiaca': 'Suprailíaca',
  'coxa': 'Coxa',
};

/// % de gordura estimada (Jackson & Pollock, 7 dobras + equação de Siri).
/// Precisa das 7 dobras, do sexo (Masculino/Feminino) e da idade na data
/// da avaliação. Devolve null se faltar algo.
double? gorduraJacksonPollock7(Map dobras, String? sexo, int? idade) {
  if (idade == null || (sexo != 'Masculino' && sexo != 'Feminino')) {
    return null;
  }
  var soma = 0.0;
  for (final k in dobrasCutaneasMedidas.keys) {
    final v = dobras[k];
    final n = v is num
        ? v.toDouble()
        : double.tryParse(v?.toString().replaceAll(',', '.') ?? '');
    if (n == null || n <= 0) return null;
    soma += n;
  }
  final densidade = sexo == 'Masculino'
      ? 1.112 - 0.00043499 * soma + 0.00000055 * soma * soma - 0.00028826 * idade
      : 1.097 - 0.00046971 * soma + 0.00000056 * soma * soma - 0.00012828 * idade;
  final g = 495 / densidade - 450;
  if (!g.isFinite || g < 2 || g > 60) return null;
  return double.parse(g.toStringAsFixed(1));
}

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
      version: 4,
      // Migração incremental: só cria o que falta (CREATE TABLE IF NOT EXISTS).
      // Fichas, resultados, medidas, perfil e fotos não são tocados.
      onUpgrade: (db, antiga, nova) async {
        await _criarMedidas(db);
        await _criarPerfil(db);
        await _criarIA(db);
      },
      onCreate: (db, version) async {
        await _criarMedidas(db);
        await _criarPerfil(db);
        await _criarIA(db);

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

  /// Tabelas do Personal IA. Nenhuma delas entra no que vai para o relógio.
  Future<void> _criarIA(DatabaseExecutor db) async {
    // Planejamento (o que se pretende), separado do que foi realizado.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS planos_exercicio (
        ficha_id TEXT NOT NULL,
        exercicio_id TEXT NOT NULL,
        conteudo TEXT NOT NULL,
        atualizado INTEGER NOT NULL,
        PRIMARY KEY (ficha_id, exercicio_id)
      )
    ''');

    // Resposta "quantas repetições boas ainda sairiam?" e desconforto,
    // sempre da ÚLTIMA série do exercício naquele treino.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS esforco_series (
        resultado_id TEXT NOT NULL,
        exercicio_id TEXT NOT NULL,
        serie INTEGER NOT NULL,
        resposta TEXT,
        desconforto TEXT,
        atualizado INTEGER NOT NULL,
        PRIMARY KEY (resultado_id, exercicio_id, serie)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS avaliacoes_ia (
        id TEXT PRIMARY KEY,
        tipo TEXT NOT NULL,
        ficha_id TEXT,
        criado INTEGER NOT NULL,
        estado TEXT NOT NULL,
        demonstracao INTEGER NOT NULL DEFAULT 0,
        pedido TEXT NOT NULL,
        resposta TEXT,
        erro TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sugestoes_ia (
        id TEXT PRIMARY KEY,
        avaliacao_id TEXT NOT NULL,
        ordem INTEGER NOT NULL,
        estado TEXT NOT NULL,
        conteudo TEXT NOT NULL,
        decidido INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ia_ajustes (
        chave TEXT PRIMARY KEY,
        valor TEXT NOT NULL
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
    final peso =
        _numeroValidado(recebida['pesoKg'], 'Peso', 20, 400, opcional: true);
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

    final dobras = <String, double>{};
    final recebidasD = recebida['dobrasMm'];
    if (recebidasD is Map) {
      for (final chave in dobrasCutaneasMedidas.keys) {
        final v = _numeroValidado(
            recebidasD[chave], 'Dobra ${dobrasCutaneasMedidas[chave]}', 2, 80,
            opcional: true);
        if (v != null) dobras[chave] = v.toDouble();
      }
    }

    // Fotos: no máximo uma por pose, só nomes de arquivo válidos.
    final fotos = <Map<String, String>>[];
    final recebidasF = recebida['fotos'];
    if (recebidasF is List) {
      final usadas = <String>{};
      for (final f in recebidasF) {
        if (f is! Map) continue;
        final vista = f['vista'];
        final arquivo = f['arquivo'];
        if (vista is! String || !vistasFoto.containsKey(vista)) continue;
        if (arquivo is! String || !_nomeFoto.hasMatch(arquivo)) continue;
        if (!usadas.add(vista)) continue;
        fotos.add({'vista': vista, 'arquivo': arquivo});
      }
    }

    final obs = (recebida['observacao'] as String? ?? '').trim();
    if (obs.length > 300) throw Exception('Observação muito longa.');

    if (peso == null &&
        gordura == null &&
        cintura == null &&
        circ.isEmpty &&
        dobras.isEmpty &&
        fotos.isEmpty) {
      throw Exception('Preencha ao menos uma medida ou foto.');
    }

    final medida = <String, dynamic>{
      'versao': 1,
      'id': (recebida['id'] as String?) ?? novoId('medida'),
      'data': data,
      if (peso != null) 'pesoKg': peso,
      if (gordura != null) 'gorduraPct': gordura,
      if (gordura != null && peso != null)
        'massaMagraKg':
            double.parse((peso * (1 - gordura / 100)).toStringAsFixed(1)),
      if (cintura != null) 'cinturaCm': cintura,
      if (circ.isNotEmpty) 'circunferenciasCm': circ,
      if (dobras.isNotEmpty) 'dobrasMm': dobras,
      if (fotos.isNotEmpty) 'fotos': fotos,
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
    final linhas = await db.query('medidas', where: 'id = ?', whereArgs: [id]);
    await db.delete('medidas', where: 'id = ?', whereArgs: [id]);

    // Apaga também os arquivos das fotos dessa avaliação.
    for (final l in linhas) {
      try {
        final m = jsonDecode(l['conteudo'] as String);
        final fotos = m is Map ? m['fotos'] : null;
        if (fotos is List) {
          for (final f in fotos) {
            if (f is Map && f['arquivo'] is String) {
              await apagarFoto(f['arquivo'] as String);
            }
          }
        }
      } catch (_) {}
    }
  }

  // ---------- Fotos (ficam só neste aparelho) ----------

  Future<Directory> pastaFotos() async {
    final base = await getDatabasesPath();
    final dir = Directory(join(base, 'fotos'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> arquivoFoto(String nome) async {
    if (!_nomeFoto.hasMatch(nome)) throw Exception('Foto inválida.');
    final dir = await pastaFotos();
    return File(join(dir.path, nome));
  }

  /// Copia a imagem escolhida para a pasta do app e devolve o nome.
  Future<String> guardarFoto(String origemPath) async {
    final nome = '${novoId('foto')}.jpg';
    final dir = await pastaFotos();
    await File(origemPath).copy(join(dir.path, nome));
    return nome;
  }

  Future<void> apagarFoto(String nome) async {
    try {
      final f = await arquivoFoto(nome);
      if (await f.exists()) await f.delete();
    } catch (_) {}
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
      // As fotos não saem do celular: tiramos a referência delas.
      'medidas': [
        for (final m in (medidas.length > maxMedidas
            ? medidas.sublist(medidas.length - maxMedidas)
            : medidas))
          {...m}..remove('fotos'),
      ],
    };
  }

  // ======================================================================
  // PERSONAL IA
  // ======================================================================

  // ---------- Ajustes simples (chave/valor em texto) ----------

  Future<String?> ajuste(String chave) async {
    final db = await database;
    final l = await db.query('ia_ajustes', where: 'chave = ?', whereArgs: [chave]);
    return l.isEmpty ? null : l.first['valor'] as String;
  }

  Future<void> definirAjuste(String chave, String? valor) async {
    final db = await database;
    if (valor == null || valor.isEmpty) {
      await db.delete('ia_ajustes', where: 'chave = ?', whereArgs: [chave]);
    } else {
      await db.insert(
        'ia_ajustes',
        {'chave': chave, 'valor': valor},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<int> semanasLembreteRevisao() async {
    final v = int.tryParse(await ajuste('ia_lembrete_semanas') ?? '');
    return (v == null || v < 1 || v > 26) ? 6 : v;
  }

  /// Estado do lembrete de revisão (local; não chama a IA nem troca treino).
  Future<Json> lembreteRevisao() async {
    final semanas = await semanasLembreteRevisao();
    final ultima = int.tryParse(await ajuste('ia_ultima_revisao') ?? '');
    final antecipada = (await ajuste('ia_revisao_antecipada')) == '1';
    final agora = DateTime.now();

    int? dias;
    var devido = antecipada;
    String motivo = antecipada ? 'antecipada' : 'em_dia';

    if (ultima != null) {
      dias = agora.difference(DateTime.fromMillisecondsSinceEpoch(ultima)).inDays;
      if (dias >= semanas * 7) {
        devido = true;
        motivo = 'prazo';
      }
    } else {
      // Nunca revisou: passa a valer depois de [semanas] semanas de histórico.
      final resultados = await listarResultados();
      if (resultados.isNotEmpty) {
        final primeiro = resultados
            .map((r) => (r['inicio'] as num).toInt())
            .reduce((a, b) => a < b ? a : b);
        final d = agora
            .difference(DateTime.fromMillisecondsSinceEpoch(primeiro))
            .inDays;
        if (d >= semanas * 7) {
          devido = true;
          motivo = 'sem_revisao';
        }
      }
    }

    return {
      'devido': devido,
      'motivo': motivo,
      'semanas': semanas,
      'diasDesdeUltima': dias,
      'ultimaRevisao': ultima,
    };
  }

  // ---------- Planejamento por exercício ----------

  Future<Map<String, Json>> listarPlanos(String fichaId) async {
    final db = await database;
    final linhas = await db.query(
      'planos_exercicio',
      where: 'ficha_id = ?',
      whereArgs: [fichaId],
    );
    return {
      for (final l in linhas)
        l['exercicio_id'] as String:
            Json.from(jsonDecode(l['conteudo'] as String) as Map),
    };
  }

  Future<Json?> obterPlano(String fichaId, String exercicioId) async {
    final db = await database;
    final linhas = await db.query(
      'planos_exercicio',
      where: 'ficha_id = ? AND exercicio_id = ?',
      whereArgs: [fichaId, exercicioId],
    );
    if (linhas.isEmpty) return null;
    return Json.from(jsonDecode(linhas.first['conteudo'] as String) as Map);
  }

  /// Exercício -> músculo principal confirmado no planejamento (todas as fichas).
  Future<Map<String, String>> musculosConfirmados() async {
    final db = await database;
    final linhas = await db.query('planos_exercicio');
    final r = <String, String>{};
    for (final l in linhas) {
      try {
        final p = jsonDecode(l['conteudo'] as String) as Map;
        final m = p['musculoPrincipal'];
        if (m is String && musculosIA.containsKey(m)) {
          r[l['exercicio_id'] as String] = m;
        }
      } catch (_) {}
    }
    return r;
  }

  Json _validarPlano(Json r) {
    int? inteiro(dynamic v, String campo, int min, int max) {
      if (v == null || (v is String && v.trim().isEmpty)) return null;
      final n = v is num ? v : num.tryParse(v.toString().replaceAll(',', '.'));
      if (n == null || !n.isFinite || n != n.truncateToDouble()) {
        throw Exception('$campo deve ser um número inteiro.');
      }
      if (n < min || n > max) {
        throw Exception('$campo deve ficar entre $min e $max.');
      }
      return n.toInt();
    }

    double? decimal(dynamic v, String campo, double min, double max) {
      if (v == null || (v is String && v.trim().isEmpty)) return null;
      final n = v is num ? v : num.tryParse(v.toString().replaceAll(',', '.'));
      if (n == null || !n.isFinite || n < min || n > max) {
        throw Exception('$campo deve ficar entre $min e $max.');
      }
      return n.toDouble();
    }

    String? texto(dynamic v, String campo, int max) {
      if (v == null) return null;
      if (v is! String) throw Exception('$campo inválido.');
      final t = v.trim();
      if (t.isEmpty) return null;
      if (t.length > max) throw Exception('$campo muito longo (máx. $max).');
      return t;
    }

    final principal = r['objetivoPrincipal'] ?? 'hipertrofia';
    if (principal != 'hipertrofia' && principal != 'forca') {
      throw Exception('Objetivo principal inválido.');
    }
    final secundario = r['objetivoSecundario'];
    if (secundario != null && secundario != 'forca') {
      throw Exception('Objetivo secundário inválido.');
    }
    if (secundario != null && principal == 'forca') {
      throw Exception('O objetivo secundário de força só vale com hipertrofia.');
    }
    final musculo = r['musculoPrincipal'];
    if (musculo != null &&
        (musculo is! String || !musculosIA.containsKey(musculo))) {
      throw Exception('Músculo principal inválido.');
    }

    final repsMin = inteiro(r['repsMin'], 'Reps mínimas', 1, 50);
    final repsMax = inteiro(r['repsMax'], 'Reps máximas', 1, 50);
    if ((repsMin == null) != (repsMax == null)) {
      throw Exception('Informe a faixa de repetições completa (mín. e máx.).');
    }
    if (repsMin != null && repsMax! < repsMin) {
      throw Exception('A repetição máxima não pode ser menor que a mínima.');
    }

    final plano = <String, dynamic>{
      'versao': 1,
      'objetivoPrincipal': principal,
      if (secundario != null) 'objetivoSecundario': secundario,
      if (musculo != null) 'musculoPrincipal': musculo,
      if (repsMin != null) 'repsMin': repsMin,
      if (repsMax != null) 'repsMax': repsMax,
      'atualizado': DateTime.now().millisecondsSinceEpoch,
    };

    void poe(String k, Object? v) {
      if (v != null) plano[k] = v;
    }

    poe('series', inteiro(r['series'], 'Séries de trabalho', 1, 50));
    poe('descansoPlanejadoS',
        inteiro(r['descansoPlanejadoS'], 'Descanso planejado', 5, 3600));
    poe('rirAlvo', inteiro(r['rirAlvo'], 'RIR alvo', 0, 4));
    poe('execucao', texto(r['execucao'], 'Orientação de execução', 200));
    poe('progressao', texto(r['progressao'], 'Regra de progressão', 200));
    poe('incrementoMinimoKg',
        decimal(r['incrementoMinimoKg'], 'Menor incremento de carga', 0.1, 50));
    poe('cargaSugeridaKg',
        decimal(r['cargaSugeridaKg'], 'Carga sugerida', 0, 500));
    return plano;
  }

  Future<Json> salvarPlano(String fichaId, String exercicioId, Json r) async {
    final plano = _validarPlano(r);
    final db = await database;

    final fichas = await db.query('fichas', columns: ['conteudo'],
        where: 'id = ?', whereArgs: [fichaId]);
    if (fichas.isEmpty) throw Exception('Ficha não encontrada.');
    final ficha = jsonDecode(fichas.first['conteudo'] as String) as Map;
    if (!(ficha['exercicios'] as List).any((e) => (e as Map)['id'] == exercicioId)) {
      throw Exception('Exercício não encontrado na ficha.');
    }

    await db.insert(
      'planos_exercicio',
      {
        'ficha_id': fichaId,
        'exercicio_id': exercicioId,
        'conteudo': jsonEncode(plano),
        'atualizado': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return plano;
  }

  // ---------- Esforço da última série (RIR) e desconforto ----------

  Future<List<Json>> listarEsforcos() async {
    final db = await database;
    final linhas = await db.query('esforco_series');
    return [
      for (final l in linhas)
        {
          'resultadoId': l['resultado_id'],
          'exercicioId': l['exercicio_id'],
          'serie': l['serie'],
          'resposta': l['resposta'],
          'desconforto': l['desconforto'],
        },
    ];
  }

  /// Número da última série realizada do exercício naquele treino
  /// (null se o treino não tem séries detalhadas desse exercício).
  Future<int?> ultimaSerieDoExercicio(Json resultado, String exercicioId) async {
    final series = resultado['seriesRealizadas'];
    if (series is! List) return null;
    int? maior;
    for (final s in series) {
      if (s is Map && s['exercicioId'] == exercicioId) {
        final n = (s['serie'] as num).toInt();
        if (maior == null || n > maior) maior = n;
      }
    }
    return maior;
  }

  Future<Json?> obterEsforco(String resultadoId, String exercicioId) async {
    final db = await database;
    final linhas = await db.query(
      'esforco_series',
      where: 'resultado_id = ? AND exercicio_id = ?',
      whereArgs: [resultadoId, exercicioId],
      orderBy: 'serie DESC',
      limit: 1,
    );
    if (linhas.isEmpty) return null;
    final l = linhas.first;
    return {
      'resultadoId': l['resultado_id'],
      'exercicioId': l['exercicio_id'],
      'serie': l['serie'],
      'resposta': l['resposta'],
      'desconforto': l['desconforto'],
    };
  }

  /// Grava resposta e desconforto da ÚLTIMA série do exercício no treino.
  /// Tudo opcional; sem nenhum dos dois, apaga o registro.
  /// Não altera o resultado sincronizado (que é imutável).
  Future<void> salvarEsforco({
    required String resultadoId,
    required String exercicioId,
    String? resposta,
    String? desconforto,
  }) async {
    if (resposta != null && !respostasEsforco.contains(resposta)) {
      throw Exception('Resposta inválida.');
    }
    if (desconforto != null && !niveisDesconforto.contains(desconforto)) {
      throw Exception('Desconforto inválido.');
    }

    final db = await database;
    final linhas = await db.query('resultados', where: 'id = ?', whereArgs: [resultadoId]);
    if (linhas.isEmpty) throw Exception('Treino não encontrado.');
    final resultado = Json.from(jsonDecode(linhas.first['conteudo'] as String) as Map);

    final ultima = await ultimaSerieDoExercicio(resultado, exercicioId);
    if (ultima == null) {
      throw Exception('Este treino não tem as séries detalhadas desse exercício.');
    }

    await db.transaction((tx) async {
      // A resposta vale só para a última série; limpa registro de outra série.
      await tx.delete(
        'esforco_series',
        where: 'resultado_id = ? AND exercicio_id = ?',
        whereArgs: [resultadoId, exercicioId],
      );
      if (resposta == null && desconforto == null) return;
      await tx.insert('esforco_series', {
        'resultado_id': resultadoId,
        'exercicio_id': exercicioId,
        'serie': ultima,
        'resposta': resposta,
        'desconforto': desconforto,
        'atualizado': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  // ---------- Avaliações e sugestões ----------

  /// Reúne os dados e monta o pedido para a IA (resumo calculado no celular).
  Future<Json> montarPedidoIA({
    required String avaliacaoId,
    required String tipo,
    String? fichaId,
    Json? respostasMontagem,
  }) async {
    final fichas = await listarFichas();
    Json? ficha;
    if (fichaId != null) {
      for (final f in fichas) {
        if (f['id'] == fichaId) ficha = f;
      }
      if (ficha == null) throw Exception('A ficha escolhida não existe mais.');
    }
    final perfil = await obterPerfil();

    return ResumoIA.montarPedido(
      avaliacaoId: avaliacaoId,
      tipo: tipo,
      agora: DateTime.now(),
      ficha: ficha,
      resultados: await listarResultados(),
      esforco: await listarEsforcos(),
      planos: fichaId == null ? <String, Json>{} : await listarPlanos(fichaId),
      musculosConfirmados: await musculosConfirmados(),
      perfil: perfil,
      idade: perfil?['nascimento'] is int
          ? idadeEm(perfil!['nascimento'] as int)
          : null,
      medidas: await listarMedidas(),
      respostasMontagem: respostasMontagem,
    );
  }

  Json _linhaAvaliacao(Map<String, Object?> l) => {
        'id': l['id'],
        'tipo': l['tipo'],
        'fichaId': l['ficha_id'],
        'criado': l['criado'],
        'estado': l['estado'],
        'demonstracao': l['demonstracao'] == 1,
        'pedido': Json.from(jsonDecode(l['pedido'] as String) as Map),
        'resposta': l['resposta'] == null
            ? null
            : Json.from(jsonDecode(l['resposta'] as String) as Map),
        'erro': l['erro'],
      };

  /// Cria a avaliação pendente. Se o id já existe (nova tentativa ou toque
  /// duplo), devolve a existente sem criar outra.
  Future<Json> criarAvaliacao({
    required String id,
    required String tipo,
    String? fichaId,
    required Json pedido,
    required bool demonstracao,
  }) async {
    final db = await database;
    await db.insert(
      'avaliacoes_ia',
      {
        'id': id,
        'tipo': tipo,
        'ficha_id': fichaId,
        'criado': DateTime.now().millisecondsSinceEpoch,
        'estado': 'pendente',
        'demonstracao': demonstracao ? 1 : 0,
        'pedido': jsonEncode(pedido),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return (await obterAvaliacao(id))!;
  }

  Future<Json?> obterAvaliacao(String id) async {
    final db = await database;
    final l = await db.query('avaliacoes_ia', where: 'id = ?', whereArgs: [id]);
    return l.isEmpty ? null : _linhaAvaliacao(l.first);
  }

  Future<List<Json>> listarAvaliacoes() async {
    final db = await database;
    final l = await db.query('avaliacoes_ia', orderBy: 'criado DESC');
    return l.map(_linhaAvaliacao).toList();
  }

  /// Guarda a resposta JÁ VALIDADA e cria as sugestões (uma vez só).
  Future<void> concluirAvaliacao(String id, Json resposta) async {
    final db = await database;
    await db.transaction((tx) async {
      final l = await tx.query('avaliacoes_ia', where: 'id = ?', whereArgs: [id]);
      if (l.isEmpty) throw Exception('Avaliação não encontrada.');
      if (l.first['estado'] == 'concluida') return; // idempotente

      await tx.update(
        'avaliacoes_ia',
        {
          'estado': 'concluida',
          'resposta': jsonEncode(resposta),
          'demonstracao': resposta['demonstracao'] == true ? 1 : 0,
          'erro': null,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      final sugestoes = (resposta['sugestoes'] as List?) ?? const [];
      for (var i = 0; i < sugestoes.length; i++) {
        final s = sugestoes[i] as Map;
        await tx.insert(
          'sugestoes_ia',
          {
            'id': '$id:${s['id']}',
            'avaliacao_id': id,
            'ordem': i,
            'estado': 'pendente',
            'conteudo': jsonEncode(s),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      if (l.first['tipo'] == 'revisao') {
        await tx.insert(
          'ia_ajustes',
          {
            'chave': 'ia_ultima_revisao',
            'valor': '${DateTime.now().millisecondsSinceEpoch}',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await tx.delete('ia_ajustes',
            where: 'chave = ?', whereArgs: ['ia_revisao_antecipada']);
      }
    });
  }

  Future<void> falharAvaliacao(String id, String erro) async {
    final db = await database;
    await db.update(
      'avaliacoes_ia',
      {'estado': 'erro', 'erro': erro},
      where: 'id = ? AND estado != ?',
      whereArgs: [id, 'concluida'],
    );
  }

  Future<void> reabrirAvaliacao(String id) async {
    final db = await database;
    await db.update(
      'avaliacoes_ia',
      {'estado': 'pendente', 'erro': null},
      where: 'id = ? AND estado = ?',
      whereArgs: [id, 'erro'],
    );
  }

  Future<void> excluirAvaliacao(String id) async {
    final db = await database;
    await db.transaction((tx) async {
      await tx.delete('sugestoes_ia', where: 'avaliacao_id = ?', whereArgs: [id]);
      await tx.delete('avaliacoes_ia', where: 'id = ?', whereArgs: [id]);
    });
  }

  Json _linhaSugestao(Map<String, Object?> l) => {
        ...Json.from(jsonDecode(l['conteudo'] as String) as Map),
        'chave': l['id'],
        'avaliacaoId': l['avaliacao_id'],
        'estado': l['estado'],
        'decidido': l['decidido'],
      };

  Future<List<Json>> listarSugestoes({String? avaliacaoId, String? estado}) async {
    final db = await database;
    final onde = <String>[];
    final args = <Object?>[];
    if (avaliacaoId != null) {
      onde.add('avaliacao_id = ?');
      args.add(avaliacaoId);
    }
    if (estado != null) {
      onde.add('estado = ?');
      args.add(estado);
    }
    final l = await db.query(
      'sugestoes_ia',
      where: onde.isEmpty ? null : onde.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'avaliacao_id DESC, ordem ASC',
    );
    return l.map(_linhaSugestao).toList();
  }

  Future<Json?> _fichaPorId(DatabaseExecutor db, String id) async {
    final l = await db.query('fichas', where: 'id = ?', whereArgs: [id]);
    if (l.isEmpty) return null;
    return Json.from(jsonDecode(l.first['conteudo'] as String) as Map);
  }

  /// null se a sugestão ainda pode ser aplicada; senão, o motivo.
  Future<String?> motivoNaoAplicavel(Json sugestao) async {
    final estado = sugestao['estado'];
    if (estado == 'aceita') return 'Já aplicada.';
    if (estado == 'ignorada') return 'Você ignorou esta sugestão.';
    if (estado == 'obsoleta') return 'A ficha mudou depois da análise.';
    if (!acoesAplicaveis.contains(sugestao['acao'])) {
      return 'Sugestão informativa.';
    }
    final db = await database;
    final av = await db.query('avaliacoes_ia',
        where: 'id = ?', whereArgs: [sugestao['avaliacaoId']]);
    if (av.isEmpty) return 'Avaliação não encontrada.';
    final fichaId = av.first['ficha_id'] as String?;
    if (fichaId == null) return 'Sem ficha associada.';
    final ficha = await _fichaPorId(db, fichaId);
    final plano = await obterPlano(fichaId, '${sugestao['exercicioId']}');
    try {
      calcularEfeito(sugestao, ficha: ficha, planoAtual: plano);
      return null;
    } on ConflitoSugestao catch (e) {
      return e.mensagem;
    }
  }

  /// Aplica uma sugestão. Seguro contra toque duplo: aplicar de novo não
  /// repete a mudança. Não sobrescreve se a ficha foi editada depois da
  /// análise (a sugestão vira "obsoleta"). Treinos passados nunca mudam.
  Future<Json> aplicarSugestao(String chave) async {
    final db = await database;
    String? conflito;
    var jaAplicada = false;
    String? destino;

    await db.transaction((tx) async {
      final l = await tx.query('sugestoes_ia', where: 'id = ?', whereArgs: [chave]);
      if (l.isEmpty) throw Exception('Sugestão não encontrada.');
      final estado = l.first['estado'];
      if (estado == 'aceita') {
        jaAplicada = true;
        return;
      }
      if (estado == 'ignorada') {
        throw Exception('Você já ignorou esta sugestão.');
      }
      if (estado == 'obsoleta') {
        throw Exception('A ficha mudou depois da análise. Nada foi alterado.');
      }

      final sug = Json.from(jsonDecode(l.first['conteudo'] as String) as Map);
      final av = await tx.query('avaliacoes_ia',
          where: 'id = ?', whereArgs: [l.first['avaliacao_id']]);
      final fichaId = av.isEmpty ? null : av.first['ficha_id'] as String?;
      if (fichaId == null) throw Exception('Sugestão sem ficha associada.');

      final ficha = await _fichaPorId(tx, fichaId);
      final exId = '${sug['exercicioId']}';
      final pl = await tx.query('planos_exercicio',
          where: 'ficha_id = ? AND exercicio_id = ?', whereArgs: [fichaId, exId]);
      final planoAtual = pl.isEmpty
          ? null
          : Json.from(jsonDecode(pl.first['conteudo'] as String) as Map);

      final EfeitoSugestao efeito;
      try {
        efeito = calcularEfeito(sug, ficha: ficha, planoAtual: planoAtual);
      } on ConflitoSugestao catch (e) {
        conflito = e.mensagem;
        return;
      }

      if (efeito.ficha != null) {
        _validarFicha(efeito.ficha!);
        await _gravarFichaTx(tx, efeito.ficha!);
        destino = 'ficha';
      } else {
        final novo = _validarPlano({...efeito.plano!});
        await tx.insert(
          'planos_exercicio',
          {
            'ficha_id': fichaId,
            'exercicio_id': efeito.exercicioId,
            'conteudo': jsonEncode(novo),
            'atualizado': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        destino = 'plano';
      }

      await tx.update(
        'sugestoes_ia',
        {'estado': 'aceita', 'decidido': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [chave],
      );
    });

    if (conflito != null) {
      await db.update(
        'sugestoes_ia',
        {'estado': 'obsoleta', 'decidido': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ? AND estado = ?',
        whereArgs: [chave, 'pendente'],
      );
      throw Exception('$conflito Nada foi alterado.');
    }

    return {'jaAplicada': jaAplicada, 'destino': destino};
  }

  Future<void> ignorarSugestao(String chave) async {
    final db = await database;
    await db.update(
      'sugestoes_ia',
      {'estado': 'ignorada', 'decidido': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ? AND estado = ?',
      whereArgs: [chave, 'pendente'],
    );
  }

  // ---------- Ficha nova a partir de um rascunho (após confirmação) ----------

  /// Salva UMA ficha do rascunho que o usuário revisou e confirmou.
  /// Só entra na lista agora; nenhuma ficha em uso é substituída.
  Future<Json> confirmarFichaDoRascunho(Json f) async {
    String maiusculo(dynamic v) {
      final t = '$v'.trim().toUpperCase();
      return t.length > 100 ? t.substring(0, 100) : t;
    }

    final exercicios = <Json>[];
    final planos = <String, Json>{};

    for (final e in (f['exercicios'] as List).cast<Map>()) {
      final id = novoId('ex');
      exercicios.add({
        'id': id,
        'nome': maiusculo(e['nome']),
        'series': e['series'],
        // O relógio aceita uma meta inteira: usamos o topo da faixa.
        'reps': e['repsMax'],
        'carga': 0,
        'descanso': e['descansoS'],
      });
      planos[id] = {
        'objetivoPrincipal': 'hipertrofia',
        if (e['objetivoSecundario'] != null)
          'objetivoSecundario': e['objetivoSecundario'],
        if (e['musculoPrincipal'] != null)
          'musculoPrincipal': e['musculoPrincipal'],
        'repsMin': e['repsMin'],
        'repsMax': e['repsMax'],
        'series': e['series'],
        'descansoPlanejadoS': e['descansoS'],
        'rirAlvo': e['rirAlvo'],
        'execucao': e['execucao'],
        'progressao': e['progressao'],
      };
    }

    final ficha = <String, dynamic>{
      'id': novoId('ficha'),
      'nome': maiusculo(f['nome']),
      'exercicios': exercicios,
    };

    _validarFicha(ficha);
    final validados = {
      for (final e in planos.entries) e.key: _validarPlano(e.value),
    };

    final db = await database;
    await db.transaction((tx) async {
      await _gravarFichaTx(tx, ficha);
      for (final e in validados.entries) {
        await tx.insert('planos_exercicio', {
          'ficha_id': ficha['id'],
          'exercicio_id': e.key,
          'conteudo': jsonEncode(e.value),
          'atualizado': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
    return ficha;
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

    await db.transaction((tx) => _gravarFichaTx(tx, ficha));
  }

  /// Grava (insere ou atualiza) uma ficha já validada e sobe a revisão que o
  /// relógio usa para saber se há fichas novas.
  Future<void> _gravarFichaTx(DatabaseExecutor tx, Json ficha) async {
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
        await tx.delete(
          'planos_exercicio',
          where: 'ficha_id = ?',
          whereArgs: [id],
        );

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