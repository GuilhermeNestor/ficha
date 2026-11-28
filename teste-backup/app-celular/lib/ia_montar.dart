import 'package:flutter/material.dart';

import 'banco.dart';
import 'ia_api.dart';
import 'ia_nucleo.dart';
import 'visual.dart';

// "Montar uma ficha": perguntas -> rascunho -> revisão -> confirmação.
// O rascunho nunca substitui uma ficha em uso: cada ficha só entra na lista
// depois que o usuário revisa e confirma.

String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

void _aviso(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
}

// ---------------------------------------------------------------------------
// Perguntas
// ---------------------------------------------------------------------------

class TelaMontarFicha extends StatefulWidget {
  const TelaMontarFicha({super.key});

  @override
  State<TelaMontarFicha> createState() => _TelaMontarFichaState();
}

class _TelaMontarFichaState extends State<TelaMontarFicha> {
  static const _objetivos = [
    'Hipertrofia',
    'Hipertrofia com trabalho de força básico',
  ];
  static const _minutos = [30, 45, 60, 75, 90];

  String? _objetivo = _objetivos.first;
  String? _experiencia;
  int? _dias;
  int? _minutosSessao;
  final Set<String> _equipamentos = {};
  final Set<String> _musculos = {};

  bool _carregando = true;
  bool _gerando = false;
  String? _erro;

  // Uma avaliação por tentativa; a mesma chave vale para repetir o envio.
  String? _avaliacaoId;

  @override
  void initState() {
    super.initState();
    _carregarPerfil();
  }

  Future<void> _carregarPerfil() async {
    try {
      final p = await Banco.instancia.obterPerfil();
      if (!mounted) return;
      setState(() {
        _experiencia = p?['nivel'] as String?;
        final d = p?['diasPorSemana'];
        if (d is int && d >= 1 && d <= 5) _dias = d;
        _carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  List<String> get _faltando => [
        if (_experiencia == null) 'seu nível de experiência',
        if (_dias == null) 'os dias disponíveis por semana',
        if (_minutosSessao == null) 'o tempo por sessão',
        if (_equipamentos.isEmpty) 'os equipamentos',
      ];

  Json get _respostas => {
        'objetivo': _objetivo,
        'experiencia': _experiencia,
        'diasDisponiveis': _dias,
        'minutosPorSessao': _minutosSessao,
        'equipamentos': _equipamentos.toList()..sort(),
        'musculosPrioritarios': _musculos.toList()..sort(),
      };

  Future<void> _gerar() async {
    if (_gerando) return;

    final falta = _faltando;
    if (falta.isNotEmpty) {
      setState(() => _erro = 'Falta responder: ${falta.join(', ')}.');
      return;
    }

    setState(() {
      _gerando = true;
      _erro = null;
    });

    try {
      _avaliacaoId ??= novoId('aval');
      final a = await ServicoIA.avaliar(
        tipo: 'montar',
        respostasMontagem: _respostas,
        avaliacaoId: _avaliacaoId,
      );
      if (!mounted) return;
      setState(() => _gerando = false);

      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => TelaRascunho(avaliacaoId: a['id'] as String),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gerando = false;
        _erro = _msg(e);
      });
    }
  }

  Widget _chips<T>({
    required Iterable<T> valores,
    required bool Function(T) selecionado,
    required String Function(T) rotulo,
    required void Function(T) aoTocar,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final v in valores)
          FilterChip(
            label: Text(rotulo(v)),
            selected: selecionado(v),
            showCheckmark: false,
            selectedColor: Theme.of(context).colorScheme.primary,
            backgroundColor: Colors.transparent,
            side: BorderSide(
              color: selecionado(v)
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white24,
            ),
            labelStyle: TextStyle(
              color: selecionado(v) ? Colors.black : Colors.white70,
            ),
            onSelected: _gerando ? null : (_) => aoTocar(v),
          ),
      ],
    );
  }

