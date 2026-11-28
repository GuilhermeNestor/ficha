// Verificação do núcleo do Personal IA, sem Flutter.
// Rode na pasta do app:  dart run tool/verificar_ia.dart
import 'dart:convert';

import '../lib/ia_nucleo.dart';

int _falhas = 0;
int _total = 0;

void confere(String nome, bool condicao, [String? detalhe]) {
  _total++;
  if (!condicao) {
    _falhas++;
    print('FALHOU: $nome ${detalhe ?? ''}');
  }
}

void lanca<T extends Object>(String nome, void Function() f) {
  _total++;
  try {
    f();
    _falhas++;
    print('FALHOU: $nome (não lançou erro)');
  } on T {
    // esperado
  } catch (e) {
    _falhas++;
    print('FALHOU: $nome (erro diferente: $e)');
  }
}

Map<String, dynamic> ficha() => {
      'id': 'peito',
      'nome': 'PEITO',
      'exercicios': [
        {'id': 'peito_ex_1', 'nome': 'SUPINO RETO', 'series': 3, 'reps': 10, 'carga': 40, 'descanso': 60},
        {'id': 'peito_ex_2', 'nome': 'TRÍCEPS CORDA', 'series': 3, 'reps': 12, 'carga': 25, 'descanso': 45},
      ],
    };

Map<String, dynamic> serie(String ex, String nome, int n, int reps, num carga) => {
      'exercicioId': ex,
      'exercicioNome': nome,
      'serie': n,
      'meta': 10,
      'repeticoes': reps,
      'carga': carga,
      'fim': 1,
      'motivo': 'pausa',
    };

Map<String, dynamic> resultado(String id, DateTime d, List<List<int>> supino,
    {String nome = 'SUPINO RETO', num carga = 40, bool detalhado = true}) {
  final inicio = d.millisecondsSinceEpoch;
  return {
    'versao': 1,
    'id': id,
    'fichaId': 'peito',
    'fichaNome': 'PEITO',
    'inicio': inicio,
    'fim': inicio + 3000000,
    'duracaoMs': 3000000,
    'seriesConcluidas': 6,
    'exerciciosConcluidos': 2,
    'cargas': [
      {'exercicioId': 'peito_ex_1', 'exercicioNome': nome, 'ultimaCarga': carga},
    ],
    if (detalhado)
      'seriesRealizadas': [
        for (var i = 0; i < supino[0].length; i++)
          serie('peito_ex_1', nome, i + 1, supino[0][i], carga),
      ],
    'estado': 'sincronizado',
  };
}

Map<String, dynamic> pedidoDe(
  List<Map<String, dynamic>> resultados, {
  String tipo = 'semana',
  Map<String, Map<String, dynamic>> planos = const {},
  List<Map<String, dynamic>> esforco = const [],
  DateTime? agora,
}) =>
    ResumoIA.montarPedido(
      avaliacaoId: 'aval_1',
      tipo: tipo,
      agora: agora ?? DateTime(2026, 11, 26, 20),
      ficha: ficha(),
      resultados: resultados,
      esforco: esforco,
      planos: planos,
      musculosConfirmados: const {},
      perfil: {
        'nome': 'SEGREDO',
        'nascimento': 123,
        'observacoes': 'dor no ombro',
        'sexo': 'Masculino',
        'alturaCm': 180,
        'objetivo': 'Hipertrofia',
      },
      idade: 30,
      medidas: [
        {'data': DateTime(2026, 11, 1).millisecondsSinceEpoch, 'pesoKg': 80.0},
      ],
    );

