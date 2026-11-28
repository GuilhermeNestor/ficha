// Núcleo do Personal IA: Dart puro (sem Flutter nem SQLite).
//
// - monta o resumo (fatos calculados no celular) que vai para a IA;
// - valida a resposta da IA (contrato versão 1);
// - gera uma resposta de demonstração (provedor simulado);
// - aplica uma sugestão sobre uma ficha, conferindo se ela mudou.
//
// Nada aqui lê ou grava no banco. Quem chama passa os dados.

import 'dart:convert';

typedef _J = Map<String, dynamic>;

// ---------------------------------------------------------------------------
// Vocabulário
// ---------------------------------------------------------------------------

const musculosIA = <String, String>{
  'peito': 'Peito',
  'costas': 'Costas',
  'ombros': 'Ombros',
  'biceps': 'Bíceps',
  'triceps': 'Tríceps',
  'quadriceps': 'Quadríceps',
  'posteriores': 'Posteriores de coxa',
  'gluteos': 'Glúteos',
  'panturrilhas': 'Panturrilhas',
  'abdomen': 'Abdômen',
};

const equipamentosIA = <String, String>{
  'maquinas': 'Máquinas',
  'cabos': 'Cabos / polias',
  'halteres': 'Halteres',
  'barras': 'Barras e anilhas',
  'corporal': 'Peso do corpo',
};

const respostasEsforco = ['0', '1', '2', '3+', 'nao_sei'];
const niveisDesconforto = ['leve', 'moderado', 'forte'];

const acoesSugestao = [
  'manter',
  'ajustar_series',
  'sugerir_carga',
  'ajustar_plano',
  'trocar_exercicio',
  'observar',
];

/// Ações que o app sabe aplicar. As outras são só informativas.
const acoesAplicaveis = ['ajustar_series', 'sugerir_carga', 'ajustar_plano'];

const camposPlanoAjustaveis = [
  'repsMin',
  'repsMax',
  'rirAlvo',
  'descansoPlanejadoS',
];

const tiposAvaliacao = ['semana', 'revisao', 'montar'];

/// Mapeamento conservador por nome EXATO (normalizado). Se o nome não está
/// aqui e o exercício não tem músculo confirmado no planejamento, o volume
/// por músculo fica "desconhecido" para ele.
const _mapaMusculos = <String, List<List<String>>>{
  // nome: [diretos, indiretos]
  'SUPINO RETO': [['peito'], ['triceps', 'ombros']],
  'SUPINO INCLINADO': [['peito'], ['triceps', 'ombros']],
  'SUPINO DECLINADO': [['peito'], ['triceps']],
  'CRUCIFIXO': [['peito'], []],
  'CRUZAMENTO DE CABOS': [['peito'], []],
  'TRICEPS CORDA': [['triceps'], []],
  'TRICEPS TESTA': [['triceps'], []],
  'TRICEPS PULLEY': [['triceps'], []],
  'PUXADA FRENTE': [['costas'], ['biceps']],
  'PUXADA ALTA': [['costas'], ['biceps']],
  'REMADA CURVADA': [['costas'], ['biceps']],
  'REMADA BAIXA': [['costas'], ['biceps']],
  'REMADA SENTADA': [['costas'], ['biceps']],
  'ROSCA DIRETA': [['biceps'], []],
  'ROSCA ALTERNADA': [['biceps'], []],
  'ROSCA MARTELO': [['biceps'], []],
  'DESENVOLVIMENTO': [['ombros'], ['triceps']],
  'ELEVACAO LATERAL': [['ombros'], []],
  'AGACHAMENTO': [['quadriceps', 'gluteos'], ['posteriores']],
  'LEG PRESS': [['quadriceps'], ['gluteos']],
  'CADEIRA EXTENSORA': [['quadriceps'], []],
  'MESA FLEXORA': [['posteriores'], []],
  'CADEIRA FLEXORA': [['posteriores'], []],
  'STIFF': [['posteriores'], ['gluteos']],
  'ELEVACAO PELVICA': [['gluteos'], ['posteriores']],
  'PANTURRILHA EM PE': [['panturrilhas'], []],
  'PANTURRILHA SENTADO': [['panturrilhas'], []],
  'ABDOMINAL': [['abdomen'], []],
};

String normalizarNome(String s) {
  const de = 'ÁÀÂÃÄáàâãäÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇçÑñ';
  const para = 'AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCcNn';
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final i = de.indexOf(c);
    b.write(i >= 0 ? para[i] : c);
  }
  return b.toString().toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

// ---------------------------------------------------------------------------
// Utilidades
// ---------------------------------------------------------------------------

double? _num(dynamic v) =>
    v is num && v.isFinite ? v.toDouble() : null;

int? _int(dynamic v) => v is num && v.isFinite ? v.toInt() : null;