  Widget _pergunta(String titulo, Widget corpo, {String? ajuda}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: CartaoVisual(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            if (ajuda != null) ...[
              const SizedBox(height: 4),
              Text(ajuda,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
            const SizedBox(height: 12),
            corpo,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Montar uma ficha')),
      body: SafeArea(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 0, 4, 14),
                    child: Text(
                      'Responda o que falta. O rascunho aparece para você '
                      'revisar e só entra na sua lista se você confirmar. '
                      'Nenhuma ficha em uso é substituída.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                  _pergunta(
                    'Objetivo',
                    _chips<String>(
                      valores: _objetivos,
                      selecionado: (v) => _objetivo == v,
                      rotulo: (v) => v,
                      aoTocar: (v) => setState(() => _objetivo = v),
                    ),
                  ),
                  _pergunta(
                    'Experiência com musculação',
                    _chips<String>(
                      valores: niveisPerfil,
                      selecionado: (v) => _experiencia == v,
                      rotulo: (v) => v,
                      aoTocar: (v) => setState(() => _experiencia = v),
                    ),
                  ),
                  _pergunta(
                    'Dias disponíveis por semana',
                    _chips<int>(
                      valores: const [1, 2, 3, 4, 5],
                      selecionado: (v) => _dias == v,
                      rotulo: (v) => '$v',
                      aoTocar: (v) => setState(() => _dias = v),
                    ),
                    ajuda: 'Dias em que você consegue treinar de verdade.',
                  ),
                  _pergunta(
                    'Tempo por sessão',
                    _chips<int>(
                      valores: _minutos,
                      selecionado: (v) => _minutosSessao == v,
                      rotulo: (v) => '$v min',
                      aoTocar: (v) => setState(() => _minutosSessao = v),
                    ),
                  ),
                  _pergunta(
                    'Equipamentos que você tem',
                    _chips<String>(
                      valores: equipamentosIA.keys,
                      selecionado: _equipamentos.contains,
                      rotulo: (v) => equipamentosIA[v]!,
                      aoTocar: (v) => setState(() {
                        if (!_equipamentos.remove(v)) _equipamentos.add(v);
                      }),
                    ),
                    ajuda: 'Escolha um ou mais.',
                  ),
                  _pergunta(
                    'Músculos prioritários',
                    _chips<String>(
                      valores: musculosIA.keys,
                      selecionado: _musculos.contains,
                      rotulo: (v) => musculosIA[v]!,
                      aoTocar: (v) => setState(() {
                        if (!_musculos.remove(v)) _musculos.add(v);
                      }),
                    ),
                    ajuda: 'Opcional. Deixe vazio para uma divisão equilibrada.',
                  ),
                  if (_erro != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_erro!,
                          style: const TextStyle(color: Colors.redAccent)),
                    ),
                  FilledButton.icon(
                    onPressed: _gerando ? null : _gerar,
                    icon: _gerando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_outlined),
                    label: Text(_gerando ? 'Gerando rascunho…' : 'Gerar rascunho'),
                  ),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rascunho
// ---------------------------------------------------------------------------

class TelaRascunho extends StatefulWidget {
  const TelaRascunho({super.key, required this.avaliacaoId});

  final String avaliacaoId;

  @override
  State<TelaRascunho> createState() => _TelaRascunhoState();
}

class _TelaRascunhoState extends State<TelaRascunho> {
  Json? _avaliacao;
  bool _carregando = true;
  String? _erro;

  /// Índices das fichas do rascunho já salvas nesta tela.
  final Set<int> _salvas = {};
  int? _salvando;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final a = await Banco.instancia.obterAvaliacao(widget.avaliacaoId);
      if (!mounted) return;
      setState(() {
        _avaliacao = a;
        _carregando = false;
        _erro = a == null ? 'Avaliação não encontrada.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = _msg(e);
        _carregando = false;
      });
    }
  }

  List<Json> get _fichas {
    final r = _avaliacao?['resposta'];
    final rasc = r is Map ? r['rascunho'] : null;
    final lista = rasc is Map ? rasc['fichas'] : null;
    if (lista is! List) return const [];
    return [for (final f in lista) Json.from(f as Map)];
  }

  Future<void> _confirmar(int i, Json ficha) async {
    if (_salvando != null || _salvas.contains(i)) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adicionar esta ficha?'),
        content: Text(
          '"${ficha['nome']}" entra na sua lista de fichas com a carga '
          'zerada, para você definir no primeiro treino. Nenhuma ficha '
          'existente é alterada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _salvando = i);
    try {
      await Banco.instancia.confirmarFichaDoRascunho(ficha);
      if (!mounted) return;
      setState(() {
        _salvas.add(i);
        _salvando = null;
      });
      _aviso(context, 'Ficha adicionada à sua lista.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = null);
      _aviso(context, _msg(e));
    }
  }

  Widget _cartaoFicha(int i, Json ficha) {
    final salva = _salvas.contains(i);
    final exercicios = [for (final e in (ficha['exercicios'] as List)) e as Map];

    return CartaoVisual(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${ficha['nome']}',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          for (var k = 0; k < exercicios.length; k++) ...[
            _linhaExercicio(k + 1, exercicios[k]),
            if (k < exercicios.length - 1)
              const Divider(height: 22, color: Colors.white12),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed:
                (salva || _salvando != null) ? null : () => _confirmar(i, ficha),
            icon: Icon(salva ? Icons.check : Icons.playlist_add),
            label: Text(salva
                ? 'Adicionada'
                : _salvando == i
                    ? 'Adicionando…'
                    : 'Revisei, adicionar à minha lista'),
          ),
        ],
      ),
    );
  }

  Widget _linhaExercicio(int pos, Map e) {
    final musculo = e['musculoPrincipal'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$pos. ${e['nome']}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          '${e['series']} séries · ${e['repsMin']}–${e['repsMax']} reps · '
          'RIR ${e['rirAlvo']} · descanso ${e['descansoS']} s'
          '${musculo is String ? ' · ${musculosIA[musculo] ?? musculo}' : ''}',
          style: TextStyle(
              color: Theme.of(context).colorScheme.primary, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Text('Por quê: ${e['porque']}',
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 4),
        Text('Execução: ${e['execucao']}',
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 4),
        Text('Progressão: ${e['progressao']}',
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        if (e['objetivoSecundario'] == 'forca') ...[
          const SizedBox(height: 4),
          const Text('Também com trabalho de força neste exercício.',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _avaliacao;
    final fichas = _fichas;
    final demo = a?['demonstracao'] == true;
    final resumo = (a?['resposta'] as Map?)?['resumo'];

    return Scaffold(
      appBar: AppBar(title: const Text('Rascunho de ficha')),
      body: SafeArea(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_erro!, textAlign: TextAlign.center),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      if (demo)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'DEMONSTRAÇÃO: gerado por regras locais, sem IA.',
                            style: TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                          ),
                        ),
                      if (resumo is String && resumo.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: CartaoVisual(
                            destaque: true,
                            child: Text(resumo),
                          ),
                        ),
                      if (fichas.isEmpty)
                        const CartaoVisual(
                          child: Text(
                            'A resposta não trouxe nenhuma ficha. Tente '
                            'montar de novo.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      for (var i = 0; i < fichas.length; i++) ...[
                        _cartaoFicha(i, fichas[i]),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
      ),
    );
  }
}