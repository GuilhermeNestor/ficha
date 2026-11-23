import 'package:flutter/material.dart';

import 'banco.dart';

// Tela de medidas corporais: peso, % de gordura, massa magra, cintura e
// circunferências. Fica só no celular: não sincroniza com o relógio.

String _num1(num v) => v.toStringAsFixed(1).replaceAll('.', ',');

String _dataCurta(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// séries que podem ser escolhidas no gráfico
final Map<String, String> _series = {
  'pesoKg': 'Peso',
  'gorduraPct': '% gordura',
  'massaMagraKg': 'Massa magra',
  'cinturaCm': 'Cintura',
  for (final e in circunferenciasMedidas.entries) 'circ:${e.key}': e.value,
};

String _unidadeDe(String chave) {
  if (chave == 'gorduraPct') return '%';
  if (chave == 'pesoKg' || chave == 'massaMagraKg') return 'kg';
  return 'cm';
}

class TelaMedidas extends StatefulWidget {
  const TelaMedidas({super.key});

  @override
  State<TelaMedidas> createState() => _TelaMedidasState();
}

class _TelaMedidasState extends State<TelaMedidas> {
  List<Json> _medidas = [];
  bool _carregando = true;
  String? _erro;
  String _serie = 'pesoKg';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final lista = await Banco.instancia.listarMedidas();
      if (!mounted) return;
      setState(() {
        _medidas = lista;
        _carregando = false;
        _erro = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString().replaceFirst('Exception: ', '');
        _carregando = false;
      });
    }
  }

  Future<void> _editar([Json? medida]) async {
    final salvou = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormMedida(medida: medida),
    );
    if (salvou == true) _carregar();
  }

  Future<void> _excluir(Json medida) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir medida?'),
        content: Text('Registro de ${_dataCurta(medida['data'] as int)}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await Banco.instancia.excluirMedida(medida['id'] as String);
    _carregar();
  }

  // pontos (data, valor) da série escolhida; ignora registros sem o campo
  List<_Ponto> _pontos() {
    num? valor(Json m) {
      if (_serie.startsWith('circ:')) {
        final c = m['circunferenciasCm'];
        final v = c is Map ? c[_serie.substring(5)] : null;
        return v is num ? v : null;
      }
      final v = m[_serie];
      return v is num ? v : null;
    }

    return [
      for (final m in _medidas)
        if (valor(m) != null) _Ponto(m['data'] as int, valor(m)!.toDouble()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_erro!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: _carregar, child: const Text('Tentar novamente')),
            ],
          ),
        ),
      );
    }

    final pontos = _pontos();
    final unidade = _unidadeDe(_serie);
    final recentes = _medidas.reversed.toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        FilledButton.icon(
          onPressed: () => _editar(),
          icon: const Icon(Icons.add),
          label: const Text('Registrar medidas'),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final e in _series.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: _serie == e.key,
                    onSelected: (_) => setState(() => _serie = e.key),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: pontos.length < 2
                ? const SizedBox(
                    height: 120,
                    child: Center(
                      child: Text(
                        'Registre pelo menos 2 vezes essa medida para ver o gráfico.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_num1(pontos.last.valor)} $unidade'
                        '  (${pontos.last.valor - pontos.first.valor >= 0 ? '+' : ''}'
                        '${_num1(pontos.last.valor - pontos.first.valor)} desde o início)',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 180,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _GraficoLinha(
                            pontos,
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        if (recentes.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Nenhuma medida ainda.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ),
        for (final m in recentes)
          Card(
            child: ListTile(
              onTap: () => _editar(m),
              title: Text(
                '${_num1(m['pesoKg'] as num)} kg'
                '${m['gorduraPct'] is num ? '  ·  ${_num1(m['gorduraPct'] as num)}% gordura' : ''}',
              ),
              subtitle: Text(
                [
                  _dataCurta(m['data'] as int),
                  if (m['massaMagraKg'] is num)
                    'magra ${_num1(m['massaMagraKg'] as num)} kg',
                  if (m['cinturaCm'] is num)
                    'cintura ${_num1(m['cinturaCm'] as num)} cm',
                  if (m['circunferenciasCm'] is Map &&
                      (m['circunferenciasCm'] as Map).isNotEmpty)
                    '${(m['circunferenciasCm'] as Map).length} circunferências',
                ].join('  ·  '),
              ),
              trailing: IconButton(
                tooltip: 'Excluir',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _excluir(m),
              ),
            ),
          ),
      ],
    );
  }
}

class _Ponto {
  final int data;
  final double valor;
  const _Ponto(this.data, this.valor);
}

class _GraficoLinha extends CustomPainter {
  _GraficoLinha(this.pontos, this.cor);

  final List<_Ponto> pontos;
  final Color cor;

  @override
  void paint(Canvas canvas, Size size) {
    const margemEsq = 40.0, margemBase = 20.0;
    final area = Rect.fromLTWH(
        margemEsq, 4, size.width - margemEsq - 4, size.height - margemBase - 4);

    var minV = pontos.map((p) => p.valor).reduce((a, b) => a < b ? a : b);
    var maxV = pontos.map((p) => p.valor).reduce((a, b) => a > b ? a : b);
    if (maxV - minV < 1) {
      minV -= 0.5;
      maxV += 0.5;
    }
    final folga = (maxV - minV) * 0.1;
    minV -= folga;
    maxV += folga;

    final t0 = pontos.first.data, t1 = pontos.last.data;
    double x(_Ponto p) =>
        area.left + (t1 == t0 ? 0.5 : (p.data - t0) / (t1 - t0)) * area.width;
    double y(_Ponto p) =>
        area.bottom - (p.valor - minV) / (maxV - minV) * area.height;

    final grade = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    const estiloTexto = TextStyle(color: Colors.white54, fontSize: 11);

    void texto(String s, Offset o, {bool direita = false}) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: estiloTexto),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, direita ? Offset(o.dx - tp.width, o.dy) : o);
    }

    for (var i = 0; i <= 3; i++) {
      final v = minV + (maxV - minV) * i / 3;
      final yy = area.bottom - area.height * i / 3;
      canvas.drawLine(Offset(area.left, yy), Offset(area.right, yy), grade);
      texto(_num1(v), Offset(area.left - 6, yy - 7), direita: true);
    }
    texto(_dataCurta(t0).substring(0, 5), Offset(area.left, area.bottom + 4));
    if (t1 != t0) {
      texto(_dataCurta(t1).substring(0, 5),
          Offset(area.right - 28, area.bottom + 4));
    }

    final caminho = Path();
    for (var i = 0; i < pontos.length; i++) {
      final o = Offset(x(pontos[i]), y(pontos[i]));
      i == 0 ? caminho.moveTo(o.dx, o.dy) : caminho.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      caminho,
      Paint()
        ..color = cor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    for (final p in pontos) {
      canvas.drawCircle(Offset(x(p), y(p)), 3.5, Paint()..color = cor);
    }
  }

  @override
  bool shouldRepaint(_GraficoLinha antigo) =>
      antigo.pontos != pontos || antigo.cor != cor;
}

