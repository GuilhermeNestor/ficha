import 'package:flutter/material.dart';

import 'banco.dart';
import 'ia_api.dart';
import 'ia_nucleo.dart';
import 'visual.dart';

// Planejamento de hipertrofia por exercício e ajustes do Personal IA.
//
// O planejamento fica numa tabela própria. A ficha que vai para o relógio
// continua com a meta inteira (reps) e o descanso de sempre: a faixa nova
// aparece só no celular.

String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

void _aviso(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
}

String _n(num v) => fmtNum(v);

// ---------------------------------------------------------------------------
// Planejamento da ficha
// ---------------------------------------------------------------------------

class TelaPlanejamento extends StatefulWidget {
  const TelaPlanejamento({super.key, required this.ficha});

  final Json ficha;

  @override
  State<TelaPlanejamento> createState() => _TelaPlanejamentoState();
}

class _TelaPlanejamentoState extends State<TelaPlanejamento> {
  Map<String, Json> _planos = {};
  bool _carregando = true;
  String? _erro;

  String get _fichaId => widget.ficha['id'] as String;

  List<Json> get _exercicios => [
        for (final e in (widget.ficha['exercicios'] as List))
          Json.from(e as Map),
      ];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final p = await Banco.instancia.listarPlanos(_fichaId);
      if (!mounted) return;
      setState(() {
        _planos = p;
        _carregando = false;
        _erro = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = _msg(e);
        _carregando = false;
      });
    }
  }

  Future<void> _editar(Json ex) async {
    final salvou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _EditorPlano(
          fichaId: _fichaId,
          exercicio: ex,
          plano: _planos[ex['id']],
        ),
      ),
    );
    if (salvou == true && mounted) await _carregar();
  }

  String _resumoPlano(Json? p) {
    if (p == null) return 'Sem planejamento. Toque para definir.';
    final partes = <String>[];
    if (p['repsMin'] != null) partes.add('${p['repsMin']}–${p['repsMax']} reps');
    if (p['series'] != null) partes.add('${p['series']} séries');
    if (p['rirAlvo'] != null) partes.add('RIR ${p['rirAlvo']}');
    if (p['descansoPlanejadoS'] != null) {
      partes.add('descanso ${p['descansoPlanejadoS']} s');
    }
    return partes.isEmpty ? 'Planejamento sem faixa de reps.' : partes.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final exercicios = _exercicios;

    return Scaffold(
      appBar: AppBar(title: const Text('Planejamento')),
      body: SafeArea(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_erro!, textAlign: TextAlign.center),
                  ))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      CartaoVisual(
                        destaque: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            rotuloVisual(context, 'Ficha', destaque: true),
                            const SizedBox(height: 8),
                            Text(
                              '${widget.ficha['nome']}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Aqui fica o que foi planejado: faixa de '
                              'repetições, esforço desejado e regra de '
                              'progressão. O histórico das séries continua '
                              'como aconteceu, e o relógio segue usando a '
                              'meta e o descanso da ficha.',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final ex in exercicios) ...[
                        _cartaoExercicio(ex),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
      ),
    );
  }

  Widget _cartaoExercicio(Json ex) {
    final p = _planos[ex['id']];
    final cargaSug = p?['cargaSugeridaKg'];

    return CartaoVisual(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _editar(ex),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${ex['nome']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  const Icon(Icons.edit_outlined,
                      size: 18, color: Colors.white54),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'No relógio: ${ex['series']}×${ex['reps']} · '
                '${_n(ex['carga'] as num)} kg · descanso ${ex['descanso']} s',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Text(
                _resumoPlano(p),
                style: TextStyle(
                  color: p == null
                      ? Colors.white54
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
              if (cargaSug is num) ...[
                const SizedBox(height: 6),
                Text(
                  'Sugestão para a próxima sessão: ${_n(cargaSug)} kg',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
              if (p?['musculoPrincipal'] is String) ...[
                const SizedBox(height: 4),
                Text(
                  'Músculo: ${musculosIA[p!['musculoPrincipal']] ?? p['musculoPrincipal']}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorPlano extends StatefulWidget {
  const _EditorPlano({
    required this.fichaId,
    required this.exercicio,
    required this.plano,
  });

  final String fichaId;
  final Json exercicio;
  final Json? plano;

  @override
  State<_EditorPlano> createState() => _EditorPlanoState();
}

class _EditorPlanoState extends State<_EditorPlano> {
  final _repsMin = TextEditingController();
  final _repsMax = TextEditingController();
  final _series = TextEditingController();
  final _descanso = TextEditingController();
  final _execucao = TextEditingController();
  final _progressao = TextEditingController();
  final _incremento = TextEditingController();

  String _objetivo = 'hipertrofia';
  bool _forcaSecundaria = false;
  String? _musculo;
  int? _rir;

  bool _salvando = false;
  String? _erro;

  String _txt(dynamic v) => v is num ? _n(v) : '';

  @override
  void initState() {
    super.initState();
    final p = widget.plano;
    if (p != null) {
      _repsMin.text = _txt(p['repsMin']);
      _repsMax.text = _txt(p['repsMax']);
      _series.text = _txt(p['series']);
      _descanso.text = _txt(p['descansoPlanejadoS']);
      _execucao.text = (p['execucao'] as String?) ?? '';
      _progressao.text = (p['progressao'] as String?) ?? '';
      _incremento.text = _txt(p['incrementoMinimoKg']);
      _objetivo = (p['objetivoPrincipal'] as String?) ?? 'hipertrofia';
      _forcaSecundaria = p['objetivoSecundario'] == 'forca';
      _musculo = p['musculoPrincipal'] as String?;
      _rir = (p['rirAlvo'] as num?)?.toInt();
    }
  }

  @override
  void dispose() {
    for (final c in [
      _repsMin, _repsMax, _series, _descanso, _execucao, _progressao,
      _incremento,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      final antigo = widget.plano;
      await Banco.instancia.salvarPlano(
        widget.fichaId,
        widget.exercicio['id'] as String,
        {
          'objetivoPrincipal': _objetivo,
          if (_objetivo == 'hipertrofia' && _forcaSecundaria)
            'objetivoSecundario': 'forca',
          'musculoPrincipal': _musculo,
          'repsMin': _repsMin.text,
          'repsMax': _repsMax.text,
          'series': _series.text,
          'descansoPlanejadoS': _descanso.text,
          'rirAlvo': _rir,
          'execucao': _execucao.text,
          'progressao': _progressao.text,
          'incrementoMinimoKg': _incremento.text,
          // Mantém a sugestão de carga que já existia.
          if (antigo?['cargaSugeridaKg'] != null)
            'cargaSugeridaKg': antigo!['cargaSugeridaKg'],
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = _msg(e);
        _salvando = false;
      });
    }
  }

  Widget _campoNum(TextEditingController c, String rotulo,
      {bool decimal = false}) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      decoration: InputDecoration(labelText: rotulo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ex = widget.exercicio;

    return Scaffold(
      appBar: AppBar(title: const Text('Planejar exercício')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              '${ex['nome']}',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Ficha atual: ${ex['series']}×${ex['reps']} · descanso '
              '${ex['descanso']} s. Isso não muda ao salvar o plano.',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 18),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'hipertrofia', label: Text('Hipertrofia')),
                ButtonSegment(value: 'forca', label: Text('Força')),
              ],
              selected: {_objetivo},
              onSelectionChanged: (s) => setState(() {
                _objetivo = s.first;
                if (_objetivo == 'forca') _forcaSecundaria = false;
              }),
            ),
            if (_objetivo == 'hipertrofia')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Trabalho de força neste exercício'),
                subtitle: const Text('Objetivo secundário, opcional.'),
                value: _forcaSecundaria,
                onChanged: (v) => setState(() => _forcaSecundaria = v),
              ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _campoNum(_repsMin, 'Reps mínimas')),
              const SizedBox(width: 12),
              Expanded(child: _campoNum(_repsMax, 'Reps máximas')),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _campoNum(_series, 'Séries de trabalho')),
              const SizedBox(width: 12),
              Expanded(child: _campoNum(_descanso, 'Descanso planejado (s)')),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _rir,
              decoration: const InputDecoration(
                labelText: 'Esforço desejado (RIR)',
                helperText: 'Repetições em reserva ao fim da série.',
              ),
              items: [
                for (var i = 0; i <= 4; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(i == 0 ? '0 (até a falha)' : '$i'),
                  ),
              ],
              onChanged: (v) => setState(() => _rir = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _musculo,
              decoration: const InputDecoration(labelText: 'Músculo principal'),
              items: [
                for (final e in musculosIA.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _musculo = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _execucao,
              maxLength: 200,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Orientação de execução',
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _progressao,
              maxLength: 200,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Regra de progressão',
                helperText: 'Ex.: ao chegar no topo da faixa em todas as '
                    'séries, subir o menor incremento.',
              ),
            ),
            const SizedBox(height: 12),
            _campoNum(_incremento, 'Menor incremento de carga (kg)',
                decimal: true),
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_erro!,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _salvando ? null : _salvar,
              icon: const Icon(Icons.check),
              label: Text(_salvando ? 'Salvando…' : 'Salvar planejamento'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ajustes do Personal IA
// ---------------------------------------------------------------------------

class TelaAjustesIA extends StatefulWidget {
  const TelaAjustesIA({super.key});

  @override
  State<TelaAjustesIA> createState() => _TelaAjustesIAState();
}

class _TelaAjustesIAState extends State<TelaAjustesIA> {
  final _url = TextEditingController();
  final _token = TextEditingController();

  bool _http = false;
  int _semanas = 6;
  bool _carregando = true;
  bool _salvando = false;
  bool _verToken = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final b = Banco.instancia;
      final url = await b.ajuste('ia_url');
      final token = await b.ajuste('ia_token');
      final prov = await b.ajuste('ia_provedor');
      final semanas = await b.semanasLembreteRevisao();
      if (!mounted) return;
      setState(() {
        _url.text = url ?? '';
        _token.text = token ?? '';
        _http = prov == 'http';
        _semanas = semanas;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = _msg(e);
        _carregando = false;
      });
    }
  }

  Future<void> _salvar() async {
    if (_salvando) return;

    if (_http) {
      final erro = validarUrlIA(_url.text);
      if (erro != null) {
        setState(() => _erro = erro);
        return;
      }
    }

    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      final b = Banco.instancia;
      await b.definirAjuste('ia_provedor', _http ? 'http' : 'simulado');
      await b.definirAjuste('ia_url', _url.text.trim());
      await b.definirAjuste('ia_token', _token.text.trim());
      await b.definirAjuste('ia_lembrete_semanas', '$_semanas');
      if (!mounted) return;
      _aviso(context, 'Ajustes salvos.');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = _msg(e);
        _salvando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes do Personal IA')),
      body: SafeArea(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  tituloVisual(context, 'Fonte da análise'),
                  CartaoVisual(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                                value: false, label: Text('Demonstração')),
                            ButtonSegment(value: true, label: Text('Hermes')),
                          ],
                          selected: {_http},
                          onSelectionChanged: (s) =>
                              setState(() => _http = s.first),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _http
                              ? 'As avaliações vão para a sua API, que fala '
                                  'com o Hermes. A chave do provedor de IA '
                                  'fica só no servidor.'
                              : 'Respostas geradas por regras locais, sem '
                                  'IA e sem internet. Serve para testar o '
                                  'fluxo e vem marcada como demonstração.',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                        if (_http) ...[
                          const SizedBox(height: 14),
                          TextField(
                            controller: _url,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: 'URL da API (https://...)',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _token,
                            obscureText: !_verToken,
                            decoration: InputDecoration(
                              labelText: 'Token de acesso',
                              suffixIcon: IconButton(
                                onPressed: () =>
                                    setState(() => _verToken = !_verToken),
                                icon: Icon(_verToken
                                    ? Icons.visibility_off
                                    : Icons.visibility),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Este token do seu servidor fica guardado só '
                            'neste celular.',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  tituloVisual(context, 'Lembrete de revisão'),
                  CartaoVisual(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text('Lembrar a cada'),
                            ),
                            IconButton(
                              onPressed: _semanas > 1
                                  ? () => setState(() => _semanas--)
                                  : null,
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text(
                              '$_semanas ${_semanas == 1 ? 'semana' : 'semanas'}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                            IconButton(
                              onPressed: _semanas < 26
                                  ? () => setState(() => _semanas++)
                                  : null,
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                        const Text(
                          'O lembrete aparece na tela Personal IA. Ele não '
                          'chama a IA e não troca o seu treino.',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (_erro != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(_erro!,
                          style: const TextStyle(color: Colors.redAccent)),
                    ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _salvando ? null : _salvar,
                    icon: const Icon(Icons.check),
                    label: Text(_salvando ? 'Salvando…' : 'Salvar ajustes'),
                  ),
                ],
              ),
      ),
    );
  }
}