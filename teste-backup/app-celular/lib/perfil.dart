import 'package:flutter/material.dart';

import 'banco.dart';

// Perfil do usuário: dados pessoais, objetivo e saúde. Só no celular.

String _num1(num v) => v.toStringAsFixed(1).replaceAll('.', ',');

String _data(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';

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

class TelaPerfil extends StatefulWidget {
  const TelaPerfil({super.key});

  @override
  State<TelaPerfil> createState() => _TelaPerfilState();
}

class _TelaPerfilState extends State<TelaPerfil> {
  final _nome = TextEditingController();
  final _altura = TextEditingController();
  final _peso = TextEditingController();
  final _pesoMeta = TextEditingController();
  final _gorduraMeta = TextEditingController();
  final _obs = TextEditingController();

  DateTime? _nascimento;
  String? _sexo, _objetivo, _nivel;
  int? _dias;

  Json? _ultimaMedida; // qualquer medida mais recente (para unir o peso)
  double? _pesoRegistrado; // último peso registrado
  double? _gorduraRegistrada; // última % de gordura registrada
  double? _magraRegistrada; // última massa magra registrada

  bool _carregando = true, _salvando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final c in [_nome, _altura, _peso, _pesoMeta, _gorduraMeta, _obs]) {
      c.dispose();
    }
    super.dispose();
  }

  String _txt(dynamic v) => v is num ? _num1(v) : '';

  double? _numero(String texto) =>
      double.tryParse(texto.trim().replaceAll(',', '.'));

  Future<void> _carregar() async {
    try {
      final p = await Banco.instancia.obterPerfil();
      final medidas = await Banco.instancia.listarMedidas();
      if (!mounted) return;

      double? ultimo(String chave) {
        for (var i = medidas.length - 1; i >= 0; i--) {
          final v = medidas[i][chave];
          if (v is num) return v.toDouble();
        }
        return null;
      }

      setState(() {
        _ultimaMedida = medidas.isEmpty ? null : medidas.last;
        _pesoRegistrado = ultimo('pesoKg');
        _gorduraRegistrada = ultimo('gorduraPct');
        _magraRegistrada = ultimo('massaMagraKg');
        _peso.text = _txt(_pesoRegistrado);

        if (p != null) {
          _nome.text = (p['nome'] as String?) ?? '';
          _altura.text = _txt(p['alturaCm']);
          _pesoMeta.text = _txt(p['pesoMetaKg']);
          _gorduraMeta.text = _txt(p['gorduraMetaPct']);
          _obs.text = (p['observacoes'] as String?) ?? '';
          _nascimento =
              DateTime.fromMillisecondsSinceEpoch(p['nascimento'] as int);
          _sexo = p['sexo'] as String?;
          _objetivo = p['objetivo'] as String?;
          _nivel = p['nivel'] as String?;
          _dias = p['diasPorSemana'] as int?;
        }
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString().replaceFirst('Exception: ', '');
        _carregando = false;
      });
    }
  }

  Future<void> _escolherNascimento() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _nascimento ?? DateTime(DateTime.now().year - 25),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      helpText: 'Data de nascimento',
    );
    if (d != null && mounted) setState(() => _nascimento = d);
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    setState(() {
      _salvando = true;
      _erro = null;
    });

    try {
      await Banco.instancia.salvarPerfil({
        'nome': _nome.text,
        'nascimento': _nascimento?.millisecondsSinceEpoch,
        'sexo': _sexo,
        'alturaCm': _altura.text,
        'objetivo': _objetivo,
        'nivel': _nivel,
        'diasPorSemana': _dias,
        'pesoMetaKg': _pesoMeta.text,
        'gorduraMetaPct': _gorduraMeta.text,
        'observacoes': _obs.text,
      });

      // Peso atual: se mudou, registra como medida de hoje.
      final novo = _numero(_peso.text);
      if (novo != null) {
        final anterior = _pesoRegistrado;
        if (anterior == null || (anterior - novo).abs() > 0.04) {
          final hoje = DateTime.now();
          final dataMs = DateTime(hoje.year, hoje.month, hoje.day, 12)
              .millisecondsSinceEpoch;
          final ultima = _ultimaMedida;
          final ultimaDia = ultima == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(ultima['data'] as int);
          final mesmoDia = ultimaDia != null &&
              ultimaDia.year == hoje.year &&
              ultimaDia.month == hoje.month &&
              ultimaDia.day == hoje.day;

          _ultimaMedida = await Banco.instancia.salvarMedida({
            if (ultima != null && mesmoDia) ...ultima,
            'data': dataMs,
            'pesoKg': novo,
          });
          _pesoRegistrado = novo;
        }
      }

      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil salvo.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _erro = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ---------------------------------------------------------------- cálculos

  int? get _idade => _nascimento == null
      ? null
      : idadeEm(_nascimento!.millisecondsSinceEpoch);

  double? get _imc {
    final alturaM = (_numero(_altura.text) ?? 0) / 100;
    final peso = _numero(_peso.text);
    if (peso == null || alturaM <= 0) return null;
    return peso / (alturaM * alturaM);
  }

  String _classeImc(double imc) {
    if (imc < 18.5) return 'Abaixo do peso';
    if (imc < 25) return 'Peso normal';
    if (imc < 30) return 'Sobrepeso';
    return 'Obesidade';
  }

  /// Gasto basal estimado (Mifflin-St Jeor). Só para Masculino/Feminino.
  int? get _gastoBasal {
    final peso = _numero(_peso.text);
    final altura = _numero(_altura.text);
    final idade = _idade;
    if (peso == null || altura == null || idade == null) return null;
    if (_sexo == 'Masculino') {
      return (10 * peso + 6.25 * altura - 5 * idade + 5).round();
    }
    if (_sexo == 'Feminino') {
      return (10 * peso + 6.25 * altura - 5 * idade - 161).round();
    }
    return null;
  }

  // ---------------------------------------------------------------- widgets

  Widget _titulo(String texto, {String? apoio}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            texto,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (apoio != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                apoio,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _rotuloCampo(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          texto,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      );

  Widget _estatistica(String titulo, String valor, {String? detalhe}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            titulo.toUpperCase(),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (detalhe != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                detalhe,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cabecalho(Color cor) {
    final nome = _nome.text.trim();
    final idade = _idade;
    final altura = _numero(_altura.text);
    final peso = _numero(_peso.text);
    final imc = _imc;
    final gasto = _gastoBasal;

    final linha = [
      if (idade != null) '$idade anos',
      if (altura != null) '${_num1(altura)} cm',
    ].join(' · ');

    final composicao = [
      if (_gorduraRegistrada != null)
        '${_num1(_gorduraRegistrada!)}% de gordura',
      if (_magraRegistrada != null)
        '${_num1(_magraRegistrada!)} kg de massa magra',
    ].join(' · ');

    return _Cartao(
      destaque: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cor.withAlpha(34),
                  border: Border.all(color: cor.withAlpha(90)),
                ),
                alignment: Alignment.center,
                child: nome.isEmpty
                    ? Icon(Icons.person_outline, color: cor, size: 28)
                    : Text(
                        nome.characters.first.toUpperCase(),
                        style: TextStyle(
                          color: cor,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome.isEmpty ? 'Seu perfil' : nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      linha.isEmpty
                          ? 'Complete seus dados abaixo'
                          : linha,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _estatistica('Peso', peso == null ? '—' : '${_num1(peso)} kg'),
              _estatistica(
                'IMC',
                imc == null ? '—' : _num1(imc),
                detalhe: imc == null ? null : _classeImc(imc),
              ),
              _estatistica(
                'Gasto basal',
                gasto == null ? '—' : '$gasto',
                detalhe: gasto == null ? 'precisa do sexo' : 'kcal/dia',
              ),
            ],
          ),
          if (composicao.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              composicao,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _linhaNascimento(Color cor) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: _escolherNascimento,
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
                child: Icon(Icons.cake_outlined, size: 18, color: cor),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Data de nascimento',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              Text(
                _nascimento == null ? 'Escolher' : _data(_nascimento!),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _nascimento == null ? cor : null,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cartaoDados(Color cor) {
    const teclado = TextInputType.numberWithOptions(decimal: true);

    return _Cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titulo('Dados pessoais'),
          TextField(
            controller: _nome,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Nome (opcional)'),
          ),
          const SizedBox(height: 8),
          _linhaNascimento(cor),
          if (_nascimento != null)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 4),
              child: Text(
                'A idade se atualiza sozinha a cada aniversário.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          _rotuloCampo('Sexo'),
          SegmentedButton<String>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            segments: [
              for (final s in sexosPerfil)
                ButtonSegment(value: s, label: Text(s)),
            ],
            selected: {if (_sexo != null) _sexo!},
            onSelectionChanged: (v) =>
                setState(() => _sexo = v.isEmpty ? null : v.first),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _altura,
                  keyboardType: teclado,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Altura',
                    suffixText: 'cm',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _peso,
                  keyboardType: teclado,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Peso atual',
                    suffixText: 'kg',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Ao mudar o peso, ele entra no histórico de medidas com a data de hoje.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _cartaoObjetivo(Color cor) {
    const teclado = TextInputType.numberWithOptions(decimal: true);

    return _Cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titulo('Objetivo'),
          _rotuloCampo('Objetivo principal'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in objetivosPerfil)
                _chip(o, _objetivo == o, cor,
                    () => setState(() => _objetivo = _objetivo == o ? null : o)),
            ],
          ),
          const SizedBox(height: 18),
          _rotuloCampo('Nível de experiência'),
          SegmentedButton<String>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            segments: [
              for (final n in niveisPerfil)
                ButtonSegment(value: n, label: Text(n)),
            ],
            selected: {if (_nivel != null) _nivel!},
            onSelectionChanged: (v) =>
                setState(() => _nivel = v.isEmpty ? null : v.first),
          ),
          const SizedBox(height: 18),
          _rotuloCampo('Dias de treino por semana'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 1; i <= 7; i++)
                _chip('$i', _dias == i, cor,
                    () => setState(() => _dias = _dias == i ? null : i)),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _pesoMeta,
                  keyboardType: teclado,
                  decoration: const InputDecoration(
                    labelText: 'Peso meta',
                    suffixText: 'kg',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _gorduraMeta,
                  keyboardType: teclado,
                  decoration: const InputDecoration(
                    labelText: 'Gordura meta',
                    suffixText: '%',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String texto, bool selecionado, Color cor, VoidCallback aoTocar) {
    return ChoiceChip(
      label: Text(texto),
      selected: selecionado,
      showCheckmark: false,
      selectedColor: cor,
      backgroundColor: Colors.transparent,
      side: BorderSide(color: selecionado ? cor : Colors.white24),
      labelStyle: TextStyle(
        color: selecionado ? Colors.black : Colors.white70,
        fontWeight: selecionado ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (_) => aoTocar(),
    );
  }

  Widget _cartaoSaude() {
    return _Cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titulo(
            'Saúde',
            apoio: 'Ajuda o personal a evitar exercícios que machuquem.',
          ),
          TextField(
            controller: _obs,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Lesões, restrições e observações',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());

    final cor = Theme.of(context).colorScheme.primary;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _cabecalho(cor),
        const SizedBox(height: 16),
        _cartaoDados(cor),
        const SizedBox(height: 16),
        _cartaoObjetivo(cor),
        const SizedBox(height: 16),
        _cartaoSaude(),
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
          onPressed: _salvando ? null : _salvar,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          icon: const Icon(Icons.check),
          label: Text(
            _salvando ? 'Salvando…' : 'Salvar perfil',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}