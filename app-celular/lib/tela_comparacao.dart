import 'package:flutter/material.dart';
import 'banco.dart';
import 'gravacoes.dart';
import 'ponte.dart';

const _nomes = {
  'picos': 'Picos',
  'adaptativo': 'Adaptativo',
  'vetorial+molde': 'Vetorial + molde',
  'vetorial': 'Vetorial',
  'livre': 'Livre',
};

const _cores = {
  'picos': Colors.lightBlueAccent,
  'adaptativo': Colors.orangeAccent,
  'vetorial+molde': Colors.purpleAccent,
};

Map<String, dynamic> _mapa(dynamic valor) => valor is Map
    ? Map<String, dynamic>.from(valor)
    : <String, dynamic>{};

int? _inteiro(dynamic valor) {
  if (valor is! num ||
      !valor.isFinite ||
      valor < 0 ||
      valor != valor.roundToDouble()) {
    return null;
  }

  return valor.toInt();
}

int? _reais(Json g) {
  final rotulos = _mapa(g['rotulos']);

  return _inteiro(
    rotulos.containsKey('repsReais')
        ? rotulos['repsReais']
        : g['repsReais'],
  );
}

int? _contagem(Json g, String detector, String campo) =>
    _inteiro(
      _mapa(_mapa(g['repsPorDetector'])[detector])[campo],
    );

bool _valida(Json g) =>
    _reais(g) != null &&
    g['truncada'] != true &&
    g['interrompida'] != true;

String _sessao(Json g) {
  final id = g['sessaoId'];

  return id is String && id.isNotEmpty
      ? id
      : 'sem-sessao:${g['id']}';
}

String _exercicio(Json g) =>
    (g['exercicioId'] ?? g['exercicioNome'] ?? g['id'])
        .toString();

String _data(Json g) {
  final inicio = _inteiro(g['inicio']);

  if (inicio == null) return 'Data indisponível';

  final d = DateTime.fromMillisecondsSinceEpoch(inicio);
  String dois(int n) => n.toString().padLeft(2, '0');

  return '${dois(d.day)}/${dois(d.month)}/${d.year} '
      '${dois(d.hour)}:${dois(d.minute)}';
}

List<String> _detectores(List<Json> lista) {
  final nomes = <String>{
    'picos',
    'adaptativo',
    'vetorial+molde',
  };

  for (final g in lista) {
    nomes.addAll(_mapa(g['repsPorDetector']).keys);
  }

  return nomes.toList();
}

Map<String, List<Json>> _agrupar(
  List<Json> lista,
  String Function(Json) chave,
) {
  final grupos = <String, List<Json>>{};

  for (final g in lista) {
    (grupos[chave(g)] ??= <Json>[]).add(g);
  }

  return grupos;
}

class TelaComparacao extends StatefulWidget {
  const TelaComparacao({super.key});

  @override
  State<TelaComparacao> createState() =>
      _TelaComparacaoState();
}

class _TelaComparacaoState extends State<TelaComparacao> {
  List<Json> _lista = [];
  String? _treino;
  String? _ex;
  String? _erro;
  bool _carregando = true;
  int _consulta = 0;

  @override
  void initState() {
    super.initState();
    Ponte.instancia.addListener(_carregar);
    _carregar();
  }

  @override
  void dispose() {
    Ponte.instancia.removeListener(_carregar);
    super.dispose();
  }

