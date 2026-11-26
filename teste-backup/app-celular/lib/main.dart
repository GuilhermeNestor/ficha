import 'package:flutter/material.dart';

import 'banco.dart';
import 'medidas.dart';
import 'perfil.dart';
import 'ponte.dart';
import 'visual.dart';

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
    ).copyWith(
      primary: verde,
      onPrimary: Colors.black,
      surface: superficie,
    );

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
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF22261F),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: Colors.white12,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: verde),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 17,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            side: const BorderSide(color: Colors.white24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: superficie,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white10),
          ),
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

class _TelaInicialState extends State<TelaInicial>
    with WidgetsBindingObserver {
  int _recebidos = 0;
  int _consulta = 0;
  int _aba = 0;
  int _periodo = 0;

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
      // A ponte já expõe o erro de sincronização.
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
    final alterou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TelaEditor(ficha: ficha),
      ),
    );

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
      await Banco.instancia.excluirFicha(
        ficha['id'] as String,
      );

      if (!mounted) return;

      await _carregar();
    } catch (e) {
      if (!mounted) return;

      setState(() => _carregando = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensagemErro(e))),
      );
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
        title: Text(
          _aba == 0
              ? 'Ficha de Treino'
              : _aba == 1
                  ? 'Histórico'
                  : _aba == 2
                      ? 'Medidas'
                      : 'Perfil',
        ),
        actions: [
          if (_aba < 2)
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _carregando ? null : _carregar,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: SafeArea(child: _conteudo()),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _aba,
        onDestinationSelected: (valor) {
          setState(() => _aba = valor);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(
              Icons.fitness_center,
              color: verde,
            ),
            label: 'Fichas',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history, color: verde),
            label: 'Histórico',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_weight_outlined),
            selectedIcon: Icon(
              Icons.monitor_weight,
              color: verde,
            ),
            label: 'Medidas',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: verde),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  Widget _conteudo() {
    if (_aba == 2) return const TelaMedidas();
    if (_aba == 3) return const TelaPerfil();

    if (_carregando) {
      return const Center(
        child: CircularProgressIndicator(),
      );
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
              Text(
                _erro!,
                textAlign: TextAlign.center,
              ),
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

  // ==========================================================
  // TELA INICIAL
  // ==========================================================

  Widget _listaFichas() {
    final ponte = Ponte.instancia;

    final totalExercicios = _fichas.fold<int>(
      0,
      (n, f) => n + (f['exercicios'] as List).length,
    );

    final totalSeries = _fichas.fold<int>(
      0,
      (n, f) => n + (f['exercicios'] as List).fold<int>(
        0,
        (s, e) => s + (e['series'] as num).toInt(),
      ),
    );

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          CartaoVisual(
            destaque: true,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const IconeVisual(
                      Icons.watch_outlined,
                      tamanho: 54,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          rotuloVisual(
                            context,
                            'Sincronização',
                            destaque: true,
                          ),
                          const Text(
                            'Amazfit Balance',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      ponte.ativa
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                      size: 17,
                      color: ponte.ativa
                          ? verde
                          : Colors.white54,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ponte.ativa
                            ? 'Celular pronto para sincronizar'
                            : 'Sincronização indisponível',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  ponte.status,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
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

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: MetricaVisual(
                  'Fichas',
                  '${_fichas.length}',
                  Icons.fitness_center,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricaVisual(
                  'Exercícios',
                  '$totalExercicios',
                  Icons.format_list_bulleted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricaVisual(
                  'Séries',
                  '$totalSeries',
                  Icons.layers_outlined,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          tituloVisual(
            context,
            'Minhas fichas',
            acao: TextButton.icon(
              onPressed: () => _editar(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nova ficha'),
            ),
          ),

          if (_fichas.isEmpty)
            const CartaoVisual(
              child: Text(
                'Crie sua primeira ficha para começar.',
                style: TextStyle(color: Colors.white70),
              ),
            ),

          for (var i = 0; i < _fichas.length; i++) ...[
            _cartaoFicha(_fichas[i], i),
            const SizedBox(height: 10),
          ],

          const SizedBox(height: 8),

          const Text(
            'As fichas são salvas no celular. '
            'Sincronize para enviá-las ao relógio.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartaoFicha(Json ficha, int indice) {
    final exercicios = ficha['exercicios'] as List;

    final series = exercicios.fold<int>(
      0,
      (n, e) => n + (e['series'] as num).toInt(),
    );

    return CartaoVisual(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _editar(ficha),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const IconeVisual(Icons.fitness_center),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          rotuloVisual(
                            context,
                            'Ficha ${(indice + 1).toString().padLeft(2, '0')}',
                          ),
                          const SizedBox(height: 4),
                          Text(
                            ficha['nome'] as String,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Opções da ficha',
                      onSelected: (v) {
                        if (v == 'editar') {
                          _editar(ficha);
                        } else if (v == 'excluir') {
                          _excluir(ficha);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'editar',
                          child: Text('Editar'),
                        ),
                        PopupMenuItem(
                          value: 'excluir',
                          child: Text('Excluir'),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Text(
                  '${exercicios.length} exercícios  ·  $series séries',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),

                if (exercicios.isNotEmpty) ...[
                  const Divider(
                    height: 22,
                    color: Colors.white12,
                  ),
                  for (final e in exercicios.take(2))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              e['nome'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${e['series']} × ${e['reps']}',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (exercicios.length > 2)
                    Text(
                      '+ ${exercicios.length - 2} exercícios',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // HISTÓRICO
  // ==========================================================

  String _duracao(num ms) {
    final min = (ms / 60000).round();

    if (min < 60) return '$min min';

    return '${min ~/ 60}h '
        '${(min % 60).toString().padLeft(2, '0')}m';
  }

  Widget _historico() {
    final agora = DateTime.now();

    final hoje = DateTime(
      agora.year,
      agora.month,
      agora.day,
    );

    final limite = DateTime(
      hoje.year,
      hoje.month,
      hoje.day - _periodo + 1,
    );

    final amanha = DateTime(
      hoje.year,
      hoje.month,
      hoje.day + 1,
    );

    final lista = _resultados.where((r) {
      if (_periodo == 0) return true;

      final inicio = DateTime.fromMillisecondsSinceEpoch(
        (r['inicio'] as num).toInt(),
      );

      return !inicio.isBefore(limite) &&
          inicio.isBefore(amanha);
    }).toList();

    final duracao = lista.fold<int>(
      0,
      (n, r) => n + (r['duracaoMs'] as num).toInt(),
    );

    final series = lista.fold<int>(
      0,
      (n, r) => n + (r['seriesConcluidas'] as num).toInt(),
    );

    const meses = [
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];

    final grupos = <String, List<Json>>{};

    for (final r in lista) {
      final d = DateTime.fromMillisecondsSinceEpoch(
        (r['inicio'] as num).toInt(),
      );

      final chave = '${meses[d.month - 1]} ${d.year}';

      (grupos[chave] ??= []).add(r);
    }

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          CartaoVisual(
            destaque: true,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                rotuloVisual(
                  context,
                  'Resumo do período',
                  destaque: true,
                ),

                const SizedBox(height: 10),

                Text(
                  '${lista.length}',
                  style: Theme.of(context)
                      .textTheme
                      .displayMedium
                      ?.copyWith(
                        fontWeight: FontWeight.bold,
                        height: 1,
                      ),
                ),

                const SizedBox(height: 6),

                const Text(
                  'Treinos registrados',
                  style: TextStyle(color: Colors.white70),
                ),

                const SizedBox(height: 18),

                Row(
                  children: [
                    Expanded(
                      child: MetricaVisual(
                        'Tempo total',
                        _duracao(duracao),
                        Icons.timer_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MetricaVisual(
                        'Séries concluídas',
                        '$series',
                        Icons.layers_outlined,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final e in const {
                0: 'Todos',
                7: '7 dias',
                30: '30 dias',
              }.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _periodo == e.key,
                  showCheckmark: false,
                  selectedColor: verde,
                  backgroundColor: Colors.transparent,
                  side: BorderSide(
                    color: _periodo == e.key
                        ? verde
                        : Colors.white24,
                  ),
                  labelStyle: TextStyle(
                    color: _periodo == e.key
                        ? Colors.black
                        : Colors.white70,
                  ),
                  onSelected: (_) {
                    setState(() => _periodo = e.key);
                  },
                ),
            ],
          ),

          const SizedBox(height: 22),

          if (lista.isEmpty)
            CartaoVisual(
              child: Column(
                children: [
                  const IconeVisual(
                    Icons.history,
                    tamanho: 56,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _resultados.isEmpty
                        ? 'Seu histórico começa aqui'
                        : 'Nenhum treino neste período',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _resultados.isEmpty
                        ? 'Sincronize pelo relógio para receber seus treinos.'
                        : 'Selecione outro período para ver mais registros.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),

          for (final grupo in grupos.entries) ...[
            tituloVisual(context, grupo.key),
            for (final r in grupo.value) ...[
              _cartaoResultado(r),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _cartaoResultado(Json r) {
    final d = DateTime.fromMillisecondsSinceEpoch(
      (r['inicio'] as num).toInt(),
    );

    final horario =
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';

    final cargas = r['cargas'] as List;

    return CartaoVisual(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          key: PageStorageKey('resultado-${r['id']}'),

          tilePadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),

          childrenPadding: const EdgeInsets.fromLTRB(
            16, 0, 16, 16,
          ),

          leading: Container(
            width: 48,
            height: 57,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${d.day}',
                  style: const TextStyle(
                    color: verde,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  horario,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          title: Text(
            r['fichaNome'] as String,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),

          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${_duracao(r['duracaoMs'] as num)}  ·  '
              '${r['seriesConcluidas']} séries',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white70,
              ),
            ),
          ),

          children: [
            const Divider(
              height: 12,
              color: Colors.white12,
            ),

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${r['exerciciosConcluidos']} exercícios concluídos',
                style: const TextStyle(
                  color: Colors.white70,
                ),
              ),
            ),

            const SizedBox(height: 14),

            Align(
              alignment: Alignment.centerLeft,
              child: rotuloVisual(
                context,
                'Últimas cargas',
              ),
            ),

            if (cargas.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('Nenhuma carga registrada.'),
              ),

            for (final c in cargas)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        c['exercicioNome'] as String,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      c['ultimaCarga'] == null
                          ? '—'
                          : '${numero(c['ultimaCarga'] as num)} kg',
                      style: const TextStyle(
                        color: verde,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ==========================================================
// EDITOR DE FICHAS
// ==========================================================

class CamposExercicio {
  CamposExercicio(Json? dados)
      : id = dados?['id'] as String? ?? novoId('ex'),
        nome = TextEditingController(
          text: dados?['nome'] as String? ?? '',
        ),
        series = TextEditingController(
          text: '${dados?['series'] ?? 3}',
        ),
        reps = TextEditingController(
          text: '${dados?['reps'] ?? 10}',
        ),
        carga = TextEditingController(
          text: '${dados?['carga'] ?? 0}'.replaceAll('.', ','),
        ),
        descanso = TextEditingController(
          text: '${dados?['descanso'] ?? 60}',
        );

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
      'carga': double.parse(
        carga.text.trim().replaceAll(',', '.'),
      ),
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
  final _removidos = <CamposExercicio>[];

  late final TextEditingController _nome;
  late final String _id;

  bool _salvando = false;

  @override
  void initState() {
    super.initState();

    _id = widget.ficha?['id'] as String? ?? novoId('ficha');

    _nome = TextEditingController(
      text: widget.ficha?['nome'] as String? ?? '',
    );

    final dados = widget.ficha?['exercicios'] as List?;

    if (dados == null || dados.isEmpty) {
      _exercicios.add(CamposExercicio(null));
    } else {
      for (final e in dados) {
        _exercicios.add(
          CamposExercicio(Json.from(e as Map)),
        );
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
        'exercicios': _exercicios
            .map((e) => e.toJson())
            .toList(),
      });

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() => _salvando = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensagemErro(e))),
      );
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
      keyboardType: TextInputType.numberWithOptions(
        decimal: decimal,
      ),
      decoration: InputDecoration(labelText: rotulo),
      validator: (valor) {
        final texto = (valor ?? '')
            .trim()
            .replaceAll(',', '.');

        final num? n = decimal
            ? double.tryParse(texto)
            : int.tryParse(texto);

        if (n == null ||
            !n.isFinite ||
            n < minimo ||
            n > maximo) {
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
          title: Text(
            widget.ficha == null
                ? 'Nova ficha'
                : 'Editar ficha',
          ),
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
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
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
                              textCapitalization:
                                  TextCapitalization.sentences,
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
                    label: Text(
                      _salvando ? 'Salvando...' : 'Salvar ficha',
                    ),
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