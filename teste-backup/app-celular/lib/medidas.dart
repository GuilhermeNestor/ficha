import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'banco.dart';

String _num1(num v) => v.toStringAsFixed(1).replaceAll('.', ',');

String _dataCurta(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}

const _meses = [
  'JAN', 'FEV', 'MAR', 'ABR', 'MAI', 'JUN',
  'JUL', 'AGO', 'SET', 'OUT', 'NOV', 'DEZ',
];

// ---------------------------------------------------------------------------
// Componentes visuais reutilizáveis
// ---------------------------------------------------------------------------

class _Cartao extends StatelessWidget {
  const _Cartao({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.destaque = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final cor = esquema.primary;
    final sup = esquema.surface;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: destaque ? cor.withAlpha(70) : Colors.white10),
        color: destaque ? null : sup,
        gradient: destaque
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.alphaBlend(cor.withAlpha(45), sup), sup],
              )
            : null,
      ),
      child: child,
    );
  }
}

Widget _pilula(double delta, String unidade) {
  final zero = delta.abs() < 0.05;
  final icone = zero
      ? Icons.remove
      : (delta > 0 ? Icons.arrow_upward : Icons.arrow_downward);

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white10,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, size: 14, color: Colors.white70),
        const SizedBox(width: 4),
        Text(
          zero ? 'estável' : '${_num1(delta.abs())} $unidade',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

Widget _tituloSecao(BuildContext context, String texto) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
    child: Text(
      texto,
      style: Theme.of(context)
          .textTheme
          .titleLarge
          ?.copyWith(fontWeight: FontWeight.bold),
    ),
  );
}

// ---------------------------------------------------------------------------
// Séries do gráfico
// ---------------------------------------------------------------------------

/// Uma série do gráfico. Pode juntar várias medidas e usar a média delas
/// (ex.: braço direito + braço esquerdo = braços).
class _Serie {
  const _Serie(this.nome, this.unidade, this.chaves, {this.circ = false});

  final String nome;
  final String unidade;
  final List<String> chaves;

  /// true: as chaves ficam dentro de 'circunferenciasCm'.
  final bool circ;

  bool get ehMedia => chaves.length > 1;

  /// Média dos valores disponíveis. Se só um lado foi medido, usa só ele.
  double? valor(Json m) {
    final fonte = circ ? m['circunferenciasCm'] : m;
    if (fonte is! Map) return null;

    final valores = <double>[];
    for (final k in chaves) {
      final x = fonte[k];
      if (x is num) valores.add(x.toDouble());
    }
    if (valores.isEmpty) return null;

    return valores.reduce((a, b) => a + b) / valores.length;
  }
}

const _pares = <String, List<String>>{
  'braco': ['bracoD', 'bracoE'],
  'coxa': ['coxaD', 'coxaE'],
  'panturrilha': ['panturrilhaD', 'panturrilhaE'],
};

const _nomesPares = <String, String>{
  'braco': 'Braços',
  'coxa': 'Coxas',
  'panturrilha': 'Panturrilhas',
};

Map<String, _Serie> _montarSeries() {
  final s = <String, _Serie>{
    'pesoKg': const _Serie('Peso', 'kg', ['pesoKg']),
    'gorduraPct': const _Serie('% gordura', '%', ['gorduraPct']),
    'massaMagraKg': const _Serie('Massa magra', 'kg', ['massaMagraKg']),
    'cinturaCm': const _Serie('Cintura', 'cm', ['cinturaCm']),
  };

  final usadas = <String>{};

  for (final e in _pares.entries) {
    final existentes =
        e.value.where(circunferenciasMedidas.containsKey).toList();
    if (existentes.isEmpty) continue;
    usadas.addAll(existentes);
    s['circ:${e.key}'] =
        _Serie(_nomesPares[e.key]!, 'cm', existentes, circ: true);
  }

  for (final e in circunferenciasMedidas.entries) {
    if (usadas.contains(e.key) || e.key == 'cintura') continue;
    s['circ:${e.key}'] = _Serie(e.value, 'cm', [e.key], circ: true);
  }

  return s;
}

final Map<String, _Serie> _series = _montarSeries();

