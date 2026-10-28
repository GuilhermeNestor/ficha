import 'package:flutter/material.dart';

import 'banco.dart';
import 'ponte.dart';
import 'tela_gravacoes.dart';

const verde = Color(0xFFB6FF00);
const fundo = Color(0xFF090B09);
const superficie = Color(0xFF191C18);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

String mensagemErro(Object erro) {
  return erro.toString().replaceFirst('Exception: ', '');
}

String numero(num valor) {
  if (valor == valor.roundToDouble()) {
    return valor.toInt().toString();
  }

  return valor.toString().replaceAll('.', ',');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final cores = ColorScheme.fromSeed(
      seedColor: verde,
      brightness: Brightness.dark,
    ).copyWith(primary: verde, onPrimary: Colors.black, surface: superficie);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ficha de Treino',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: cores,
        scaffoldBackgroundColor: fundo,
        appBarTheme: const AppBarTheme(
          backgroundColor: fundo,
          foregroundColor: Colors.white,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF22261F),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: superficie,
          indicatorColor: Color(0xFF35451A),
        ),
      ),
      home: const TelaInicial(),
    );
  }
}

class TelaInicial extends StatefulWidget {
  const TelaInicial({super.key});

  @override
  State<TelaInicial> createState() => _TelaInicialState();
}

class _TelaInicialState extends State<TelaInicial> with WidgetsBindingObserver {
  int _recebidos = 0;
  int _consulta = 0;
  int _aba = 0;
  bool _carregando = true;
  String? _erro;