  Future<void> _carregar() async {
    final consulta = ++_consulta;

    try {
      final lista = await Gravacoes.instancia.listar();

      lista.sort(
        (a, b) => (_inteiro(b['inicio']) ?? 0)
            .compareTo(_inteiro(a['inicio']) ?? 0),
      );

      if (!mounted || consulta != _consulta) return;

      setState(() {
        _lista = lista;
        _erro = null;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted || consulta != _consulta) return;

      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  void _voltar() {
    if (_ex != null) {
      setState(() => _ex = null);
    } else if (_treino != null) {
      setState(() => _treino = null);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: _treino == null,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _voltar();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _voltar,
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Voltar',
        ),
        title: Text(
          _treino == null
              ? 'Comparação por treino'
              : _ex == null
                  ? 'Exercícios do treino'
                  : 'Comparação das séries',
        ),
        actions: [
          IconButton(
            onPressed: _carregar,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _conteudo(),
    ),
  );

  Widget _conteudo() {
    final selecionadas = _lista.where((g) {
      return (_treino == null || _sessao(g) == _treino) &&
          (_ex == null || _exercicio(g) == _ex);
    }).toList();

    final grupos = _treino == null
        ? _agrupar(selecionadas, _sessao)
        : _agrupar(selecionadas, _exercicio);

    final entradas = grupos.entries.toList();

    if (_ex != null) {
      selecionadas.sort((a, b) {
        final ordem = (_inteiro(a['serie']) ?? 0)
            .compareTo(_inteiro(b['serie']) ?? 0);

        return ordem != 0
            ? ordem
            : (_inteiro(a['inicio']) ?? 0)
                .compareTo(_inteiro(b['inicio']) ?? 0);
      });
    }

    final quantidade = _ex == null
        ? entradas.length
        : selecionadas.length;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: quantidade + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_erro != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Não foi possível atualizar: $_erro',
                  ),
                ),
              const Text(
                'Compare a contagem até o fim manual da série. '
                'Acertar o total não garante que cada repetição '
                'foi reconhecida corretamente.',
              ),
              const SizedBox(height: 12),
              if (_treino != null &&
                  selecionadas.isNotEmpty) ...[
                Text(
                  '${selecionadas.first['fichaNome'] ?? 'Treino'}'
                  '${_ex == null ? '' : ' · ${selecionadas.first['exercicioNome']}'}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                _Resumo(lista: selecionadas),
              ],
              if (selecionadas.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'Nenhuma gravação neste nível. '
                    'Sincronize pelo relógio.',
                  ),
                ),
            ],
          );
        }

        if (_ex != null) {
          return _CartaoSerie(g: selecionadas[index - 1]);
        }

        final grupo = entradas[index - 1];
        final registros = grupo.value;

        // A lista original está ordenada da mais recente
        // para a mais antiga.
        final primeiro = registros.last;
        final validos = registros.where(_valida).length;

        final titulo = _treino == null
            ? '${primeiro['fichaNome'] ?? 'Treino'}'
                ' · ${_data(primeiro)}'
            : '${primeiro['exercicioNome'] ?? 'Exercício'}';

        return Card(
          child: ListTile(
            isThreeLine: true,
            leading: Icon(
              _treino == null
                  ? Icons.fitness_center
                  : Icons.bar_chart,
            ),
            title: Text(titulo),
            subtitle: Text(
              '${registros.length} séries gravadas'
              ' · $validos com gabarito válido\n'
              '${_treino == null ? 'Abrir exercícios' : 'Abrir comparação e séries'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() {
              if (_treino == null) {
                _treino = grupo.key;
              } else {
                _ex = grupo.key;
              }
            }),
          ),
        );
      },
    );
  }
}

class _Resumo extends StatelessWidget {
  const _Resumo({required this.lista});