// ---------------------------------------------------------------------------
// Tela principal
// ---------------------------------------------------------------------------

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
    final salvou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _FormMedida(medida: medida)),
    );
    if (salvou == true && mounted) await _carregar();
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

    try {
      await Banco.instancia.excluirMedida(medida['id'] as String);
      if (mounted) await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível excluir: '
            '${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  List<_Ponto> _pontos() {
    final serie = _series[_serie]!;
    final pontos = <_Ponto>[];

    for (final m in _medidas) {
      final v = serie.valor(m);
      if (v != null) pontos.add(_Ponto(m['data'] as int, v));
    }

    return pontos;
  }

  Widget _botaoNova() {
    return FilledButton.icon(
      onPressed: () => _editar(),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: const Icon(Icons.add),
      label: const Text(
        'Nova avaliação',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _tile(String rotulo, String valor, IconData icone, Color cor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, size: 18, color: cor),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                valor,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              rotulo,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroi() {
    final tema = Theme.of(context);
    final cor = tema.colorScheme.primary;
    final ultima = _medidas.isEmpty ? null : _medidas.last;

    if (ultima == null) {
      return _Cartao(
        destaque: true,
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.monitor_weight_outlined, size: 40, color: cor),
            const SizedBox(height: 14),
            Text(
              'Seu ponto de partida',
              style: tema.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Comece registrando suas medidas. Todos os campos são opcionais.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 22),
            _botaoNova(),
          ],
        ),
      );
    }

    final pesoBruto = ultima['pesoKg'];
    final num? peso = pesoBruto is num ? pesoBruto : null;

    // Último peso registrado antes desta avaliação (pode ter ficado para trás).
    num? anterior;
    for (var i = _medidas.length - 2; i >= 0; i--) {
      final v = _medidas[i]['pesoKg'];
      if (v is num) {
        anterior = v;
        break;
      }
    }
    final delta = (peso == null || anterior == null)
        ? null
        : (peso - anterior).toDouble();

    String valorDe(String chave, String sufixo) {
      final v = ultima[chave];
      return v is num ? '${_num1(v)}$sufixo' : '—';
    }

    return _Cartao(
      destaque: true,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ÚLTIMA AVALIAÇÃO',
                style: TextStyle(
                  color: cor,
                  fontSize: 12,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _dataCurta(ultima['data'] as int),
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                peso == null ? '—' : _num1(peso),
                style: tema.textTheme.displayMedium
                    ?.copyWith(fontWeight: FontWeight.bold, height: 1),
              ),
              if (peso != null) ...[
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    'kg',
                    style: TextStyle(fontSize: 20, color: Colors.white70),
                  ),
                ),
              ],
              const Spacer(),
              if (delta != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _pilula(delta, 'kg'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _tile('Gordura', valorDe('gorduraPct', '%'),
                  Icons.water_drop_outlined, cor),
              const SizedBox(width: 10),
              _tile('Massa magra', valorDe('massaMagraKg', ' kg'),
                  Icons.fitness_center, cor),
              const SizedBox(width: 10),
              _tile('Cintura', valorDe('cinturaCm', ' cm'), Icons.straighten,
                  cor),
            ],
          ),
          const SizedBox(height: 20),
          _botaoNova(),
        ],
      ),
    );
  }

  Widget _chips(Color cor) {
    final entradas = _series.entries.toList();

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entradas.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final e = entradas[i];
          final sel = e.key == _serie;

          return ChoiceChip(
            label: Text(e.value.nome),
            selected: sel,
            showCheckmark: false,
            selectedColor: cor,
            backgroundColor: Colors.transparent,
            side: BorderSide(color: sel ? cor : Colors.white24),
            labelStyle: TextStyle(
              color: sel ? Colors.black : Colors.white70,
              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
            ),
            onSelected: (_) => setState(() => _serie = e.key),
          );
        },
      ),
    );
  }

  Widget _graficoCard(Color cor) {
    final tema = Theme.of(context);
    final serie = _series[_serie]!;
    final pontos = _pontos();
    final delta = pontos.length < 2
        ? null
        : pontos.last.valor - pontos[pontos.length - 2].valor;
    final unidadeDelta = _serie == 'gorduraPct' ? 'p.p.' : serie.unidade;

    return _Cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            serie.nome.toUpperCase(),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (pontos.isEmpty)
            const Text(
              'Esta medida ainda não foi registrada.',
              style: TextStyle(color: Colors.white70),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _num1(pontos.last.valor),
                  style: tema.textTheme.displaySmall
                      ?.copyWith(fontWeight: FontWeight.bold, height: 1),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    serie.unidade,
                    style: const TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                ),
                const Spacer(),
                if (delta != null) _pilula(delta, unidadeDelta),
              ],
            ),
          if (serie.ehMedia && pontos.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Média entre o lado direito e o esquerdo.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          if (pontos.length >= 2) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 170,
              width: double.infinity,
              child: CustomPaint(painter: _GraficoLinha(pontos, cor)),
            ),
          ] else if (pontos.length == 1)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Mais um registro desta medida libera o gráfico.',
                style: TextStyle(color: Colors.white54),
              ),
            ),
        ],
      ),
    );
  }

  String _resumo(Json m) {
    final partes = <String>[];
    if (m['gorduraPct'] is num) {
      partes.add('${_num1(m['gorduraPct'] as num)}% gordura');
    }
    if (m['cinturaCm'] is num) {
      partes.add('cintura ${_num1(m['cinturaCm'] as num)} cm');
    }
    final c = m['circunferenciasCm'];
    if (c is Map) {
      final n = c.values.where((v) => v is num).length;
      if (n > 0) partes.add('$n regiões');
    }
    if (partes.isEmpty) {
      return m['pesoKg'] is num ? 'Somente peso' : 'Sem medidas';
    }
    return partes.join(' · ');
  }

  Widget _itemHistorico(Json m, Color cor, Color sup) {
    final d = DateTime.fromMillisecondsSinceEpoch(m['data'] as int);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: sup,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white10),
        ),
        child: InkWell(
          onTap: () => _editar(m),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(
              children: [
                Container(
                  width: 52,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: cor.withAlpha(28),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Text(
                        d.day.toString().padLeft(2, '0'),
                        style: TextStyle(
                          color: cor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        _meses[d.month - 1],
                        style: TextStyle(
                          color: cor.withAlpha(190),
                          fontSize: 11,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m['pesoKg'] is num
                            ? '${_num1(m['pesoKg'] as num)} kg'
                            : 'Medidas corporais',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _resumo(m),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white54),
                  onSelected: (v) {
                    if (v == 'editar') {
                      _editar(m);
                    } else {
                      _excluir(m);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'editar', child: Text('Editar')),
                    PopupMenuItem(value: 'excluir', child: Text('Excluir')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
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

    final esquema = Theme.of(context).colorScheme;
    final cor = esquema.primary;
    final sup = esquema.surface;
    final temDados = _medidas.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        _heroi(),
        if (temDados) ...[
          const SizedBox(height: 28),
          _tituloSecao(context, 'Evolução'),
          _chips(cor),
          const SizedBox(height: 12),
          _graficoCard(cor),
          const SizedBox(height: 28),
          _tituloSecao(context, 'Histórico'),
          for (final m in _medidas.reversed) _itemHistorico(m, cor, sup),
        ],
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
    const margemEsq = 38.0, margemBase = 22.0, margemTopo = 10.0;
    const margemDir = 12.0;

    final area = Rect.fromLTWH(
      margemEsq,
      margemTopo,
      size.width - margemEsq - margemDir,
      size.height - margemBase - margemTopo,
    );

    var minV = pontos.map((p) => p.valor).reduce((a, b) => a < b ? a : b);
    var maxV = pontos.map((p) => p.valor).reduce((a, b) => a > b ? a : b);
    if (maxV - minV < 1) {
      minV -= 0.5;
      maxV += 0.5;
    }
    final folga = (maxV - minV) * 0.12;
    minV -= folga;
    maxV += folga;

    final t0 = pontos.first.data, t1 = pontos.last.data;

    Offset pos(_Ponto p) => Offset(
          area.left +
              (t1 == t0 ? 0.5 : (p.data - t0) / (t1 - t0)) * area.width,
          area.bottom - (p.valor - minV) / (maxV - minV) * area.height,
        );

    final grade = Paint()
      ..color = Colors.white10
      ..strokeWidth = 1;
    const estiloTexto = TextStyle(color: Colors.white38, fontSize: 11);

    void texto(String s, Offset o, {bool direita = false}) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: estiloTexto),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, direita ? Offset(o.dx - tp.width, o.dy) : o);
      tp.dispose();
    }

    for (var i = 0; i <= 3; i++) {
      final v = minV + (maxV - minV) * i / 3;
      final yy = area.bottom - area.height * i / 3;
      canvas.drawLine(Offset(area.left, yy), Offset(area.right, yy), grade);
      texto(_num1(v), Offset(area.left - 8, yy - 7), direita: true);
    }

    texto(_dataCurta(t0).substring(0, 5), Offset(area.left, area.bottom + 6));
    if (t1 != t0) {
      texto(
        _dataCurta(t1).substring(0, 5),
        Offset(area.right - 28, area.bottom + 6),
      );
    }

    final o = [for (final p in pontos) pos(p)];

    // Curva suave passando por todos os pontos.
    final linha = Path()..moveTo(o.first.dx, o.first.dy);
    for (var i = 1; i < o.length; i++) {
      final a = o[i - 1], b = o[i];
      final cx = (a.dx + b.dx) / 2;
      linha.cubicTo(cx, a.dy, cx, b.dy, b.dx, b.dy);
    }

    // Degradê embaixo da linha.
    final preenchimento = Path.from(linha)
      ..lineTo(o.last.dx, area.bottom)
      ..lineTo(o.first.dx, area.bottom)
      ..close();

    canvas.drawPath(
      preenchimento,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [cor.withAlpha(90), cor.withAlpha(0)],
        ).createShader(area),
    );

    canvas.drawPath(
      linha,
      Paint()
        ..color = cor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    if (o.length <= 24) {
      for (final p in o) {
        canvas.drawCircle(p, 3, Paint()..color = cor);
      }
    }

    // Último ponto em destaque.
    final u = o.last;
    canvas.drawCircle(u, 10, Paint()..color = cor.withAlpha(55));
    canvas.drawCircle(u, 5.5, Paint()..color = cor);
    canvas.drawCircle(u, 2.2, Paint()..color = const Color(0xFF090B09));
  }

  @override
  bool shouldRepaint(_GraficoLinha antigo) =>
      antigo.pontos != pontos || antigo.cor != cor;
}

// ---------------------------------------------------------------------------
// Formulário com o mapa corporal
// ---------------------------------------------------------------------------

class _FormMedida extends StatefulWidget {
  const _FormMedida({this.medida});

  final Json? medida;

  @override
  State<_FormMedida> createState() => _FormMedidaState();
}

class _FormMedidaState extends State<_FormMedida>
    with SingleTickerProviderStateMixin {
  late final AnimationController _zoom = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
    reverseDuration: const Duration(milliseconds: 330),
  );

  final _entrada = TextEditingController();
  final _mapaKey = GlobalKey();
  String? _regiao, _erroLocal;
  bool _voltando = false;

  late final TextEditingController _peso;
  late final TextEditingController _gordura;
  late final TextEditingController _cintura;
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
    _zoom.dispose();
    _entrada.dispose();
    _peso.dispose();
    _gordura.dispose();
    _cintura.dispose();
    for (final c in _circ.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _campo(String k) =>
      k == 'cintura' ? _cintura : _circ[k]!;

  void _medir(String k) {
    if (_regiao != null || _salvando) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _regiao = k;
      _erroLocal = null;
      _entrada.text = _campo(k).text;
    });
    _zoom.forward(from: 0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _mapaKey.currentContext;
      if (mounted && c != null) {
        Scrollable.ensureVisible(
          c,
          alignment: 0.12,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _voltarMapa(bool aplicar) async {
    final k = _regiao;
    if (k == null || _voltando) return;

    final v = _entrada.text.trim().replaceAll(',', '.');
    final n = double.tryParse(v);
    final minimo = k == 'cintura' ? 30 : 10;

    if (aplicar &&
        v.isNotEmpty &&
        (n == null || !n.isFinite || n < minimo || n > 250)) {
      setState(() => _erroLocal = 'Use um valor entre $minimo e 250 cm.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      if (aplicar) _campo(k).text = v.replaceAll('.', ',');
      _voltando = true;
      _erroLocal = null;
    });

    await _zoom.reverse();
    if (!mounted) return;
    setState(() {
      _regiao = null;
      _voltando = false;
    });
  }

  Future<void> _escolherData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (d != null && mounted) setState(() => _data = d);
  }

  Future<void> _salvar() async {
    if (_salvando || _regiao != null) return;

    // Tudo é opcional, mas é preciso preencher pelo menos uma coisa.
    final algum = _peso.text.trim().isNotEmpty ||
        _gordura.text.trim().isNotEmpty ||
        _cintura.text.trim().isNotEmpty ||
        _circ.values.any((c) => c.text.trim().isNotEmpty);
    if (!algum) {
      setState(() => _erro = 'Preencha ao menos uma medida para salvar.');
      return;
    }

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
        // Mantém uma observação antiga, sem exibir o campo no formulário.
        if (widget.medida?['observacao'] is String)
          'observacao': widget.medida!['observacao'],
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

  Widget _editor(String k) {
    final esquema = Theme.of(context).colorScheme;
    final cor = esquema.primary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(cor.withAlpha(22), const Color(0xff1b211b)),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cor.withAlpha(90)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _rotulo(k),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _entrada,
            enabled: !_voltando,
            autofocus: false,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Medida',
              suffixText: 'cm',
              errorText: _erroLocal,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => _voltarMapa(true),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _voltando ? null : () => _voltarMapa(true),
            child: const Text('Aplicar'),
          ),
          TextButton(
            onPressed: _voltando ? null : () => _voltarMapa(false),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Widget _mapa() {
    return LayoutBuilder(
      key: _mapaKey,
      builder: (context, limites) {
        final w = limites.maxWidth;
        final escala = w / 360;
        final k = _regiao;
        final cor = Theme.of(context).colorScheme.primary;
        final editorNaDireita = k != null && _locais[k]!.dx >= 180;
        final valores = {
          for (final nome in _locais.keys) nome: _campo(nome).text,
        };

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, 0.05),
              radius: 0.8,
              colors: [cor.withAlpha(30), Colors.transparent],
            ),
          ),
          child: ClipRect(
            child: SizedBox(
              width: w,
              height: 440 * escala,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _zoom,
                      builder: (_, __) => CustomPaint(
                        painter: _Figura(
                          valores,
                          k,
                          Curves.easeInOutCubic.transform(_zoom.value),
                        ),
                      ),
                    ),
                  ),
                  if (k == null)
                    for (final e in _locais.entries)
                      Positioned(
                        left: e.value.dx * escala - 20,
                        top: e.value.dy * escala - 20,
                        width: 40,
                        height: 40,
                        child: Semantics(
                          button: true,
                          label: _rotulo(e.key),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _medir(e.key),
                          ),
                        ),
                      ),
                  if (k == null)
                    for (final e in _legendas.entries)
                      Positioned(
                        left: e.value.dx == 0 ? 0 : null,
                        right: e.value.dx != 0 ? 0 : null,
                        top: (e.value.dy - 20) * escala,
                        width: 90 * escala,
                        height: 40 * escala,
                        child: Semantics(
                          button: true,
                          label: valores[e.key]!.isEmpty
                              ? '${_rotulo(e.key)}, sem medida'
                              : '${_rotulo(e.key)}: ${valores[e.key]} cm',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _medir(e.key),
                          ),
                        ),
                      ),
                  if (k != null)
                    Align(
                      alignment: editorNaDireita
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: SizedBox(
                          width: w * 0.48,
                          child: SingleChildScrollView(child: _editor(k)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _cartaoBasico(Color cor) {
    const teclado = TextInputType.numberWithOptions(decimal: true);

    return _Cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: _escolherData,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cor.withAlpha(28),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.calendar_today_outlined,
                          size: 18, color: cor),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Data da avaliação',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    Text(
                      _dataCurta(_data.millisecondsSinceEpoch),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, color: Colors.white38),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _peso,
                  keyboardType: teclado,
                  decoration: const InputDecoration(
                    labelText: 'Peso',
                    suffixText: 'kg',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _gordura,
                  keyboardType: teclado,
                  decoration: const InputDecoration(
                    labelText: 'Gordura',
                    suffixText: '%',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Peso e gordura são opcionais. A gordura serve para calcular a massa magra.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _cartaoMapa(Color cor) {
    final total = _locais.length;
    final feitas =
        _locais.keys.where((k) => _campo(k).text.trim().isNotEmpty).length;

    return _Cartao(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Mapa corporal',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: cor.withAlpha(28),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$feitas/$total',
                          style: TextStyle(
                            color: cor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: feitas / total,
                      minHeight: 5,
                      backgroundColor: Colors.white10,
                      color: cor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _regiao == null
                        ? 'Toque em uma região para aproximar e medir.'
                        : _rotulo(_regiao!),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            _mapa(),
            if (_regiao == null)
              ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                title: const Text('Escolher região pelo nome'),
                children: [
                  for (final k in _locais.keys)
                    ListTile(
                      dense: true,
                      title: Text(_rotulo(k)),
                      trailing: Text(
                        _campo(k).text.isEmpty ? '—' : '${_campo(k).text} cm',
                        style: TextStyle(
                          color: _campo(k).text.isEmpty ? Colors.white38 : cor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () => _medir(k),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.medida == null ? 'Nova avaliação' : 'Editar avaliação'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _cartaoBasico(cor),
            const SizedBox(height: 16),
            _cartaoMapa(cor),
            const SizedBox(height: 20),
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _erro!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            FilledButton.icon(
              onPressed: _salvando || _regiao != null ? null : _salvar,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              icon: const Icon(Icons.check),
              label: Text(
                _salvando ? 'Salvando…' : 'Salvar avaliação',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Coordenadas do desenho na vista frontal.
// O lado esquerdo da pessoa aparece à direita de quem olha.
const _locais = <String, Offset>{
  'pescoco': Offset(180, 76),
  'ombros': Offset(224, 95),
  'peito': Offset(164, 118),
  'bracoD': Offset(119, 140),
  'bracoE': Offset(241, 140),
  'cintura': Offset(153, 158),
  'abdomen': Offset(183, 178),
  'quadril': Offset(158, 209),
  'coxaD': Offset(154, 252),
  'coxaE': Offset(206, 252),
  'panturrilhaD': Offset(152, 340),
  'panturrilhaE': Offset(208, 340),
};

String _rotulo(String k) =>
    k == 'cintura' ? 'Cintura' : (circunferenciasMedidas[k] ?? k);

// x = 0: legenda à esquerda. x = 1: legenda à direita.
// y define a altura de cada legenda para separar as linhas.
const _legendas = <String, Offset>{
  'pescoco': Offset(0, 52),
  'peito': Offset(0, 97),
  'bracoD': Offset(0, 143),
  'cintura': Offset(0, 189),
  'coxaD': Offset(0, 261),
  'panturrilhaD': Offset(0, 342),
  'ombros': Offset(1, 73),
  'bracoE': Offset(1, 123),
  'abdomen': Offset(1, 171),
  'quadril': Offset(1, 218),
  'coxaE': Offset(1, 261),
  'panturrilhaE': Offset(1, 342),
};

const _acento = Color(0xffc4ef88);

class _Anel {
  const _Anel(this.centro, this.rx, this.ry);

  final Offset centro;
  final double rx, ry;
}

// Onde a fita métrica passa em cada região (mesmas coordenadas do desenho).
const _aneis = <String, _Anel>{
  'pescoco': _Anel(Offset(180, 74), 8, 2.5),
  'ombros': _Anel(Offset(180, 93), 54, 7),
  'peito': _Anel(Offset(180, 116), 41, 7),
  'bracoD': _Anel(Offset(122, 140), 13, 4),
  'bracoE': _Anel(Offset(238, 140), 13, 4),
  'cintura': _Anel(Offset(180, 158), 29, 5),
  'abdomen': _Anel(Offset(180, 180), 29, 5),
  'quadril': _Anel(Offset(180, 210), 38, 6),
  'coxaD': _Anel(Offset(159, 252), 19, 5),
  'coxaE': _Anel(Offset(201, 252), 19, 5),
  'panturrilhaD': _Anel(Offset(156, 340), 15, 4.5),
  'panturrilhaE': _Anel(Offset(204, 340), 15, 4.5),
};

class _Figura extends CustomPainter {
  final Map<String, String> preenchidas;
  final String? foco;
  final double t;

  _Figura(this.preenchidas, this.foco, this.t);

  // Metade do corpo fechada pela linha central, usada no preenchimento.
  static final Path _silhueta = Path.from(_tracos[0])..close();

  /// Anel de fita métrica: metade da frente forte, metade de trás fraca.
  void _fita(
    Canvas canvas,
    _Anel a,
    double opacidade,
    double largura, {
    double forca = 1,
  }) {
    if (opacidade <= 0) return;

    final rect = Rect.fromCenter(
      center: a.centro,
      width: a.rx * 2,
      height: a.ry * 2,
    );
    final pena = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = largura
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect,
      math.pi,
      math.pi,
      false,
      pena..color = _acento.withAlpha((70 * opacidade * forca).round()),
    );
    canvas.drawArc(
      rect,
      0,
      math.pi,
      false,
      pena..color = _acento.withAlpha((235 * opacidade * forca).round()),
    );
  }

  // Desenhamos uma metade do corpo e espelhamos a outra.
  // O último caminho contém apenas os traços centrais.
  static final _tracos = <Path>[
    Path()
      ..moveTo(180, 23)
      ..quadraticBezierTo(171, 22, 166, 30)
      ..quadraticBezierTo(162, 38, 165, 48)
      ..quadraticBezierTo(162, 45, 162, 50)
      ..quadraticBezierTo(162, 56, 166, 57)
      ..quadraticBezierTo(168, 65, 175, 69)
      ..lineTo(175, 76)
      ..quadraticBezierTo(166, 82, 151, 85)
      ..quadraticBezierTo(132, 85, 125, 97)
      ..quadraticBezierTo(119, 106, 119, 118)
      ..quadraticBezierTo(111, 132, 107, 148)
      ..lineTo(104, 159)
      ..quadraticBezierTo(95, 169, 91, 183)
      ..lineTo(83, 203)
      ..quadraticBezierTo(79, 208, 77, 216)
      ..lineTo(74, 224)
      ..quadraticBezierTo(74, 230, 78, 228)
      ..lineTo(82, 222)
      ..quadraticBezierTo(80, 232, 83, 233)
      ..quadraticBezierTo(90, 230, 94, 217)
      ..lineTo(96, 209)
      ..quadraticBezierTo(108, 197, 116, 181)
      ..quadraticBezierTo(122, 171, 123, 160)
      ..quadraticBezierTo(132, 151, 137, 135)
      ..lineTo(141, 125)
      ..quadraticBezierTo(145, 143, 148, 151)
      ..quadraticBezierTo(153, 166, 151, 177)
      ..lineTo(147, 198)
      ..quadraticBezierTo(143, 210, 143, 224)
      ..quadraticBezierTo(139, 247, 143, 268)
      ..lineTo(147, 290)
      ..quadraticBezierTo(143, 304, 146, 316)
      ..quadraticBezierTo(139, 334, 143, 353)
      ..lineTo(148, 376)
      ..lineTo(147, 393)
      ..quadraticBezierTo(141, 402, 136, 407)
      ..quadraticBezierTo(133, 412, 140, 414)
      ..lineTo(155, 414)
      ..quadraticBezierTo(162, 413, 163, 408)
      ..lineTo(162, 394)
      ..quadraticBezierTo(165, 379, 165, 367)
      ..quadraticBezierTo(174, 345, 169, 325)
      ..lineTo(170, 309)
      ..quadraticBezierTo(176, 294, 174, 277)
      ..quadraticBezierTo(180, 254, 180, 234),

    Path()
      // Pescoço, clavícula e deltoide
      ..moveTo(175, 73)
      ..quadraticBezierTo(174, 83, 179, 88)
      ..moveTo(171, 78)
      ..quadraticBezierTo(157, 85, 151, 92)
      ..quadraticBezierTo(140, 94, 133, 103)
      ..moveTo(150, 87)
      ..quadraticBezierTo(135, 87, 129, 96)
      ..quadraticBezierTo(122, 105, 121, 119)
      ..quadraticBezierTo(129, 118, 136, 109)
      ..quadraticBezierTo(140, 102, 149, 96)
      // Peitoral
      ..moveTo(176, 93)
      ..quadraticBezierTo(159, 88, 145, 99)
      ..quadraticBezierTo(137, 109, 137, 119)
      ..quadraticBezierTo(143, 130, 154, 131)
      ..quadraticBezierTo(167, 131, 177, 124)
      ..quadraticBezierTo(180, 109, 176, 93)
      // Braço e antebraço
      ..moveTo(121, 120)
      ..quadraticBezierTo(112, 132, 109, 151)
      ..quadraticBezierTo(118, 153, 125, 141)
      ..quadraticBezierTo(132, 130, 134, 119)
      ..moveTo(132, 128)
      ..quadraticBezierTo(130, 148, 122, 155)
      ..lineTo(114, 161)
      ..moveTo(105, 160)
      ..quadraticBezierTo(99, 171, 94, 189)
      ..lineTo(87, 205)
      ..moveTo(117, 161)
      ..quadraticBezierTo(111, 178, 96, 200)
      // Serrátil e oblíquos
      ..moveTo(148, 132)
      ..quadraticBezierTo(154, 136, 158, 143)
      ..lineTo(149, 139)
      ..moveTo(149, 143)
      ..lineTo(158, 151)
      ..lineTo(151, 148)
      ..moveTo(151, 153)
      ..quadraticBezierTo(159, 158, 162, 169)
      ..lineTo(153, 163)
      ..moveTo(153, 171)
      ..quadraticBezierTo(156, 189, 171, 205)
      // Abdômen
      ..moveTo(162, 135)
      ..quadraticBezierTo(168, 131, 178, 131)
      ..lineTo(178, 143)
      ..quadraticBezierTo(171, 146, 164, 144)
      ..close()
      ..moveTo(165, 149)
      ..quadraticBezierTo(172, 147, 178, 148)
      ..lineTo(178, 158)
      ..quadraticBezierTo(172, 162, 166, 158)
      ..close()
      ..moveTo(167, 165)
      ..quadraticBezierTo(172, 163, 178, 163)
      ..lineTo(178, 176)
      ..quadraticBezierTo(170, 179, 167, 173)
      ..close()
      ..moveTo(166, 181)
      ..quadraticBezierTo(169, 193, 179, 203)
      ..moveTo(151, 193)
      ..quadraticBezierTo(157, 207, 177, 220)
      // Coxa e joelho
      ..moveTo(147, 213)
      ..quadraticBezierTo(145, 241, 150, 257)
      ..quadraticBezierTo(155, 274, 151, 287)
      ..moveTo(151, 216)
      ..quadraticBezierTo(168, 234, 166, 258)
      ..quadraticBezierTo(162, 277, 156, 287)
      ..quadraticBezierTo(149, 263, 150, 250)
      ..moveTo(176, 235)
      ..quadraticBezierTo(175, 254, 169, 269)
      ..quadraticBezierTo(166, 281, 168, 290)
      ..moveTo(148, 295)
      ..quadraticBezierTo(157, 290, 166, 296)
      ..lineTo(162, 308)
      ..quadraticBezierTo(156, 315, 150, 307)
      ..close()
      // Panturrilha e pé
      ..moveTo(147, 318)
      ..quadraticBezierTo(143, 342, 151, 358)
      ..quadraticBezierTo(156, 347, 156, 317)
      ..moveTo(163, 315)
      ..quadraticBezierTo(172, 337, 159, 358)
      ..lineTo(155, 387)
      ..moveTo(149, 371)
      ..lineTo(153, 390)
      ..moveTo(148, 397)
      ..lineTo(141, 408),

    Path()
      ..moveTo(166, 42)
      ..quadraticBezierTo(170, 40, 174, 42)
      ..moveTo(169, 55)
      ..lineTo(173, 61)
      ..moveTo(107, 167)
      ..lineTo(96, 194)
      ..moveTo(154, 222)
      ..quadraticBezierTo(165, 241, 160, 259)
      ..moveTo(152, 319)
      ..lineTo(149, 343),

    Path()
      ..moveTo(175, 69)
      ..quadraticBezierTo(180, 72, 185, 69)
      ..moveTo(178, 88)
      ..lineTo(182, 88)
      ..moveTo(180, 180)
      ..relativeLineTo(0, 4),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final alvo = _locais[foco] ?? const Offset(180, 220);
    final escalaTela = size.width / 360;
    final zoom = 1 + 1.6 * t;

    // O músculo ocupa um lado e o editor ocupa o lado oposto.
    final destinoX = alvo.dx >= 180 ? 83.0 : 277.0;

    canvas.save();
    canvas.scale(escalaTela);
    canvas.translate(
      (destinoX - alvo.dx * 2.6) * t,
      (215 - alvo.dy * 2.6) * t,
    );
    canvas.scale(zoom);

    final pena = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (var lado = 0; lado < 2; lado++) {
      canvas.save();
      if (lado == 1) {
        canvas.translate(360, 0);
        canvas.scale(-1, 1);
      }

      // Corpo com leve preenchimento em degradê.
      canvas.drawPath(
        _silhueta,
        Paint()
          ..style = PaintingStyle.fill
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x2EC4EF88), Color(0x08C4EF88)],
          ).createShader(const Rect.fromLTWH(60, 23, 240, 391)),
      );

      // Brilho suave no contorno.
      canvas.drawPath(
        _tracos[0],
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2
          ..strokeJoin = StrokeJoin.round
          ..color = _acento.withAlpha(60)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
      );

      for (var i = 0; i < _tracos.length - 1; i++) {
        pena.color =
            i == 0 ? const Color(0xffd9e4d5) : const Color(0xff9bae9e);
        pena.strokeWidth = i == 0 ? 1.65 : 1.15;
        canvas.drawPath(_tracos[i], pena);
      }
      canvas.restore();
    }

    // Traços centrais (uma vez só, sem espelhar).
    pena
      ..color = const Color(0xff9bae9e)
      ..strokeWidth = 1.15;
    canvas.drawPath(_tracos.last, pena);

    // Fitas das regiões já medidas (fracas; somem durante o zoom).
    for (final e in preenchidas.entries) {
      if (e.value.isEmpty || e.key == foco) continue;
      final a = _aneis[e.key];
      if (a != null) _fita(canvas, a, 1 - t, 1.0, forca: 0.5);
    }

    // Fita da região escolhida.
    if (foco != null) {
      final a = _aneis[foco!];
      if (a != null) {
        canvas.drawOval(
          Rect.fromCenter(
            center: a.centro,
            width: a.rx * 2,
            height: a.ry * 2,
          ),
          Paint()..color = _acento.withAlpha((38 * t).round()),
        );
        _fita(canvas, a, t, 1.7);
      }
      canvas.drawCircle(
        alvo,
        2.6,
        Paint()..color = _acento.withAlpha((255 * t).round()),
      );
    }
    canvas.restore();

    if (t >= 1) return;

    canvas.save();
    canvas.scale(escalaTela);

    for (final e in _legendas.entries) {
      final esquerda = e.value.dx == 0;
      final y = e.value.dy;
      final p = _locais[e.key]!;
      final valor = preenchidas[e.key] ?? '';
      final alpha = (255 * (1 - t)).round();
      final feito = valor.isNotEmpty;

      final cor = (feito ? const Color(0xffc4ef88) : const Color(0xffa5b2aa))
          .withAlpha(alpha);

      final linha = Path()
        ..moveTo(p.dx, p.dy)
        ..lineTo(esquerda ? 98 : 262, y)
        ..lineTo(esquerda ? 86 : 274, y);

      canvas.drawPath(
        linha,
        Paint()
          ..color = cor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9,
      );

      // Marcador na região: cheio se já foi medida, vazado se não.
      if (feito) {
        canvas.drawCircle(p, 4.5, Paint()..color = cor.withAlpha((70 * (1 - t)).round()));
        canvas.drawCircle(p, 2.4, Paint()..color = cor);
      } else {
        canvas.drawCircle(
          p,
          2.4,
          Paint()
            ..color = cor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.9,
        );
      }

      void texto(String str, double top, double fonte, FontWeight peso) {
        final tp = TextPainter(
          text: TextSpan(
            text: str,
            style: TextStyle(color: cor, fontSize: fonte, fontWeight: peso),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 80);
        tp.paint(canvas, Offset(esquerda ? 8 : 352 - tp.width, top));
        tp.dispose();
      }

      final nome = _rotulo(e.key)
          .replaceAll(' direito', ' D')
          .replaceAll(' esquerdo', ' E')
          .replaceAll(' direita', ' D')
          .replaceAll(' esquerda', ' E');

      texto(nome, feito ? y - 16 : y - 8, 11, FontWeight.w500);
      if (feito) {
        texto('$valor cm', y - 1, 13, FontWeight.bold);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_Figura old) =>
      old.t != t || old.foco != foco || old.preenchidas != preenchidas;
}