  List<Json> _fichas = [];
  List<Json> _resultados = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Ponte.instancia.addListener(_atualizarPonte);
    _recebidos = Ponte.instancia.resultadosRecebidos;
    _carregar();
    _iniciarPonte();
  }

  Future<void> _iniciarPonte() async {
    try {
      await Ponte.instancia.iniciar();
    } catch (_) {
      // A ponte já expõe o erro no cartão de sincronização.
    }
  }

  void _atualizarPonte() {
    if (!mounted) return;
    if (_recebidos != Ponte.instancia.resultadosRecebidos) {
      _recebidos = Ponte.instancia.resultadosRecebidos;
      _carregar();
    } else {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _iniciarPonte();
      _carregar();
    }
  }

  @override
  void dispose() {
    Ponte.instancia.removeListener(_atualizarPonte);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _carregar() async {
    final consulta = ++_consulta;
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final fichas = await Banco.instancia.listarFichas();
      final resultados = await Banco.instancia.listarResultados();

      if (!mounted || consulta != _consulta) return;

      setState(() {
        _fichas = fichas;
        _resultados = resultados;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted || consulta != _consulta) return;

      setState(() {
        _erro = mensagemErro(e);
        _carregando = false;
      });
    }
  }

  Future<void> _editar([Json? ficha]) async {
    final alterou = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => TelaEditor(ficha: ficha)));

    if (alterou == true && mounted) {
      await _carregar();
    }
  }

  Future<void> _excluir(Json ficha) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir ficha?'),
        content: Text(
          'Excluir "${ficha['nome']}" do celular?\n\n'
          'O histórico será mantido. A exclusão será enviada '
          'na próxima sincronização. Mantenha ao menos uma ficha.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    setState(() => _carregando = true);

    try {
      await Banco.instancia.excluirFicha(ficha['id'] as String);

      if (!mounted) return;
      await _carregar();
    } catch (e) {
      if (!mounted) return;

      setState(() => _carregando = false);

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensagemErro(e))));
    }
  }

  Future<void> _sincronizar() async {
    await _iniciarPonte();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sincronização'),
        content: Text(
          Ponte.instancia.ativa
              ? 'Mantenha este app aberto no celular e o relógio conectado '
                    'ao Zepp. No relógio, toque em SINCRONIZAR.\n\n'
                    'O resultado será salvo no histórico antes da confirmação. '
                    'Depois, as fichas do celular serão enviadas ao relógio.'
              : Ponte.instancia.status,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_aba == 0 ? 'Ficha de Treino' : 'Histórico'),
        actions: [
          IconButton(
            tooltip: 'Gravações de teste',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const TelaGravacoes())),
            icon: const Icon(Icons.sensors),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: _conteudo()),
      floatingActionButton: _aba == 0 && !_carregando && _erro == null
          ? FloatingActionButton.extended(
              onPressed: () => _editar(),
              icon: const Icon(Icons.add),
              label: const Text('Nova ficha'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _aba,
        onDestinationSelected: (valor) {
          setState(() => _aba = valor);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.fitness_center),
            label: 'Fichas',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'Histórico'),
        ],
      ),
    );
  }

  Widget _conteudo() {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 16),
              Text(_erro!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _carregar,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    return _aba == 0 ? _listaFichas() : _historico();
  }

  Widget _listaFichas() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        Card(
          color: superficie,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.watch_outlined, color: verde),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Amazfit Balance',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  Ponte.instancia.status,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _sincronizar,
                    icon: const Icon(Icons.sync),
                    label: const Text('Sincronizar'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 24, 4, 12),
          child: Text(
            'Minhas fichas',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
          ),
        ),
        if (_fichas.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Nenhuma ficha criada.\nToque em “Nova ficha” para começar.',
              textAlign: TextAlign.center,
            ),
          ),
        ..._fichas.map((ficha) {
          final exercicios = ficha['exercicios'] as List;

          final series = exercicios.fold<int>(
            0,
            (total, e) => total + (e['series'] as num).toInt(),
          );

          return Card(
            color: superficie,
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              leading: const Icon(Icons.fitness_center, color: verde),
              title: Text(
                ficha['nome'] as String,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${exercicios.length} exercícios • $series séries',
              ),
              onTap: () => _editar(ficha),
              trailing: PopupMenuButton<String>(
                onSelected: (opcao) {
                  if (opcao == 'editar') {
                    _editar(ficha);
                  } else {
                    _excluir(ficha);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'editar', child: Text('Editar')),
                  PopupMenuItem(value: 'excluir', child: Text('Excluir')),
                ],
              ),
            ),
          );
        }),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'As alterações são salvas neste celular.',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      ],
    );
  }

  Widget _historico() {
    if (_resultados.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history, size: 64, color: verde),
              SizedBox(height: 20),
              Text(
                'Seu histórico começa aqui',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12),
              Text(
                'Abra este app e toque em SINCRONIZAR no relógio '
                'para receber seus treinos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _resultados.length,
      itemBuilder: (context, indice) {
        final r = _resultados[indice];
        final data = DateTime.fromMillisecondsSinceEpoch(
          (r['inicio'] as num).toInt(),
        );

        String dois(int n) => n.toString().padLeft(2, '0');

        final dataTexto = '${dois(data.day)}/${dois(data.month)}/${data.year}';

        final minutos = ((r['duracaoMs'] as num) / 60000).round();
        final cargas = r['cargas'] as List;

        return Card(
          color: superficie,
          child: ExpansionTile(
            leading: const Icon(Icons.check_circle, color: verde),
            title: Text(r['fichaNome'] as String),
            subtitle: Text('$dataTexto • $minutos min'),
            children: [
              ListTile(
                title: Text(
                  '${r['seriesConcluidas']} séries • '
                  '${r['exerciciosConcluidos']} exercícios',
                ),
                subtitle: const Text('Últimas cargas registradas'),
              ),
              ...cargas.map(
                (c) => ListTile(
                  title: Text(c['exercicioNome'] as String),
                  trailing: Text(
                    c['ultimaCarga'] == null
                        ? '—'
                        : '${numero(c['ultimaCarga'] as num)} kg',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class CamposExercicio {
  CamposExercicio(Json? dados)
    : id = dados?['id'] as String? ?? novoId('ex'),
      nome = TextEditingController(text: dados?['nome'] as String? ?? ''),
      series = TextEditingController(text: '${dados?['series'] ?? 3}'),
      reps = TextEditingController(text: '${dados?['reps'] ?? 10}'),
      carga = TextEditingController(
        text: '${dados?['carga'] ?? 0}'.replaceAll('.', ','),
      ),
      descanso = TextEditingController(text: '${dados?['descanso'] ?? 60}');

  final String id;
  final TextEditingController nome;
  final TextEditingController series;
  final TextEditingController reps;
  final TextEditingController carga;
  final TextEditingController descanso;

  Json toJson() {
    return {
      'id': id,
      'nome': nome.text.trim(),
      'series': int.parse(series.text.trim()),
      'reps': int.parse(reps.text.trim()),
      'carga': double.parse(carga.text.trim().replaceAll(',', '.')),
      'descanso': int.parse(descanso.text.trim()),
    };
  }

  void dispose() {
    nome.dispose();
    series.dispose();
    reps.dispose();
    carga.dispose();
    descanso.dispose();
  }
}

class TelaEditor extends StatefulWidget {
  const TelaEditor({super.key, this.ficha});

  final Json? ficha;

  @override
  State<TelaEditor> createState() => _TelaEditorState();
}

class _TelaEditorState extends State<TelaEditor> {
  final _form = GlobalKey<FormState>();
  final _exercicios = <CamposExercicio>[];

  // Mantém os controladores removidos vivos até a tela ser descartada.
  final _removidos = <CamposExercicio>[];

  late final TextEditingController _nome;
  late final String _id;

  bool _salvando = false;

  @override
  void initState() {
    super.initState();

    _id = widget.ficha?['id'] as String? ?? novoId('ficha');

    _nome = TextEditingController(text: widget.ficha?['nome'] as String? ?? '');

    final dados = widget.ficha?['exercicios'] as List?;

    if (dados == null || dados.isEmpty) {
      _exercicios.add(CamposExercicio(null));
    } else {
      for (final e in dados) {
        _exercicios.add(CamposExercicio(Json.from(e as Map)));
      }
    }
  }

  @override
  void dispose() {
    _nome.dispose();

    for (final e in [..._exercicios, ..._removidos]) {
      e.dispose();
    }

    super.dispose();
  }

  Future<void> _salvar() async {
    if (_salvando || !_form.currentState!.validate()) return;

    setState(() => _salvando = true);

    try {
      await Banco.instancia.salvarFicha({
        'id': _id,
        'nome': _nome.text.trim(),
        'exercicios': _exercicios.map((e) => e.toJson()).toList(),
      });

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() => _salvando = false);

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensagemErro(e))));
    }
  }

  String? _validarNome(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Informe o nome';
    }

    return null;
  }

  Widget _campoNumero(
    TextEditingController controlador,
    String rotulo,
    num minimo,
    num maximo, {
    bool decimal = false,
  }) {
    return TextFormField(
      controller: controlador,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      decoration: InputDecoration(labelText: rotulo),
      validator: (valor) {
        final texto = (valor ?? '').trim().replaceAll(',', '.');

        final num? n = decimal ? double.tryParse(texto) : int.tryParse(texto);

        if (n == null || !n.isFinite || n < minimo || n > maximo) {
          return '$minimo a $maximo';
        }

        return null;
      },
    );
  }

  void _mover(int indice, int destino) {
    setState(() {
      final item = _exercicios.removeAt(indice);
      _exercicios.insert(destino, item);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_salvando,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.ficha == null ? 'Nova ficha' : 'Editar ficha'),
        ),
        body: SafeArea(
          child: AbsorbPointer(
            absorbing: _salvando,
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _nome,
                    maxLength: 100,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Nome da ficha',
                      hintText: 'Ex.: Peito e tríceps',
                    ),
                    validator: _validarNome,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Exercícios',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(_exercicios.length, (i) {
                    final e = _exercicios[i];

                    return Card(
                      key: ValueKey(e.id),
                      color: superficie,
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Exercício ${i + 1}',
                                    style: const TextStyle(
                                      color: verde,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Mover para cima',
                                  onPressed: i == 0
                                      ? null
                                      : () => _mover(i, i - 1),
                                  icon: const Icon(Icons.arrow_upward),
                                ),
                                IconButton(
                                  tooltip: 'Mover para baixo',
                                  onPressed: i == _exercicios.length - 1
                                      ? null
                                      : () => _mover(i, i + 1),
                                  icon: const Icon(Icons.arrow_downward),
                                ),
                                IconButton(
                                  tooltip: 'Remover exercício',
                                  onPressed: _exercicios.length == 1
                                      ? null
                                      : () {
                                          setState(() {
                                            _removidos.add(
                                              _exercicios.removeAt(i),
                                            );
                                          });
                                        },
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                            TextFormField(
                              controller: e.nome,
                              maxLength: 100,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                labelText: 'Nome do exercício',
                              ),
                              validator: _validarNome,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _campoNumero(
                                    e.series,
                                    'Séries',
                                    1,
                                    50,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _campoNumero(
                                    e.reps,
                                    'Repetições',
                                    1,
                                    200,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _campoNumero(
                                    e.carga,
                                    'Carga (kg)',
                                    0,
                                    500,
                                    decimal: true,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _campoNumero(
                                    e.descanso,
                                    'Descanso (s)',
                                    5,
                                    3600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  OutlinedButton.icon(
                    onPressed: _exercicios.length >= 40
                        ? null
                        : () {
                            setState(() {
                              _exercicios.add(CamposExercicio(null));
                            });
                          },
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar exercício'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _salvando ? null : _salvar,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_salvando ? 'Salvando...' : 'Salvar ficha'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Salvar atualiza a ficha neste celular. '
                    'Sincronize no relógio para receber as alterações.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