  final List<Json> lista;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumo das gravações',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Erro médio = média da diferença absoluta por série. '
            'Erros a mais e a menos não se cancelam.',
          ),
          const SizedBox(height: 12),
          for (final nome in _detectores(lista))
            _linha(context, nome),
          const SizedBox(height: 8),
          const Text(
            'Ficam fora do resumo: gravações parciais, '
            'interrompidas, sem reps reais ou sem contagem '
            'do detector. Cada registro conta uma vez.',
          ),
        ],
      ),
    ),
  );

  Widget _linha(BuildContext context, String nome) {
    final validas = lista.where((g) {
      return _valida(g) &&
          _contagem(g, nome, 'serie') != null;
    }).toList();

    var exatas = 0;
    var erro = 0;
    var apos = 0;
    var comApos = 0;

    for (final g in validas) {
      final diferenca =
          _contagem(g, nome, 'serie')! - _reais(g)!;

      erro += diferenca.abs();

      if (diferenca == 0) exatas++;

      final extra = _contagem(g, nome, 'apos');

      if (extra != null) {
        apos += extra;
        comApos++;
      }
    }

    final media = validas.isEmpty
        ? '—'
        : (erro / validas.length)
            .toStringAsFixed(2)
            .replaceAll('.', ',');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _nomes[nome] ?? nome,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _cores[nome] ?? Colors.tealAccent,
            ),
          ),
          Text(
            validas.isEmpty
                ? 'Sem comparação válida'
                : '$exatas/${validas.length} totais exatos'
                    ' · erro médio: $media reps',
          ),
          if (comApos > 0)
            Text(
              'Após o fim: $apos contagens em $comApos registros',
            ),
        ],
      ),
    );
  }
}

class _CartaoSerie extends StatelessWidget {
  const _CartaoSerie({required this.g});

  final Json g;

  @override
  Widget build(BuildContext context) {
    final reais = _reais(g);
    final nomes = _detectores([g]);

    double escala = 1;

    for (final valor in [
      reais,
      ...nomes.map((n) => _contagem(g, n, 'serie')),
    ]) {
      if (valor != null && valor > escala) {
        escala = valor.toDouble();
      }
    }

    final motivos = <String>[
      if (g['truncada'] == true) 'Gravação parcial',
      if (g['interrompida'] == true) 'Gravação interrompida',
      if (reais == null) 'Sem repetições reais informadas',
    ];

    final observacao =
        (_mapa(g['rotulos'])['observacao'] ?? '').toString();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Série ${g['serie'] ?? '?'}'
              ' · ${g['carga'] ?? '?'} kg',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(_data(g)),
            const SizedBox(height: 8),
            Text(
              'Repetições reais: ${reais ?? 'não informadas'}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (motivos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${motivos.join(' · ')}. Fora do resumo.',
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            for (final nome in nomes)
              _barra(nome, reais, escala),
            if (reais != null)
              const Text(
                'A marca branca nas barras indica o total real.',
              ),
            if (_mapa(g['repsPorDetector']).isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Este registro antigo não tem contagens '
                  'separadas por detector.',
                ),
              ),
            if (observacao.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Observação: $observacao'),
              ),
            const SizedBox(height: 12),
            const Text(
              'Para corrigir as reps reais ou as observações, '
              'volte à lista de gravações e toque no registro.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _barra(String nome, int? reais, double escala) {
    final contou = _contagem(g, nome, 'serie');
    final apos = _contagem(g, nome, 'apos');

    final diferenca = contou != null && reais != null
        ? contou - reais
        : null;

    final status = diferenca == null
        ? 'Sem comparação'
        : diferenca == 0
            ? 'Acertou o total'
            : diferenca > 0
                ? '$diferenca a mais'
                : '${-diferenca} a menos';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_nomes[nome] ?? nome}: '
            '${contou ?? 'sem dados'} · $status',
          ),
          const SizedBox(height: 6),
          if (contou != null)
            LayoutBuilder(
              builder: (context, constraints) {
                return SizedBox(
                  height: 20,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.center,
                          child: LinearProgressIndicator(
                            value: contou / escala,
                            minHeight: 12,
                            color:
                                _cores[nome] ?? Colors.tealAccent,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                      ),
                      if (reais != null)
                        Positioned(
                          left: (
                            (constraints.maxWidth - 2) *
                            reais /
                            escala
                          ).clamp(
                            0.0,
                            constraints.maxWidth - 2,
                          ).toDouble(),
                          top: 0,
                          bottom: 0,
                          width: 2,
                          child: const ColoredBox(
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          Text('Após o fim manual: ${apos ?? 'sem dados'}'),
        ],
      ),
    );
  }
}