String _dia(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

DateTime _segunda(DateTime d) {
  final dia = DateTime(d.year, d.month, d.day);
  return dia.subtract(Duration(days: dia.weekday - 1));
}

/// Número sem ".0" quando inteiro: 40.0 -> "40", 42.5 -> "42,5".
String fmtNum(num v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString().replaceAll('.', ',');
}

/// Ordem das respostas de esforço da mais perto da falha para a mais longe.
int? rirComoNumero(String? resposta) {
  switch (resposta) {
    case '0':
      return 0;
    case '1':
      return 1;
    case '2':
      return 2;
    case '3+':
      return 3;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Resumo (fatos calculados no celular)
// ---------------------------------------------------------------------------

class ResumoIA {
  ResumoIA._();

  /// Monta o pedido que vai para a IA. Não lê o banco.
  ///
  /// [resultados]: todos os treinos sincronizados (mais novo primeiro ou não).
  /// [esforco]: linhas {resultadoId, exercicioId, serie, resposta, desconforto}.
  /// [planos]: planejamento da ficha em análise, por id de exercício.
  /// [musculosConfirmados]: exercício -> músculo principal definido no
  ///   planejamento (vale mais que o dicionário de nomes).
  static _J montarPedido({
    required String avaliacaoId,
    required String tipo,
    required DateTime agora,
    required _J? ficha,
    required List<_J> resultados,
    required List<_J> esforco,
    required Map<String, _J> planos,
    required Map<String, String> musculosConfirmados,
    required _J? perfil,
    required int? idade,
    required List<_J> medidas,
    _J? respostasMontagem,
  }) {
    if (!tiposAvaliacao.contains(tipo)) {
      throw ArgumentError('Tipo de avaliação inválido.');
    }
    if (tipo != 'montar' && ficha == null) {
      throw ArgumentError('Escolha a ficha em análise.');
    }

    final janelaDias = tipo == 'semana' ? 7 : null;
    final fim = agora.millisecondsSinceEpoch;
    final inicioJanela = janelaDias == null
        ? null
        : DateTime(agora.year, agora.month, agora.day - janelaDias + 1)
            .millisecondsSinceEpoch;

    // Esforço por (resultado, exercício, série).
    final esf = <String, _J>{};
    for (final e in esforco) {
      esf['${e['resultadoId']}|${e['exercicioId']}|${e['serie']}'] = e;
    }

    final pedido = <String, dynamic>{
      'versao': 1,
      'avaliacaoId': avaliacaoId,
      'tipo': tipo,
      'geradoEm': agora.toUtc().toIso8601String(),
      'perfil': _perfilSeguro(perfil, idade),
      'corpo': _corpo(medidas),
    };

    if (tipo == 'montar') {
      pedido['respostas'] = respostasMontagem ?? <String, dynamic>{};
      pedido['faltando'] = _faltandoMontagem(respostasMontagem);
      pedido['volumeSemanalPorMusculo'] = _volumeSemanal(
        resultados: resultados,
        agora: agora,
        musculosConfirmados: musculosConfirmados,
        semanas: 6,
      );
      pedido['sessoes'] = <_J>[];
      pedido['exercicios'] = <_J>[];
      return pedido;
    }

    final fichaId = ficha!['id'] as String;
    final exercicios = (ficha['exercicios'] as List).cast<Map>();

    final doFicha = resultados.where((r) => r['fichaId'] == fichaId).toList()
      ..sort((a, b) =>
          (_int(a['inicio']) ?? 0).compareTo(_int(b['inicio']) ?? 0));

    final naJanela = doFicha.where((r) {
      final i = _int(r['inicio']) ?? 0;
      return inicioJanela == null || i >= inicioJanela;
    }).toList();

    final limiteSessoes = tipo == 'semana' ? 4 : 12;
    final usadas = doFicha.length > limiteSessoes
        ? doFicha.sublist(doFicha.length - limiteSessoes)
        : doFicha;
    // Na semana, as sessões da janela sempre entram.
    final idsUsadas = <String>{
      for (final r in usadas) r['id'] as String,
      for (final r in naJanela) r['id'] as String,
    };
    final sessoesUsadas = doFicha
        .where((r) => idsUsadas.contains(r['id']))
        .toList();

    pedido['fichaEmAnalise'] = {
      'id': fichaId,
      'nome': ficha['nome'],
    };

    pedido['periodo'] = {
      'tipo': tipo == 'semana' ? 'ultimos_7_dias' : 'historico_completo',
      'inicio': inicioJanela != null
          ? _dia(inicioJanela)
          : (doFicha.isEmpty
              ? 'desconhecido'
              : _dia(_int(doFicha.first['inicio']) ?? 0)),
      'fim': _dia(fim),
      'sessoesNaJanela': naJanela.length,
      'sessoesDaFichaNoTotal': doFicha.length,
      'sessoesEnviadas': sessoesUsadas.length,
      'truncado': doFicha.length > sessoesUsadas.length,
    };

    pedido['sessoes'] = [
      for (final r in sessoesUsadas)
        {
          'id': r['id'],
          'data': _dia(_int(r['inicio']) ?? 0),
          'duracaoMin': ((_int(r['duracaoMs']) ?? 0) / 60000).round(),
          'naJanela': naJanela.any((n) => n['id'] == r['id']),
        },
    ];

    pedido['exercicios'] = [
      for (final ex in exercicios)
        _resumoExercicio(
          ex: Map<String, dynamic>.from(ex),
          plano: planos[ex['id']],
          sessoes: sessoesUsadas,
          esforco: esf,
        ),
    ];

    pedido['volumeSemanalPorMusculo'] = _volumeSemanal(
      resultados: resultados,
      agora: agora,
      musculosConfirmados: musculosConfirmados,
      semanas: tipo == 'semana' ? 4 : 8,
    );

    return pedido;
  }

  static _J _perfilSeguro(_J? p, int? idade) {
    dynamic d(dynamic v) => v ?? 'desconhecido';
    return {
      'idade': d(idade),
      'sexo': d(p?['sexo']),
      'alturaCm': d(p?['alturaCm']),
      'objetivo': d(p?['objetivo']),
      'nivel': d(p?['nivel']),
      'diasPorSemana': d(p?['diasPorSemana']),
      'pesoMetaKg': d(p?['pesoMetaKg']),
      'gorduraMetaPct': d(p?['gorduraMetaPct']),
    };
  }

  static _J _corpo(List<_J> medidas) {
    final ordenadas = [...medidas]
      ..sort((a, b) => (_int(a['data']) ?? 0).compareTo(_int(b['data']) ?? 0));

    List<_J> serie(String chave) {
      final r = <_J>[];
      for (final m in ordenadas) {
        final v = _num(m[chave]);
        if (v != null) r.add({'data': _dia(_int(m['data']) ?? 0), 'valor': v});
      }
      return r.length > 6 ? r.sublist(r.length - 6) : r;
    }

    final peso = serie('pesoKg');
    final gordura = serie('gorduraPct');
    final cintura = serie('cinturaCm');

    return {
      'pesoKg': peso.isEmpty ? 'desconhecido' : peso,
      'gorduraPct': gordura.isEmpty ? 'desconhecido' : gordura,
      'cinturaCm': cintura.isEmpty ? 'desconhecido' : cintura,
    };
  }

  static List<String> _faltandoMontagem(_J? r) {
    final falta = <String>[];
    if (r == null) return ['objetivo', 'experiencia', 'diasDisponiveis',
      'minutosPorSessao', 'equipamentos', 'musculosPrioritarios'];
    if ((r['objetivo'] as String?)?.isNotEmpty != true) falta.add('objetivo');
    if ((r['experiencia'] as String?)?.isNotEmpty != true) {
      falta.add('experiencia');
    }
    if (_int(r['diasDisponiveis']) == null) falta.add('diasDisponiveis');
    if (_int(r['minutosPorSessao']) == null) falta.add('minutosPorSessao');
    if (r['equipamentos'] is! List || (r['equipamentos'] as List).isEmpty) {
      falta.add('equipamentos');
    }
    if (r['musculosPrioritarios'] is! List) falta.add('musculosPrioritarios');
    return falta;
  }

  static _J _resumoExercicio({
    required _J ex,
    required _J? plano,
    required List<_J> sessoes,
    required Map<String, _J> esforco,
  }) {
    final exId = ex['id'] as String;
    final nomeAtual = normalizarNome(ex['nome'] as String);

    var nomeDiferente = 0;
    var semSeries = 0;
    final saida = <_J>[];

    for (final r in sessoes) {
      final rid = r['id'] as String;
      final todas = r['seriesRealizadas'];
      final lista = <_J>[];
      var nomeOutro = false;

      if (todas is List) {
        for (final s in todas) {
          if (s is! Map || s['exercicioId'] != exId) continue;
          if (normalizarNome('${s['exercicioNome']}') != nomeAtual) {
            nomeOutro = true;
            continue;
          }
          lista.add(Map<String, dynamic>.from(s));
        }
      }

      if (nomeOutro && lista.isEmpty) {
        // Mesmo ID, mas o nome mudou: pode ser outro exercício/máquina.
        nomeDiferente++;
        continue;
      }

      double? ultimaCarga;
      final cargas = r['cargas'];
      if (cargas is List) {
        for (final c in cargas) {
          if (c is Map && c['exercicioId'] == exId) {
            ultimaCarga = _num(c['ultimaCarga']);
          }
        }
      }

      if (lista.isEmpty) {
        if (todas is! List) semSeries++;
        // Sem séries detalhadas: só a última carga conhecida, se houver.
        if (ultimaCarga != null || todas is! List) {
          saida.add({
            'sessaoId': rid,
            'data': _dia(_int(r['inicio']) ?? 0),
            'series': 'desconhecido',
            'ultimaCargaKg': ultimaCarga ?? 'desconhecido',
            'rirUltimaSerie': 'desconhecido',
            'desconfortoUltimaSerie': 'desconhecido',
          });
        }
        continue;
      }

      lista.sort((a, b) =>
          (_int(a['serie']) ?? 0).compareTo(_int(b['serie']) ?? 0));
      final ultimo = _int(lista.last['serie']) ?? 0;
      final reg = esforco['$rid|$exId|$ultimo'];

      saida.add({
        'sessaoId': rid,
        'data': _dia(_int(r['inicio']) ?? 0),
        'series': [
          for (final s in lista)
            {
              'n': _int(s['serie']),
              'reps': _int(s['repeticoes']),
              'cargaKg': _num(s['carga']),
              'meta': _int(s['meta']),
              'motivoFim': s['motivo'],
            },
        ],
        'ultimaCargaKg': ultimaCarga ?? 'desconhecido',
        'rirUltimaSerie': (reg?['resposta'] as String?) ?? 'desconhecido',
        'desconfortoUltimaSerie':
            (reg?['desconforto'] as String?) ?? 'nenhum_registrado',
      });
    }

    return {
      'exercicioId': exId,
      'nome': ex['nome'],
      'planejadoFicha': {
        'series': ex['series'],
        'reps': ex['reps'],
        'cargaKg': ex['carga'],
        'descansoS': ex['descanso'],
      },
      'plano': plano == null ? 'desconhecido' : _planoPublico(plano),
      'sessoes': saida,
      'sessoesComNomeDiferente': nomeDiferente,
      'sessoesSemSeriesDetalhadas': semSeries,
      'origemContagem': 'desconhecida',
      'tendencia': tendencia(saida),
    };
  }

  static _J _planoPublico(_J p) => {
        for (final k in const [
          'objetivoPrincipal',
          'objetivoSecundario',
          'musculoPrincipal',
          'repsMin',
          'repsMax',
          'series',
          'descansoPlanejadoS',
          'rirAlvo',
          'execucao',
          'progressao',
          'incrementoMinimoKg',
          'cargaSugeridaKg',
        ])
          if (p[k] != null) k: p[k],
      };

  /// Tendência entre as duas últimas sessões com séries detalhadas.
  static _J tendencia(List<_J> sessoes) {
    final comSeries = sessoes.where((s) => s['series'] is List).toList();
    if (comSeries.length < 2) {
      return {
        'status': 'insuficiente',
        'detalhe': 'Menos de 2 sessões com séries detalhadas.',
        'esforcoConhecido': false,
      };
    }
    final a = comSeries[comSeries.length - 2];
    final b = comSeries[comSeries.length - 1];
    final sa = (a['series'] as List).cast<Map>();
    final sb = (b['series'] as List).cast<Map>();

    double cargaMax(List<Map> l) => l
        .map((s) => _num(s['cargaKg']) ?? 0)
        .fold<double>(0, (m, v) => v > m ? v : m);

    int total(List<Map> l) =>
        l.fold<int>(0, (n, s) => n + (_int(s['reps']) ?? 0));

    final conhecido = rirComoNumero(a['rirUltimaSerie'] as String?) != null &&
        rirComoNumero(b['rirUltimaSerie'] as String?) != null;

    if ((cargaMax(sa) - cargaMax(sb)).abs() > 0.01) {
      return {
        'status': 'carga_mudou',
        'detalhe':
            'Carga ${fmtNum(cargaMax(sa))} kg -> ${fmtNum(cargaMax(sb))} kg.',
        'esforcoConhecido': conhecido,
      };
    }
    if (sa.length != sb.length) {
      return {
        'status': 'insuficiente',
        'detalhe': 'Número de séries diferente entre as sessões.',
        'esforcoConhecido': conhecido,
      };
    }

    final ta = total(sa), tb = total(sb);
    return {
      'status': tb > ta ? 'subindo' : (tb < ta ? 'caindo' : 'estavel'),
      'detalhe': 'Total de repetições $ta -> $tb com '
          '${fmtNum(cargaMax(sb))} kg.',
      'esforcoConhecido': conhecido,
    };
  }

  static _J _volumeSemanal({
    required List<_J> resultados,
    required DateTime agora,
    required Map<String, String> musculosConfirmados,
    required int semanas,
  }) {
    final inicioJanela = _segunda(agora).subtract(Duration(days: 7 * (semanas - 1)));
    final porSemana = <String, Map<String, List<int>>>{};
    var mapeadas = 0, semMapa = 0, total = 0;

    for (final r in resultados) {
      final ini = _int(r['inicio']);
      final series = r['seriesRealizadas'];
      if (ini == null || series is! List) continue;
      final data = DateTime.fromMillisecondsSinceEpoch(ini);
      if (data.isBefore(inicioJanela)) continue;
      final chave = _dia(_segunda(data).millisecondsSinceEpoch);

      for (final s in series) {
        if (s is! Map) continue;
        total++;
        final exId = '${s['exercicioId']}';
        List<String> diretos;
        List<String> indiretos;

        final confirmado = musculosConfirmados[exId];
        final padrao = _mapaMusculos[normalizarNome('${s['exercicioNome']}')];

        if (confirmado != null && musculosIA.containsKey(confirmado)) {
          diretos = [confirmado];
          indiretos = padrao == null
              ? <String>[]
              : padrao[1].where((m) => m != confirmado).toList();
        } else if (padrao != null) {
          diretos = padrao[0];
          indiretos = padrao[1];
        } else {
          semMapa++;
          continue;
        }

        mapeadas++;
        final mapa = porSemana.putIfAbsent(chave, () => {});
        for (final m in diretos) {
          (mapa.putIfAbsent(m, () => [0, 0]))[0]++;
        }
        for (final m in indiretos) {
          (mapa.putIfAbsent(m, () => [0, 0]))[1]++;
        }
      }
    }

    if (total == 0 || mapeadas == 0) {
      return {
        'status': 'indisponivel',
        'motivo': total == 0
            ? 'Sem séries detalhadas no período.'
            : 'Nenhum exercício com músculo conhecido.',
      };
    }

    final chaves = porSemana.keys.toList()..sort();
    return {
      'status': semMapa == 0 ? 'ok' : 'parcial',
      'seriesSemMapeamento': semMapa,
      'seriesMapeadas': mapeadas,
      'semanas': [
        for (final c in chaves)
          {
            'semanaInicio': c,
            'musculos': {
              for (final e in porSemana[c]!.entries)
                e.key: {'direto': e.value[0], 'indireto': e.value[1]},
            },
          },
      ],
    };
  }
}

// ---------------------------------------------------------------------------
// Validação da resposta da IA (contrato versão 1)
// ---------------------------------------------------------------------------

class RespostaInvalida implements Exception {
  RespostaInvalida(this.mensagem);
  final String mensagem;

  @override
  String toString() => 'Resposta da IA inválida: $mensagem';
}

class ValidacaoIA {
  ValidacaoIA._();

  static String _texto(dynamic v, String campo, int max,
      {bool obrigatorio = true}) {
    if (v == null && !obrigatorio) return '';
    if (v is! String) throw RespostaInvalida('$campo deve ser texto.');
    final t = v.trim();
    if (obrigatorio && t.isEmpty) throw RespostaInvalida('$campo vazio.');
    if (t.length > max) throw RespostaInvalida('$campo muito longo.');
    return t;
  }

  static int _inteiro(dynamic v, String campo, int min, int max) {
    if (v is! num || !v.isFinite || v != v.truncateToDouble()) {
      throw RespostaInvalida('$campo deve ser inteiro.');
    }
    if (v < min || v > max) {
      throw RespostaInvalida('$campo fora do limite ($min a $max).');
    }
    return v.toInt();
  }

  static double _decimal(dynamic v, String campo, double min, double max) {
    if (v is! num || !v.isFinite) {
      throw RespostaInvalida('$campo deve ser número.');
    }
    if (v < min || v > max) {
      throw RespostaInvalida('$campo fora do limite.');
    }
    return v.toDouble();
  }

  /// Valida e devolve uma cópia só com os campos conhecidos.
  /// Lança [RespostaInvalida] se algo estiver fora do contrato.
  static _J validarResposta(dynamic bruta, _J pedido) {
    if (bruta is! Map) throw RespostaInvalida('formato inesperado.');
    final r = Map<String, dynamic>.from(bruta);

    if (r['versao'] != 1) throw RespostaInvalida('versão não suportada.');
    if (r['avaliacaoId'] != pedido['avaliacaoId']) {
      throw RespostaInvalida('avaliação diferente da pedida.');
    }
    final tipo = pedido['tipo'] as String;
    if (r['tipo'] != tipo) throw RespostaInvalida('tipo diferente do pedido.');

    final sessoesValidas = <String>{
      for (final s in (pedido['sessoes'] as List? ?? const []))
        (s as Map)['id'] as String,
    };
    final exerciciosPedido = <String, Map>{
      for (final e in (pedido['exercicios'] as List? ?? const []))
        (e as Map)['exercicioId'] as String: e,
    };

    final saida = <String, dynamic>{
      'versao': 1,
      'avaliacaoId': r['avaliacaoId'],
      'tipo': tipo,
      'demonstracao': r['demonstracao'] == true,
      'resumo': _texto(r['resumo'], 'resumo', 800),
    };

    final recomendacao = r['recomendacao'];
    if (recomendacao != null) {
      if (recomendacao is! String ||
          !const ['ajustar', 'manter', 'observar'].contains(recomendacao)) {
        throw RespostaInvalida('recomendação inválida.');
      }
      saida['recomendacao'] = recomendacao;
    }

    final sug = r['sugestoes'] ?? const [];
    if (sug is! List || sug.length > 12) {
      throw RespostaInvalida('lista de sugestões inválida.');
    }
    final ids = <String>{};
    final limpas = <_J>[];
    for (final item in sug) {
      if (item is! Map) throw RespostaInvalida('sugestão inválida.');
      limpas.add(_sugestao(Map<String, dynamic>.from(item), ids,
          sessoesValidas, exerciciosPedido));
    }
    saida['sugestoes'] = limpas;

    final perguntas = r['perguntas'] ?? const [];
    if (perguntas is! List || perguntas.length > 5) {
      throw RespostaInvalida('perguntas inválidas.');
    }
    saida['perguntas'] = [
      for (final p in perguntas) _texto(p, 'pergunta', 200),
    ];

    final exp = r['explicacao'];
    if (exp != null) {
      if (exp is! Map) throw RespostaInvalida('explicação inválida.');
      saida['explicacao'] = {
        for (final k in const [
          'volumeEDescanso',
          'faixaReps',
          'encerrarSerie',
          'progressao',
          'forca',
        ])
          if (exp[k] != null) k: _texto(exp[k], 'explicação $k', 900),
      };
    }

    if (tipo == 'montar') {
      saida['rascunho'] = _rascunho(r['rascunho']);
    } else if (r['rascunho'] != null) {
      throw RespostaInvalida('rascunho só é aceito ao montar uma ficha.');
    }

    if (tipo != 'montar' &&
        limpas.isEmpty &&
        (saida['perguntas'] as List).isEmpty &&
        recomendacao != 'manter') {
      throw RespostaInvalida('sem sugestão, pergunta ou recomendação.');
    }

    return saida;
  }

  static _J _sugestao(_J s, Set<String> ids, Set<String> sessoes,
      Map<String, Map> exercicios) {
    final id = _texto(s['id'], 'id da sugestão', 40);
    if (!ids.add(id)) throw RespostaInvalida('id de sugestão repetido.');

    final acao = s['acao'];
    if (acao is! String || !acoesSugestao.contains(acao)) {
      throw RespostaInvalida('ação desconhecida.');
    }

    final confianca = s['confianca'];
    if (confianca is! String ||
        !const ['alta', 'media', 'baixa'].contains(confianca)) {
      throw RespostaInvalida('confiança inválida.');
    }

    final exId = s['exercicioId'];
    Map? exPedido;
    if (exId != null) {
      if (exId is! String || !exercicios.containsKey(exId)) {
        throw RespostaInvalida('exercício inexistente na ficha enviada.');
      }
      exPedido = exercicios[exId];
    } else if (acao != 'observar' && acao != 'manter') {
      throw RespostaInvalida('a ação $acao precisa de um exercício.');
    }

    final evidencia = s['evidencia'] ?? const [];
    if (evidencia is! List || evidencia.length > 6) {
      throw RespostaInvalida('evidência inválida.');
    }
    final ev = <_J>[];
    for (final e in evidencia) {
      if (e is! Map) throw RespostaInvalida('evidência inválida.');
      final sid = e['sessaoId'];
      final eid = e['exercicioId'];
      if (sid is! String || !sessoes.contains(sid)) {
        throw RespostaInvalida('evidência cita uma sessão desconhecida.');
      }
      if (eid is! String || !exercicios.containsKey(eid)) {
        throw RespostaInvalida('evidência cita um exercício desconhecido.');
      }
      ev.add({
        'sessaoId': sid,
        'exercicioId': eid,
        'texto': _texto(e['texto'], 'texto da evidência', 300),
      });
    }
    if (acao != 'observar' && ev.isEmpty) {
      throw RespostaInvalida('toda sugestão precisa de evidência do histórico.');
    }

    final saida = <String, dynamic>{
      'id': id,
      'acao': acao,
      'exercicioId': exId,
      'titulo': _texto(s['titulo'], 'título', 120),
      'motivo': _texto(s['motivo'], 'motivo', 500),
      'evidencia': ev,
      'confianca': confianca,
    };

    if (acoesAplicaveis.contains(acao)) {
      final a = s['alteracao'];
      if (a is! Map) throw RespostaInvalida('falta a alteração proposta.');
      final planejado = exPedido!['planejadoFicha'] as Map;

      switch (acao) {
        case 'ajustar_series':
          final de = _inteiro(a['de'], 'séries atuais', 1, 50);
          final para = _inteiro(a['para'], 'séries propostas', 1, 50);
          if (de == para) throw RespostaInvalida('alteração sem efeito.');
          if ((para - de).abs() > 2) {
            throw RespostaInvalida('mudança de séries grande demais.');
          }
          if (planejado['series'] != de) {
            throw RespostaInvalida('séries atuais não batem com a ficha.');
          }
          saida['alteracao'] = {'de': de, 'para': para};
          break;
        case 'sugerir_carga':
          final de = _decimal(a['cargaAtualKg'], 'carga atual', 0, 500);
          final para = _decimal(a['cargaSugeridaKg'], 'carga sugerida', 0, 500);
          if (para == de) throw RespostaInvalida('alteração sem efeito.');
          if (de > 0 && para > de * 1.25) {
            throw RespostaInvalida('aumento de carga acima do limite de segurança.');
          }
          saida['alteracao'] = {'cargaAtualKg': de, 'cargaSugeridaKg': para};
          break;
        case 'ajustar_plano':
          final campo = a['campo'];
          if (campo is! String || !camposPlanoAjustaveis.contains(campo)) {
            throw RespostaInvalida('campo do planejamento inválido.');
          }
          final max = campo == 'descansoPlanejadoS'
              ? 600
              : (campo == 'rirAlvo' ? 4 : 50);
          final min = campo == 'descansoPlanejadoS'
              ? 15
              : (campo == 'rirAlvo' ? 0 : 1);
          final de = a['de'] == null ? null : _inteiro(a['de'], 'valor atual', min, max);
          final para = _inteiro(a['para'], 'valor proposto', min, max);
          if (de == para) throw RespostaInvalida('alteração sem efeito.');
          saida['alteracao'] = {'campo': campo, 'de': de, 'para': para};
          break;
      }
    } else if (s['alteracao'] != null) {
      throw RespostaInvalida('a ação $acao não aceita alteração.');
    }

    return saida;
  }

  static _J _rascunho(dynamic bruto) {
    if (bruto is! Map) throw RespostaInvalida('falta o rascunho da ficha.');
    final fichas = bruto['fichas'];
    if (fichas is! List || fichas.isEmpty || fichas.length > 7) {
      throw RespostaInvalida('o rascunho precisa de 1 a 7 fichas.');
    }

    final saida = <_J>[];
    for (final f in fichas) {
      if (f is! Map) throw RespostaInvalida('ficha inválida.');
      final exs = f['exercicios'];
      if (exs is! List || exs.isEmpty || exs.length > 12) {
        throw RespostaInvalida('cada ficha precisa de 1 a 12 exercícios.');
      }
      final lista = <_J>[];
      for (final e in exs) {
        if (e is! Map) throw RespostaInvalida('exercício inválido.');
        final min = _inteiro(e['repsMin'], 'reps mínimas', 1, 50);
        final max = _inteiro(e['repsMax'], 'reps máximas', 1, 50);
        if (max < min) throw RespostaInvalida('faixa de reps invertida.');
        final musculo = e['musculoPrincipal'];
        if (musculo != null &&
            (musculo is! String || !musculosIA.containsKey(musculo))) {
          throw RespostaInvalida('músculo desconhecido.');
        }
        final sec = e['objetivoSecundario'];
        if (sec != null && sec != 'forca') {
          throw RespostaInvalida('objetivo secundário inválido.');
        }
        lista.add({
          'nome': _texto(e['nome'], 'nome do exercício', 100),
          'series': _inteiro(e['series'], 'séries', 1, 10),
          'repsMin': min,
          'repsMax': max,
          'descansoS': _inteiro(e['descansoS'], 'descanso', 15, 600),
          'rirAlvo': _inteiro(e['rirAlvo'], 'RIR alvo', 0, 4),
          'execucao': _texto(e['execucao'], 'execução', 200),
          'progressao': _texto(e['progressao'], 'progressão', 200),
          'musculoPrincipal': musculo,
          'objetivoSecundario': sec,
          'porque': _texto(e['porque'], 'por que o exercício', 400),
        });
      }
      saida.add({
        'nome': _texto(f['nome'], 'nome da ficha', 100),
        'exercicios': lista,
      });
    }
    return {'fichas': saida};
  }
}

// ---------------------------------------------------------------------------
// Aplicar uma sugestão
// ---------------------------------------------------------------------------

class ConflitoSugestao implements Exception {
  ConflitoSugestao(this.mensagem);
  final String mensagem;

  @override
  String toString() => mensagem;
}

/// O que aplicar muda: a ficha (relógio) ou o planejamento (só celular).
class EfeitoSugestao {
  EfeitoSugestao.ficha(this.ficha)
      : exercicioId = null,
        plano = null;
  EfeitoSugestao.plano(this.exercicioId, this.plano) : ficha = null;

  final _J? ficha;
  final String? exercicioId;
  final _J? plano;
}

/// Confere se a ficha/plano ainda têm o valor analisado e devolve o efeito.
/// Lança [ConflitoSugestao] se o usuário já mudou o valor (não sobrescreve).
EfeitoSugestao calcularEfeito(
  _J sugestao, {
  required _J? ficha,
  required _J? planoAtual,
}) {
  final acao = sugestao['acao'];
  final exId = sugestao['exercicioId'];
  final alteracao = sugestao['alteracao'];

  if (!acoesAplicaveis.contains(acao) || alteracao is! Map) {
    throw ConflitoSugestao('Esta sugestão é só informativa.');
  }
  if (ficha == null) {
    throw ConflitoSugestao('A ficha analisada não existe mais.');
  }

  final lista = (ficha['exercicios'] as List).cast<Map>();
  final i = lista.indexWhere((e) => e['id'] == exId);
  if (i < 0) {
    throw ConflitoSugestao('O exercício não está mais na ficha.');
  }

  if (acao == 'ajustar_series') {
    if (lista[i]['series'] != alteracao['de']) {
      throw ConflitoSugestao(
          'A ficha foi editada depois da análise (séries agora: '
          '${lista[i]['series']}).');
    }
    final nova = jsonDecode(jsonEncode(ficha)) as Map<String, dynamic>;
    ((nova['exercicios'] as List)[i] as Map)['series'] = alteracao['para'];
    return EfeitoSugestao.ficha(nova);
  }

  final plano = Map<String, dynamic>.from(planoAtual ?? const {});

  if (acao == 'sugerir_carga') {
    final atual = _num(lista[i]['carga']);
    final analisada = _num(alteracao['cargaAtualKg']);
    final ultima = _num(plano['cargaSugeridaKg']);
    // Vale se a carga da ficha ainda é a analisada, ou se a última
    // sugestão aplicada já era a carga analisada.
    final confere = (atual != null && analisada != null &&
            (atual - analisada).abs() < 0.01) ||
        (ultima != null && analisada != null &&
            (ultima - analisada).abs() < 0.01);
    if (!confere) {
      throw ConflitoSugestao(
          'A carga da ficha mudou depois da análise. Nada foi alterado.');
    }
    plano['cargaSugeridaKg'] = alteracao['cargaSugeridaKg'];
    return EfeitoSugestao.plano(exId as String, plano);
  }

  // ajustar_plano
  final campo = alteracao['campo'] as String;
  final de = alteracao['de'];
  if (de != null && plano[campo] != de) {
    throw ConflitoSugestao(
        'O planejamento foi editado depois da análise. Nada foi alterado.');
  }
  plano[campo] = alteracao['para'];
  final mn = _int(plano['repsMin']);
  final mx = _int(plano['repsMax']);
  if (mn != null && mx != null && mx < mn) {
    throw ConflitoSugestao('A faixa de repetições ficaria invertida.');
  }
  return EfeitoSugestao.plano(exId as String, plano);
}

// ---------------------------------------------------------------------------
// Provedor simulado (demonstração)
// ---------------------------------------------------------------------------

class ProvedorSimulado {
  ProvedorSimulado._();

  /// Responde como a IA responderia, mas só com regras locais simples.
  /// Sempre marcado como demonstração.
  static _J responder(_J pedido) {
    final tipo = pedido['tipo'] as String;
    if (tipo == 'montar') return _montar(pedido);
    return _avaliar(pedido);
  }

  static _J _avaliar(_J pedido) {
    final tipo = pedido['tipo'] as String;
    final sugestoes = <_J>[];
    final perguntas = <String>[];
    var n = 0;

    String id() => 's${++n}';

    for (final e in (pedido['exercicios'] as List).cast<Map>()) {
      final exId = e['exercicioId'] as String;
      final nome = e['nome'] as String;
      final plano = e['plano'] is Map ? e['plano'] as Map : null;
      final planejado = e['planejadoFicha'] as Map;
      final sessoes = (e['sessoes'] as List)
          .cast<Map>()
          .where((s) => s['series'] is List)
          .toList();
      final tend = e['tendencia'] as Map;

      if (sessoes.length < 2) {
        if (sessoes.isEmpty) continue;
        sugestoes.add({
          'id': id(),
          'acao': 'observar',
          'exercicioId': exId,
          'titulo': 'Observar $nome por mais uma sessão',
          'motivo':
              'Só há uma sessão com séries detalhadas; é pouco para comparar.',
          'evidencia': [
            {
              'sessaoId': sessoes.last['sessaoId'],
              'exercicioId': exId,
              'texto': 'Sessão de ${sessoes.last['data']}: '
                  '${_repsTexto(sessoes.last)}.',
            },
          ],
          'confianca': 'baixa',
        });
        continue;
      }

      final a = sessoes[sessoes.length - 2];
      final b = sessoes[sessoes.length - 1];
      final alvoMax = _int(plano?['repsMax']) ?? _int(planejado['reps']) ?? 0;
      final seriesB = (b['series'] as List).cast<Map>();
      final todasNoTopo = alvoMax > 0 &&
          seriesB.every((s) => (_int(s['reps']) ?? 0) >= alvoMax);
      final carga = _num(seriesB.isEmpty ? null : seriesB.last['cargaKg']);
      final rirB = rirComoNumero(b['rirUltimaSerie'] as String?);
      final desconforto = b['desconfortoUltimaSerie'];

      final evid = [
        {
          'sessaoId': a['sessaoId'],
          'exercicioId': exId,
          'texto': 'Sessão de ${a['data']}: ${_repsTexto(a)}.',
        },
        {
          'sessaoId': b['sessaoId'],
          'exercicioId': exId,
          'texto': 'Sessão de ${b['data']}: ${_repsTexto(b)}.',
        },
      ];

      if (desconforto == 'forte' || desconforto == 'moderado') {
        sugestoes.add({
          'id': id(),
          'acao': 'observar',
          'exercicioId': exId,
          'titulo': 'Atenção ao desconforto em $nome',
          'motivo': 'Você registrou desconforto $desconforto na última série. '
              'Se persistir, procure um profissional antes de aumentar carga.',
          'evidencia': evid.sublist(1),
          'confianca': 'media',
        });
        continue;
      }

      final estavelOuSubindo =
          tend['status'] == 'estavel' || tend['status'] == 'subindo';
      if (todasNoTopo && carga != null && carga > 0 && estavelOuSubindo) {
        final incremento = _num(plano?['incrementoMinimoKg']);
        if (rirB == 0) {
          sugestoes.add({
            'id': id(),
            'acao': 'manter',
            'exercicioId': exId,
            'titulo': 'Manter ${fmtNum(carga)} kg em $nome',
            'motivo': 'Você chegou ao topo da faixa, mas a última série foi '
                'até o limite (0 repetições sobrando). Vale repetir antes de subir.',
            'evidencia': evid,
            'confianca': 'media',
          });
        } else if (incremento == null) {
          perguntas.add(
              'Qual é o menor incremento de carga disponível em $nome?');
          sugestoes.add({
            'id': id(),
            'acao': 'manter',
            'exercicioId': exId,
            'titulo': 'Manter ${fmtNum(carga)} kg em $nome por enquanto',
            'motivo': 'Você está no topo da faixa de repetições, mas não sei o '
                'menor incremento disponível. Informe no planejamento do exercício.',
            'evidencia': evid,
            'confianca': 'baixa',
          });
        } else {
          sugestoes.add({
            'id': id(),
            'acao': 'sugerir_carga',
            'exercicioId': exId,
            'titulo': 'Subir para ${fmtNum(carga + incremento)} kg em $nome',
            'motivo': 'Topo da faixa de repetições em todas as séries'
                '${rirB == null ? ' (esforço da última série não informado)' : ''}. '
                'Sugestão para a próxima sessão, no menor incremento informado.',
            'evidencia': evid,
            'confianca': rirB == null ? 'baixa' : 'media',
            'alteracao': {
              'cargaAtualKg': carga,
              'cargaSugeridaKg': carga + incremento,
            },
          });
        }
        continue;
      }

      if (tend['status'] == 'caindo') {
        sugestoes.add({
          'id': id(),
          'acao': 'observar',
          'exercicioId': exId,
          'titulo': 'Repetições caíram em $nome',
          'motivo': '${tend['detalhe']} Uma queda isolada não justifica mudar '
              'a ficha; observe mais uma sessão.',
          'evidencia': evid,
          'confianca': 'baixa',
        });
        continue;
      }

      sugestoes.add({
        'id': id(),
        'acao': 'manter',
        'exercicioId': exId,
        'titulo': 'Manter $nome como está',
        'motivo': 'Ainda não chegou ao topo da faixa em todas as séries. '
            '${tend['detalhe'] ?? ''}',
        'evidencia': evid,
        'confianca': 'media',
      });
    }

    final resumo = sugestoes.isEmpty
        ? 'Não há sessões com séries detalhadas suficientes para sugerir '
            'ajustes. Continue treinando e informe o esforço da última série.'
        : (tipo == 'semana'
            ? 'Análise de demonstração da sua semana, exercício por exercício.'
            : 'Revisão de demonstração do período completo da ficha.');

    return {
      'versao': 1,
      'avaliacaoId': pedido['avaliacaoId'],
      'tipo': tipo,
      'demonstracao': true,
      'resumo': resumo,
      'recomendacao': sugestoes.any((s) => acoesAplicaveis.contains(s['acao']))
          ? 'ajustar'
          : 'manter',
      'sugestoes': sugestoes,
      'perguntas': perguntas.take(5).toList(),
      if (tipo == 'revisao')
        'explicacao': {
          'progressao':
              'Mantenha a carga enquanto houver repetições a ganhar; ao '
                  'completar o topo da faixa com folga, tente mais uma '
                  'repetição e só então use o menor incremento disponível.',
          'encerrarSerie':
              'Encerre a série quando a técnica começar a piorar ou quando '
                  'sobrarem poucas repetições. Não é preciso chegar à falha '
                  'em toda série.',
        },
    };
  }

  static String _repsTexto(Map sessao) {
    final series = (sessao['series'] as List).cast<Map>();
    final reps = series.map((s) => '${s['reps']}').join('/');
    final carga = series.isEmpty ? null : _num(series.last['cargaKg']);
    return '$reps reps${carga == null ? '' : ' com ${fmtNum(carga)} kg'}';
  }

  // ---- Montar ficha (rascunho de demonstração) ----

  static const _catalogo = <Map<String, dynamic>>[
    {'n': 'Supino reto com barra', 'm': 'peito', 'e': 'barras', 'c': true},
    {'n': 'Supino inclinado com halteres', 'm': 'peito', 'e': 'halteres', 'c': true},
    {'n': 'Peck deck', 'm': 'peito', 'e': 'maquinas', 'c': false},
    {'n': 'Flexão de braços', 'm': 'peito', 'e': 'corporal', 'c': true},
    {'n': 'Puxada frente', 'm': 'costas', 'e': 'cabos', 'c': true},
    {'n': 'Remada baixa', 'm': 'costas', 'e': 'cabos', 'c': true},
    {'n': 'Remada curvada', 'm': 'costas', 'e': 'barras', 'c': true},
    {'n': 'Barra fixa', 'm': 'costas', 'e': 'corporal', 'c': true},
    {'n': 'Desenvolvimento com halteres', 'm': 'ombros', 'e': 'halteres', 'c': true},
    {'n': 'Elevação lateral', 'm': 'ombros', 'e': 'halteres', 'c': false},
    {'n': 'Rosca direta', 'm': 'biceps', 'e': 'barras', 'c': false},
    {'n': 'Rosca alternada', 'm': 'biceps', 'e': 'halteres', 'c': false},
    {'n': 'Tríceps corda', 'm': 'triceps', 'e': 'cabos', 'c': false},
    {'n': 'Mergulho no banco', 'm': 'triceps', 'e': 'corporal', 'c': false},
    {'n': 'Agachamento livre', 'm': 'quadriceps', 'e': 'barras', 'c': true},
    {'n': 'Leg press', 'm': 'quadriceps', 'e': 'maquinas', 'c': true},
    {'n': 'Cadeira extensora', 'm': 'quadriceps', 'e': 'maquinas', 'c': false},
    {'n': 'Agachamento com peso do corpo', 'm': 'quadriceps', 'e': 'corporal', 'c': true},
    {'n': 'Mesa flexora', 'm': 'posteriores', 'e': 'maquinas', 'c': false},
    {'n': 'Stiff com halteres', 'm': 'posteriores', 'e': 'halteres', 'c': true},
    {'n': 'Elevação pélvica', 'm': 'gluteos', 'e': 'corporal', 'c': true},
    {'n': 'Panturrilha em pé', 'm': 'panturrilhas', 'e': 'maquinas', 'c': false},
    {'n': 'Panturrilha com peso do corpo', 'm': 'panturrilhas', 'e': 'corporal', 'c': false},
    {'n': 'Abdominal no solo', 'm': 'abdomen', 'e': 'corporal', 'c': false},
  ];

  static const _divisoes = <int, List<List<String>>>{
    1: [['peito', 'costas', 'quadriceps', 'ombros', 'posteriores', 'abdomen']],
    2: [
      ['peito', 'costas', 'quadriceps', 'ombros', 'abdomen'],
      ['costas', 'peito', 'posteriores', 'gluteos', 'biceps', 'triceps'],
    ],
    3: [
      ['peito', 'ombros', 'triceps'],
      ['costas', 'biceps', 'abdomen'],
      ['quadriceps', 'posteriores', 'gluteos', 'panturrilhas'],
    ],
    4: [
      ['peito', 'ombros', 'triceps'],
      ['costas', 'biceps'],
      ['quadriceps', 'posteriores', 'panturrilhas'],
      ['peito', 'costas', 'ombros', 'abdomen'],
    ],
    5: [
      ['peito', 'triceps'],
      ['costas', 'biceps'],
      ['quadriceps', 'gluteos', 'panturrilhas'],
      ['ombros', 'abdomen'],
      ['posteriores', 'gluteos', 'peito', 'costas'],
    ],
  };

  static _J _montar(_J pedido) {
    final r = (pedido['respostas'] as Map?) ?? const {};
    final faltando = (pedido['faltando'] as List?) ?? const [];
    if (faltando.isNotEmpty) {
      throw RespostaInvalida('faltam respostas: ${faltando.join(', ')}.');
    }

    final dias = (_int(r['diasDisponiveis']) ?? 3).clamp(1, 5);
    final minutos = _int(r['minutosPorSessao']) ?? 60;
    final equip = {
      for (final e in (r['equipamentos'] as List)) '$e',
      'corporal',
    };
    final prioritarios = {
      for (final m in (r['musculosPrioritarios'] as List? ?? const [])) '$m',
    };
    final nivel = '${r['experiencia']}';
    final qtdPorFicha = minutos <= 45 ? 4 : (minutos <= 75 ? 5 : 6);
    final seriesBase = nivel == 'Iniciante' ? 2 : 3;

    final divisao = _divisoes[dias]!;
    final fichas = <_J>[];
    final usados = <String>{};

    for (var d = 0; d < divisao.length; d++) {
      final grupos = divisao[d];
      final escolhidos = <Map<String, dynamic>>[];

      // Compostos primeiro, depois isoladores.
      for (final composto in [true, false]) {
        for (final m in grupos) {
          if (escolhidos.length >= qtdPorFicha) break;
          final candidatos = _catalogo.where((x) =>
              x['m'] == m &&
              x['c'] == composto &&
              equip.contains(x['e']) &&
              !escolhidos.contains(x));
          if (candidatos.isEmpty) continue;
          // Prefere equipamento que o usuário marcou (não só peso do corpo).
          final lista = candidatos.toList()
            ..sort((a, b) {
              final pa = a['e'] == 'corporal' ? 1 : 0;
              final pb = b['e'] == 'corporal' ? 1 : 0;
              return pa.compareTo(pb);
            });
          escolhidos.add(lista.first);
        }
      }

      if (escolhidos.isEmpty) continue;
      usados.addAll(escolhidos.map((e) => '${e['m']}'));

      fichas.add({
        'nome': 'Treino ${String.fromCharCode(65 + d)}',
        'exercicios': [
          for (var i = 0; i < escolhidos.length; i++)
            _exercicioRascunho(
              escolhidos[i],
              i,
              prioritarios.contains(escolhidos[i]['m'])
                  ? seriesBase + 1
                  : seriesBase,
            ),
        ],
      });
    }

    if (fichas.isEmpty) {
      throw RespostaInvalida(
          'nenhum exercício combina com os equipamentos informados.');
    }

    return {
      'versao': 1,
      'avaliacaoId': pedido['avaliacaoId'],
      'tipo': 'montar',
      'demonstracao': true,
      'resumo': 'Rascunho de DEMONSTRAÇÃO: ${fichas.length} treino(s) '
          'para $dias dia(s) por semana, montado por regras locais, sem IA. '
          'Revise tudo antes de adicionar.',
      'sugestoes': <_J>[],
      'perguntas': <String>[],
      'explicacao': {
        'volumeEDescanso':
            'Séries distribuídas entre os dias para que cada músculo grande '
                'apareça ao menos uma vez por semana. Descanso maior nos '
                'compostos, menor nos isoladores.',
        'faixaReps':
            'Compostos em 6 a 10 repetições e isoladores em 10 a 15, '
                'terminando as séries com 1 a 3 repetições sobrando.',
        'encerrarSerie':
            'Pare a série quando sobrarem poucas repetições boas ou a técnica '
                'piorar. Falha não é exigida em toda série.',
        'progressao':
            'Mantenha a carga até completar o topo da faixa em todas as '
                'séries; então suba o menor incremento disponível.',
        'forca':
            'Sem trabalho específico de força neste rascunho: o objetivo '
                'informado é hipertrofia.',
      },
      'rascunho': {'fichas': fichas},
    };
  }

  static _J _exercicioRascunho(Map<String, dynamic> x, int posicao, int series) {
    final composto = x['c'] == true;
    return {
      'nome': x['n'],
      'series': series,
      'repsMin': composto ? 6 : 10,
      'repsMax': composto ? 10 : 15,
      'descansoS': composto ? 120 : 60,
      'rirAlvo': composto ? 2 : 1,
      'execucao': composto
          ? 'Controle a descida e mantenha a técnica em todas as repetições.'
          : 'Movimento controlado, sem balançar.',
      'progressao': 'Complete o topo da faixa em todas as séries antes de subir a carga.',
      'musculoPrincipal': x['m'],
      'objetivoSecundario': null,
      'porque': posicao == 0
          ? 'Exercício composto no início, quando há mais energia.'
          : (composto
              ? 'Composto de apoio para o mesmo grupo.'
              : 'Isolador no fim para completar o volume do músculo.'),
    };
  }
}