class _FormMedida extends StatefulWidget {
  const _FormMedida({this.medida});

  final Json? medida;

  @override
  State<_FormMedida> createState() => _FormMedidaState();
}

class _FormMedidaState extends State<_FormMedida> {
  late final TextEditingController _peso;
  late final TextEditingController _gordura;
  late final TextEditingController _cintura;
  late final TextEditingController _obs;
  late DateTime _data;
  final Map<String, TextEditingController> _circ = {
    for (final k in circunferenciasMedidas.keys) k: TextEditingController(),
  };
  String? _erro;
  bool _salvando = false;

  String _txt(dynamic v) => v is num ? _num1(v) : '';

  @override
  void initState() {
    super.initState();
    final m = widget.medida;
    _peso = TextEditingController(text: _txt(m?['pesoKg']));
    _gordura = TextEditingController(text: _txt(m?['gorduraPct']));
    _cintura = TextEditingController(text: _txt(m?['cinturaCm']));
    _obs = TextEditingController(text: (m?['observacao'] as String?) ?? '');
    final c = m?['circunferenciasCm'];
    for (final k in circunferenciasMedidas.keys) {
      _circ[k]!.text = _txt(c is Map ? c[k] : null);
    }
    _data = m == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(m['data'] as int);
  }

  @override
  void dispose() {
    _peso.dispose();
    _gordura.dispose();
    _cintura.dispose();
    _obs.dispose();
    for (final c in _circ.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _escolherData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _data = d);
  }

  Future<void> _salvar() async {
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await Banco.instancia.salvarMedida({
        if (widget.medida != null) 'id': widget.medida!['id'],
        'data': DateTime(_data.year, _data.month, _data.day, 12)
            .millisecondsSinceEpoch,
        'pesoKg': _peso.text,
        'gorduraPct': _gordura.text,
        'cinturaCm': _cintura.text,
        'circunferenciasCm': {
          for (final e in _circ.entries) e.key: e.value.text,
        },
        'observacao': _obs.text,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString().replaceFirst('Exception: ', '');
        _salvando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const teclado = TextInputType.numberWithOptions(decimal: true);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.medida == null ? 'Registrar medidas' : 'Editar medidas',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _escolherData,
              icon: const Icon(Icons.calendar_today),
              label: Text(_dataCurta(_data.millisecondsSinceEpoch)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _peso,
              keyboardType: teclado,
              decoration: const InputDecoration(labelText: 'Peso (kg)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _gordura,
              keyboardType: teclado,
              decoration: const InputDecoration(
                labelText: '% de gordura (opcional)',
                helperText: 'Com ela, a massa magra é calculada sozinha.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cintura,
              keyboardType: teclado,
              decoration:
                  const InputDecoration(labelText: 'Cintura (cm, opcional)'),
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Circunferências (cm)'),
              children: [
                for (final e in circunferenciasMedidas.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _circ[e.key],
                      keyboardType: teclado,
                      decoration: InputDecoration(labelText: e.value),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _obs,
              maxLength: 300,
              decoration:
                  const InputDecoration(labelText: 'Observação (opcional)'),
            ),
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_erro!,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            FilledButton(
              onPressed: _salvando ? null : _salvar,
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}