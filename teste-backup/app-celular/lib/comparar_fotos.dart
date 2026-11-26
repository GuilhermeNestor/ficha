import 'dart:io';

import 'package:flutter/material.dart';

import 'banco.dart';

// Fotos de evolução: exibição de uma foto salva e tela de comparação
// entre duas avaliações. As fotos ficam só neste celular.

String _num1(num v) => v.toStringAsFixed(1).replaceAll('.', ',');

String _dataCurta(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// Mostra uma foto guardada pelo nome do arquivo.
class FotoImg extends StatefulWidget {
  const FotoImg({
    super.key,
    required this.nome,
    this.fit = BoxFit.cover,
    this.cacheWidth = 700,
  });

  final String nome;
  final BoxFit fit;
  final int cacheWidth;

  @override
  State<FotoImg> createState() => _FotoImgState();
}

class _FotoImgState extends State<FotoImg> {
  late Future<File> _arquivo = Banco.instancia.arquivoFoto(widget.nome);

  @override
  void didUpdateWidget(FotoImg antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.nome != widget.nome) {
      _arquivo = Banco.instancia.arquivoFoto(widget.nome);
    }
  }

  Widget _vazio({bool erro = false}) => Container(
        color: Colors.white10,
        alignment: Alignment.center,
        child: erro
            ? const Icon(Icons.broken_image_outlined, color: Colors.white38)
            : null,
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File>(
      future: _arquivo,
      builder: (context, snap) {
        final arquivo = snap.data;
        if (snap.hasError) return _vazio(erro: true);
        if (arquivo == null) return _vazio();

        return Image.file(
          arquivo,
          fit: widget.fit,
          cacheWidth: widget.cacheWidth,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _vazio(erro: true),
        );
      },
    );
  }
}

String? _fotoDa(Json m, String vista) {
  final lista = m['fotos'];
  if (lista is! List) return null;
  for (final f in lista) {
    if (f is Map && f['vista'] == vista && f['arquivo'] is String) {
      return f['arquivo'] as String;
    }
  }
  return null;
}

class TelaCompararFotos extends StatefulWidget {
  const TelaCompararFotos({super.key, required this.medidas});

  /// Todas as avaliações, da mais antiga para a mais recente.
  final List<Json> medidas;

  @override
  State<TelaCompararFotos> createState() => _TelaCompararFotosState();
}

class _TelaCompararFotosState extends State<TelaCompararFotos> {
  late String _vista;
  String? _antesId, _depoisId;
  bool _deslizar = false;

  List<Json> _avaliacoes(String vista) => [
        for (final m in widget.medidas)
          if (_fotoDa(m, vista) != null) m,
      ];

  List<String> get _vistasComFoto => [
        for (final k in vistasFoto.keys)
          if (_avaliacoes(k).isNotEmpty) k,
      ];

  @override
  void initState() {
    super.initState();

    // Começa pela vista que tem mais avaliações com foto.
    var melhor = vistasFoto.keys.first;
    var maior = -1;
    for (final k in vistasFoto.keys) {
      final n = _avaliacoes(k).length;
      if (n > maior) {
        maior = n;
        melhor = k;
      }
    }
    _vista = melhor;
    _padrao();
  }

  /// Antes = a avaliação mais antiga com a foto; Depois = a mais recente.
  void _padrao() {
    final lista = _avaliacoes(_vista);
    _antesId = lista.isEmpty ? null : lista.first['id'] as String;
    _depoisId = lista.isEmpty ? null : lista.last['id'] as String;
  }

  Json? _achar(String? id) {
    for (final m in widget.medidas) {
      if (m['id'] == id) return m;
    }
    return null;
  }

  void _ampliar(String nome) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: FotoImg(
                  nome: nome,
                  fit: BoxFit.contain,
                  cacheWidth: 1600,
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                  tooltip: 'Fechar',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _etiqueta(String texto) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          texto,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );

  Widget _fotoCard(Json m, String rotulo) {
    final nome = _fotoDa(m, _vista)!;
    final data = _dataCurta(m['data'] as int);

    return GestureDetector(
      onTap: () => _ampliar(nome),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FotoImg(nome: nome),
              Positioned(
                left: 8,
                bottom: 8,
                child: _etiqueta('$rotulo · $data'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seletor(
    String rotulo,
    String? valor,
    List<Json> lista,
    ValueChanged<String?> aoMudar,
  ) {
    return Expanded(
      child: DropdownButtonFormField<String>(
        key: ValueKey('$rotulo-$_vista-$valor'),
        initialValue: valor,
        isExpanded: true,
        decoration: InputDecoration(labelText: rotulo),
        items: [
          for (final m in lista)
            DropdownMenuItem(
              value: m['id'] as String,
              child: Text(_dataCurta(m['data'] as int)),
            ),
        ],
        onChanged: aoMudar,
      ),
    );
  }

  Widget _linhaDelta(String rotulo, num a, num b, String unidade) {
    final d = (b - a).toDouble();
    final sinal = d > 0 ? '+' : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(rotulo, style: const TextStyle(color: Colors.white70)),
          ),
          Text(
            '${_num1(a)} → ${_num1(b)} $unidade',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          SizedBox(
            width: 74,
            child: Text(
              '$sinal${_num1(d)}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartaoDeltas(Json antes, Json depois) {
    final linhas = <Widget>[];

    void tentar(String rotulo, String chave, String unidade) {
      final a = antes[chave], b = depois[chave];
      if (a is num && b is num) linhas.add(_linhaDelta(rotulo, a, b, unidade));
    }

    tentar('Peso', 'pesoKg', 'kg');
    tentar('Gordura', 'gorduraPct', '%');
    tentar('Massa magra', 'massaMagraKg', 'kg');
    tentar('Cintura', 'cinturaCm', 'cm');

    final ca = antes['circunferenciasCm'], cb = depois['circunferenciasCm'];
    if (ca is Map && cb is Map) {
      for (final e in circunferenciasMedidas.entries) {
        final a = ca[e.key], b = cb[e.key];
        if (a is num && b is num) linhas.add(_linhaDelta(e.value, a, b, 'cm'));
      }
    }

    final dias = DateTime.fromMillisecondsSinceEpoch(depois['data'] as int)
        .difference(DateTime.fromMillisecondsSinceEpoch(antes['data'] as int))
        .inDays;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            dias == 0 ? 'No mesmo dia' : '$dias dias de diferença',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (linhas.isEmpty)
            const Text(
              'As duas avaliações não têm medidas em comum para comparar.',
              style: TextStyle(color: Colors.white54),
            )
          else
            ...linhas,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vistas = _vistasComFoto;
    final lista = _avaliacoes(_vista);
    final antes = _achar(_antesId);
    final depois = _achar(_depoisId);

    return Scaffold(
      appBar: AppBar(title: const Text('Comparar fotos')),
      body: SafeArea(
        child: vistas.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Nenhuma foto salva ainda.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      for (final k in vistas)
                        ButtonSegment(value: k, label: Text(vistasFoto[k]!)),
                    ],
                    selected: {_vista},
                    onSelectionChanged: (s) => setState(() {
                      _vista = s.first;
                      _padrao();
                    }),
                  ),
                  const SizedBox(height: 16),
                  if (lista.length < 2)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Text(
                        'Só há uma avaliação com a foto de ${vistasFoto[_vista]!.toLowerCase()}. '
                        'Faça outra avaliação com a mesma pose para comparar.',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        _seletor('Antes', _antesId, lista,
                            (v) => setState(() => _antesId = v)),
                        const SizedBox(width: 12),
                        _seletor('Depois', _depoisId, lista,
                            (v) => setState(() => _depoisId = v)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: false, label: Text('Lado a lado')),
                        ButtonSegment(value: true, label: Text('Deslizar')),
                      ],
                      selected: {_deslizar},
                      onSelectionChanged: (s) =>
                          setState(() => _deslizar = s.first),
                    ),
                    const SizedBox(height: 16),
                    if (antes != null && depois != null) ...[
                      if (_deslizar)
                        _Deslizar(
                          antes: _fotoDa(antes, _vista)!,
                          depois: _fotoDa(depois, _vista)!,
                          rotuloAntes:
                              'Antes · ${_dataCurta(antes['data'] as int)}',
                          rotuloDepois:
                              'Depois · ${_dataCurta(depois['data'] as int)}',
                        )
                      else
                        Row(
                          children: [
                            Expanded(child: _fotoCard(antes, 'Antes')),
                            const SizedBox(width: 10),
                            Expanded(child: _fotoCard(depois, 'Depois')),
                          ],
                        ),
                      const SizedBox(height: 8),
                      const Text(
                        'Toque em uma foto para ampliar.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      _cartaoDeltas(antes, depois),
                    ],
                  ],
                ],
              ),
      ),
    );
  }
}

class _RecorteEsquerdo extends CustomClipper<Rect> {
  _RecorteEsquerdo(this.pos);

  final double pos;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * pos, size.height);

  @override
  bool shouldReclip(_RecorteEsquerdo antigo) => antigo.pos != pos;
}

/// Duas fotos sobrepostas com uma divisória que o dedo arrasta.
class _Deslizar extends StatefulWidget {
  const _Deslizar({
    required this.antes,
    required this.depois,
    required this.rotuloAntes,
    required this.rotuloDepois,
  });

  final String antes, depois, rotuloAntes, rotuloDepois;

  @override
  State<_Deslizar> createState() => _DeslizarState();
}

class _DeslizarState extends State<_Deslizar> {
  double _pos = 0.5;

  Widget _etiqueta(String texto) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          texto,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = w * 4 / 3;

        return GestureDetector(
          onHorizontalDragUpdate: (d) => setState(
            () => _pos = (_pos + d.delta.dx / w).clamp(0.0, 1.0),
          ),
          onTapDown: (d) => setState(
            () => _pos = (d.localPosition.dx / w).clamp(0.0, 1.0),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: FotoImg(nome: widget.depois, cacheWidth: 1000),
                  ),
                  Positioned.fill(
                    child: ClipRect(
                      clipper: _RecorteEsquerdo(_pos),
                      child: FotoImg(nome: widget.antes, cacheWidth: 1000),
                    ),
                  ),
                  Positioned(
                    left: w * _pos - 1,
                    top: 0,
                    bottom: 0,
                    width: 2,
                    child: const ColoredBox(color: Colors.white),
                  ),
                  Positioned(
                    left: w * _pos - 18,
                    top: h / 2 - 18,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.compare_arrows,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: _etiqueta(widget.rotuloAntes),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: _etiqueta(widget.rotuloDepois),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}