void main() {
  final agora = DateTime(2026, 11, 26, 20);

  // ---------- privacidade ----------
  {
    final p = pedidoDe([]);
    final txt = jsonEncode(p);
    confere('não envia nome', !txt.contains('SEGREDO'));
    confere('não envia nascimento', !txt.contains('"nascimento"'));
    confere('não envia observações de saúde', !txt.contains('dor no ombro'));
    confere('perfil tem idade', (p['perfil'] as Map)['idade'] == 30);
    confere('falta vira desconhecido',
        (p['perfil'] as Map)['pesoMetaKg'] == 'desconhecido');
  }

  // ---------- histórico vazio ----------
  {
    final p = pedidoDe([]);
    confere('vazio: 0 sessões na janela',
        (p['periodo'] as Map)['sessoesNaJanela'] == 0);
    confere('vazio: exercícios sem sessões',
        ((p['exercicios'] as List).first as Map)['sessoes'].isEmpty);
    confere('vazio: volume indisponível',
        (p['volumeSemanalPorMusculo'] as Map)['status'] == 'indisponivel');
  }

  // ---------- sessões: tendência, nome diferente, formato antigo ----------
  final r1 = resultado('r1', agora.subtract(const Duration(days: 6)), [[10, 9, 8]]);
  final r2 = resultado('r2', agora.subtract(const Duration(days: 2)), [[11, 10, 9]]);
  {
    final p = pedidoDe([r1, r2]);
    final ex = (p['exercicios'] as List).first as Map;
    final t = ex['tendencia'] as Map;
    confere('tendência subindo', t['status'] == 'subindo', '$t');
    confere('esforço desconhecido sem RIR', t['esforcoConhecido'] == false);
    confere('origem da contagem desconhecida',
        ex['origemContagem'] == 'desconhecida');
    final s = (ex['sessoes'] as List).last as Map;
    confere('RIR desconhecido', s['rirUltimaSerie'] == 'desconhecido');
  }

  {
    // máquina diferente: mesmo ID, nome diferente -> não mistura
    final rOutro = resultado('r0', agora.subtract(const Duration(days: 4)),
        [[15, 14, 13]], nome: 'SUPINO RETO MAQUINA', carga: 60);
    final p = pedidoDe([rOutro, r2]);
    final ex = (p['exercicios'] as List).first as Map;
    confere('nome diferente é contado à parte',
        ex['sessoesComNomeDiferente'] == 1, '${ex['sessoesComNomeDiferente']}');
    confere('nome diferente não entra nas sessões',
        (ex['sessoes'] as List).length == 1);
  }

  {
    // contagem de origem desconhecida / formato antigo sem séries
    final antigo = resultado('r_antigo', agora.subtract(const Duration(days: 3)),
        [[10]], detalhado: false);
    final p = pedidoDe([antigo]);
    final ex = (p['exercicios'] as List).first as Map;
    final s = (ex['sessoes'] as List).first as Map;
    confere('sem séries detalhadas = desconhecido', s['series'] == 'desconhecido');
    confere('conta sessões sem séries', ex['sessoesSemSeriesDetalhadas'] == 1);
    confere('tendência insuficiente',
        (ex['tendencia'] as Map)['status'] == 'insuficiente');
  }

  {
    // RIR informado entra e torna o esforço conhecido
    final esf = [
      {'resultadoId': 'r1', 'exercicioId': 'peito_ex_1', 'serie': 3, 'resposta': '2', 'desconforto': null},
      {'resultadoId': 'r2', 'exercicioId': 'peito_ex_1', 'serie': 3, 'resposta': '1', 'desconforto': 'leve'},
    ];
    final p = pedidoDe([r1, r2], esforco: esf);
    final ex = (p['exercicios'] as List).first as Map;
    confere('esforço conhecido com RIR nas duas',
        (ex['tendencia'] as Map)['esforcoConhecido'] == true);
    final s = (ex['sessoes'] as List).last as Map;
    confere('RIR da última série', s['rirUltimaSerie'] == '1');
    confere('desconforto separado', s['desconfortoUltimaSerie'] == 'leve');
    // resposta de uma série não vale para as outras
    confere('RIR só na última série',
        !jsonEncode(s['series']).contains('rir'));
  }

  // ---------- volume por músculo ----------
  {
    final p = pedidoDe([r1, r2]);
    final v = p['volumeSemanalPorMusculo'] as Map;
    confere('volume parcial (tríceps corda sem série registrada)',
        v['status'] == 'ok' || v['status'] == 'parcial', '${v['status']}');
    final sem = (v['semanas'] as List).first as Map;
    final peito = (sem['musculos'] as Map)['peito'] as Map;
    confere('peito direto contado', (peito['direto'] as int) >= 3);
    confere('tríceps indireto no supino',
        ((sem['musculos'] as Map)['triceps'] as Map)['indireto'] >= 3);
  }

  {
    final desconhecido = resultado('rx', agora.subtract(const Duration(days: 1)),
        [[10, 10]], nome: 'EXERCICIO MALUCO');
    final p = ResumoIA.montarPedido(
      avaliacaoId: 'a',
      tipo: 'revisao',
      agora: agora,
      ficha: ficha(),
      resultados: [desconhecido],
      esforco: const [],
      planos: const {},
      musculosConfirmados: const {},
      perfil: null,
      idade: null,
      medidas: const [],
    );
    confere('exercício sem mapa: volume indisponível',
        (p['volumeSemanalPorMusculo'] as Map)['status'] == 'indisponivel');
    final p2 = ResumoIA.montarPedido(
      avaliacaoId: 'a',
      tipo: 'revisao',
      agora: agora,
      ficha: ficha(),
      resultados: [desconhecido],
      esforco: const [],
      planos: const {},
      musculosConfirmados: const {'peito_ex_1': 'peito'},
      perfil: null,
      idade: null,
      medidas: const [],
    );
    confere('músculo confirmado no plano vale',
        (p2['volumeSemanalPorMusculo'] as Map)['status'] != 'indisponivel');
  }

  // ---------- provedor simulado + validação ----------
  {
    final p = pedidoDe([r1, r2]);
    final resp = ProvedorSimulado.responder(p);
    confere('simulado marcado como demonstração', resp['demonstracao'] == true);
    final ok = ValidacaoIA.validarResposta(resp, p);
    confere('resposta simulada é válida', ok['sugestoes'] is List);
    confere('toda sugestão não-observar tem evidência',
        (ok['sugestoes'] as List).every((s) =>
            s['acao'] == 'observar' || (s['evidencia'] as List).isNotEmpty));
  }

  {
    // topo da faixa + incremento conhecido -> sugere carga
    final top1 = resultado('t1', agora.subtract(const Duration(days: 5)), [[10, 10, 10]]);
    final top2 = resultado('t2', agora.subtract(const Duration(days: 1)), [[10, 10, 10]]);
    final esf = [
      {'resultadoId': 't2', 'exercicioId': 'peito_ex_1', 'serie': 3, 'resposta': '2', 'desconforto': null},
    ];
    final p = pedidoDe([top1, top2],
        planos: {
          'peito_ex_1': {'repsMin': 8, 'repsMax': 10, 'incrementoMinimoKg': 2.5},
        },
        esforco: esf);
    final resp = ProvedorSimulado.responder(p);
    final ok = ValidacaoIA.validarResposta(resp, p);
    final s = (ok['sugestoes'] as List).first as Map;
    confere('sugere carga no topo da faixa', s['acao'] == 'sugerir_carga', '${s['acao']}');
    confere('carga sugerida = atual + incremento',
        (s['alteracao'] as Map)['cargaSugeridaKg'] == 42.5);
  }

  {
    // topo da faixa, mas sem incremento conhecido -> pergunta e mantém
    final top1 = resultado('t1', agora.subtract(const Duration(days: 5)), [[10, 10, 10]]);
    final top2 = resultado('t2', agora.subtract(const Duration(days: 1)), [[10, 10, 10]]);
    final p = pedidoDe([top1, top2]);
    final resp = ProvedorSimulado.responder(p);
    final s = (resp['sugestoes'] as List).first as Map;
    confere('sem incremento: mantém', s['acao'] == 'manter', '${s['acao']}');
    confere('sem incremento: pergunta', (resp['perguntas'] as List).isNotEmpty);
  }

  {
    // uma sessão ruim isolada não muda nada
    final bom = resultado('b1', agora.subtract(const Duration(days: 5)), [[10, 10, 10]]);
    final ruim = resultado('b2', agora.subtract(const Duration(days: 1)), [[7, 6, 5]]);
    final p = pedidoDe([bom, ruim]);
    final resp = ProvedorSimulado.responder(p);
    confere('sessão ruim isolada: nada aplicável',
        (resp['sugestoes'] as List).every((s) => !acoesAplicaveis.contains(s['acao'])));
  }

  {
    // desconforto forte nunca vira aumento de carga
    final top1 = resultado('d1', agora.subtract(const Duration(days: 5)), [[10, 10, 10]]);
    final top2 = resultado('d2', agora.subtract(const Duration(days: 1)), [[10, 10, 10]]);
    final esf = [
      {'resultadoId': 'd2', 'exercicioId': 'peito_ex_1', 'serie': 3, 'resposta': '3+', 'desconforto': 'forte'},
    ];
    final p = pedidoDe([top1, top2],
        planos: {'peito_ex_1': {'repsMax': 10, 'incrementoMinimoKg': 2.5}},
        esforco: esf);
    final resp = ProvedorSimulado.responder(p);
    confere('desconforto forte: sem aumento',
        (resp['sugestoes'] as List).every((s) => s['acao'] != 'sugerir_carga'));
  }

  // ---------- resposta inválida ----------
  {
    final p = pedidoDe([r1, r2]);
    final base = ProvedorSimulado.responder(p);

    Map<String, dynamic> copia() => jsonDecode(jsonEncode(base)) as Map<String, dynamic>;

    lanca<RespostaInvalida>('não é objeto', () => ValidacaoIA.validarResposta('texto', p));
    lanca<RespostaInvalida>('versão errada', () {
      final r = copia()..['versao'] = 2;
      ValidacaoIA.validarResposta(r, p);
    });
    lanca<RespostaInvalida>('avaliação trocada', () {
      final r = copia()..['avaliacaoId'] = 'outra';
      ValidacaoIA.validarResposta(r, p);
    });
    lanca<RespostaInvalida>('exercício inventado', () {
      final r = copia();
      (r['sugestoes'] as List).first['exercicioId'] = 'nao_existe';
      ValidacaoIA.validarResposta(r, p);
    });
    lanca<RespostaInvalida>('sessão inventada na evidência', () {
      final r = copia();
      final s = (r['sugestoes'] as List).first as Map;
      s['evidencia'] = [
        {'sessaoId': 'fantasma', 'exercicioId': 'peito_ex_1', 'texto': 'x'},
      ];
      ValidacaoIA.validarResposta(r, p);
    });
    lanca<RespostaInvalida>('ação desconhecida', () {
      final r = copia();
      (r['sugestoes'] as List).first['acao'] = 'apagar_tudo';
      ValidacaoIA.validarResposta(r, p);
    });
    lanca<RespostaInvalida>('sugestão sem evidência', () {
      final r = copia();
      final s = (r['sugestoes'] as List).firstWhere((s) => s['acao'] == 'manter') as Map;
      s['evidencia'] = [];
      ValidacaoIA.validarResposta(r, p);
    });
    lanca<RespostaInvalida>('séries que não batem com a ficha', () {
      final r = copia();
      r['sugestoes'] = [
        {
          'id': 'x', 'acao': 'ajustar_series', 'exercicioId': 'peito_ex_1',
          'titulo': 't', 'motivo': 'm', 'confianca': 'alta',
          'evidencia': [{'sessaoId': 'r1', 'exercicioId': 'peito_ex_1', 'texto': 't'}],
          'alteracao': {'de': 5, 'para': 6},
        },
      ];
      ValidacaoIA.validarResposta(r, p);
    });
    lanca<RespostaInvalida>('carga com salto absurdo', () {
      final r = copia();
      r['sugestoes'] = [
        {
          'id': 'x', 'acao': 'sugerir_carga', 'exercicioId': 'peito_ex_1',
          'titulo': 't', 'motivo': 'm', 'confianca': 'alta',
          'evidencia': [{'sessaoId': 'r1', 'exercicioId': 'peito_ex_1', 'texto': 't'}],
          'alteracao': {'cargaAtualKg': 40, 'cargaSugeridaKg': 120},
        },
      ];
      ValidacaoIA.validarResposta(r, p);
    });
    lanca<RespostaInvalida>('rascunho fora do tipo', () {
      final r = copia()..['rascunho'] = {'fichas': []};
      ValidacaoIA.validarResposta(r, p);
    });
    lanca<RespostaInvalida>('texto enorme', () {
      final r = copia()..['resumo'] = 'x' * 5000;
      ValidacaoIA.validarResposta(r, p);
    });
  }

  // ---------- aplicar sugestão ----------
  {
    final f = ficha();
    final sug = {
      'acao': 'ajustar_series',
      'exercicioId': 'peito_ex_1',
      'alteracao': {'de': 3, 'para': 4},
    };
    final ef = calcularEfeito(sug, ficha: f, planoAtual: null);
    final nova = ef.ficha!;
    confere('aplicar séries muda a cópia',
        ((nova['exercicios'] as List).first as Map)['series'] == 4);
    confere('aplicar não altera o original',
        ((f['exercicios'] as List).first as Map)['series'] == 3);

    final editada = ficha();
    ((editada['exercicios'] as List).first as Map)['series'] = 5;
    lanca<ConflitoSugestao>('ficha editada depois da análise',
        () => calcularEfeito(sug, ficha: editada, planoAtual: null));

    lanca<ConflitoSugestao>('ficha apagada',
        () => calcularEfeito(sug, ficha: null, planoAtual: null));

    final carga = {
      'acao': 'sugerir_carga',
      'exercicioId': 'peito_ex_1',
      'alteracao': {'cargaAtualKg': 40.0, 'cargaSugeridaKg': 42.5},
    };
    final ec = calcularEfeito(carga, ficha: f, planoAtual: null);
    confere('carga vira sugestão no plano, não na ficha',
        ec.ficha == null && ec.plano!['cargaSugeridaKg'] == 42.5);
    final mudou = ficha();
    ((mudou['exercicios'] as List).first as Map)['carga'] = 50;
    lanca<ConflitoSugestao>('carga mudou depois da análise',
        () => calcularEfeito(carga, ficha: mudou, planoAtual: null));

    final plano = {
      'acao': 'ajustar_plano',
      'exercicioId': 'peito_ex_1',
      'alteracao': {'campo': 'repsMax', 'de': 10, 'para': 12},
    };
    final ep = calcularEfeito(plano, ficha: f, planoAtual: {'repsMin': 8, 'repsMax': 10});
    confere('ajusta plano', ep.plano!['repsMax'] == 12);
    lanca<ConflitoSugestao>('plano editado depois da análise',
        () => calcularEfeito(plano, ficha: f, planoAtual: {'repsMin': 8, 'repsMax': 11}));
    lanca<ConflitoSugestao>('faixa invertida',
        () => calcularEfeito({
              'acao': 'ajustar_plano',
              'exercicioId': 'peito_ex_1',
              'alteracao': {'campo': 'repsMax', 'de': 10, 'para': 6},
            }, ficha: f, planoAtual: {'repsMin': 8, 'repsMax': 10}));
    lanca<ConflitoSugestao>('manter não é aplicável',
        () => calcularEfeito({'acao': 'manter', 'exercicioId': 'peito_ex_1'},
            ficha: f, planoAtual: null));
  }

  // ---------- montar ficha ----------
  {
    final respostas = {
      'objetivo': 'Hipertrofia',
      'experiencia': 'Intermediário',
      'diasDisponiveis': 3,
      'minutosPorSessao': 60,
      'equipamentos': ['maquinas', 'halteres', 'cabos'],
      'musculosPrioritarios': ['costas'],
    };
    final p = ResumoIA.montarPedido(
      avaliacaoId: 'm1',
      tipo: 'montar',
      agora: agora,
      ficha: null,
      resultados: const [],
      esforco: const [],
      planos: const {},
      musculosConfirmados: const {},
      perfil: null,
      idade: null,
      medidas: const [],
      respostasMontagem: respostas,
    );
    confere('montar: nada faltando', (p['faltando'] as List).isEmpty);
    final resp = ProvedorSimulado.responder(p);
    final ok = ValidacaoIA.validarResposta(resp, p);
    final fichas = (ok['rascunho'] as Map)['fichas'] as List;
    confere('montar: 3 fichas para 3 dias', fichas.length == 3, '${fichas.length}');
    confere('montar: sem barras usa só equipamento informado',
        !jsonEncode(fichas).contains('com barra'));

    final faltando = ResumoIA.montarPedido(
      avaliacaoId: 'm2', tipo: 'montar', agora: agora, ficha: null,
      resultados: const [], esforco: const [], planos: const {},
      musculosConfirmados: const {}, perfil: null, idade: null,
      medidas: const [], respostasMontagem: {'objetivo': 'Força'},
    );
    confere('montar: lista o que falta',
        (faltando['faltando'] as List).contains('diasDisponiveis'));
    lanca<RespostaInvalida>('montar sem respostas não gera',
        () => ProvedorSimulado.responder(faltando));
  }

  print('$_total verificações, $_falhas falha(s).');
  if (_falhas > 0) throw StateError('Há falhas.');
}