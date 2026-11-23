import 'package:flutter/material.dart';

import 'banco.dart';

// Perfil do usuário: dados pessoais e objetivo. Só no celular.

String _num1(num v) => v.toStringAsFixed(1).replaceAll('.', ',');

String _data(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

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

  Json? _ultimaMedida;
  bool _carregando = true, _salvando = false;
  String? _erro, _ok;

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

  Future<void> _carregar() async {
    try {
      final p = await Banco.instancia.obterPerfil();
      final medidas = await Banco.instancia.listarMedidas();
      if (!mounted) return;
      setState(() {
        _ultimaMedida = medidas.isEmpty ? null : medidas.last;
        _peso.text = _txt(_ultimaMedida?['pesoKg']);
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
    if (d != null) setState(() => _nascimento = d);
  }

  Future<void> _salvar() async {
    setState(() {
      _salvando = true;
      _erro = null;
      _ok = null;
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
      final novo = double.tryParse(_peso.text.replaceAll(',', '.'));
      if (novo != null) {
        final anterior = (_ultimaMedida?['pesoKg'] as num?)?.toDouble();
        if (anterior == null || (anterior - novo).abs() > 0.04) {
          final hoje = DateTime.now();
          final dataMs = DateTime(hoje.year, hoje.month, hoje.day, 12)
              .millisecondsSinceEpoch;
          final ultimaDia = _ultimaMedida == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  _ultimaMedida!['data'] as int);
          final mesmoDia = ultimaDia != null &&
              ultimaDia.year == hoje.year &&
              ultimaDia.month == hoje.month &&
              ultimaDia.day == hoje.day;
          _ultimaMedida = await Banco.instancia.salvarMedida({
            if (mesmoDia) ..._ultimaMedida!,
            'data': dataMs,
            'pesoKg': novo,
          });
        }
      }

      if (!mounted) return;
      setState(() {
        _salvando = false;
        _ok = 'Perfil salvo.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _erro = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Widget _dropdown(String rotulo, List<String> opcoes, String? valor,
      ValueChanged<String?> aoMudar) {
    return DropdownButtonFormField<String>(
      initialValue: valor,
      decoration: InputDecoration(labelText: rotulo),
      items: [
        for (final o in opcoes) DropdownMenuItem(value: o, child: Text(o)),
      ],
      onChanged: aoMudar,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());

    const teclado = TextInputType.numberWithOptions(decimal: true);
    final idade = _nascimento == null
        ? null
        : idadeEm(_nascimento!.millisecondsSinceEpoch);
    final alturaM =
        (double.tryParse(_altura.text.replaceAll(',', '.')) ?? 0) / 100;
    final peso = double.tryParse(_peso.text.replaceAll(',', '.'));
    final imc =
        (peso != null && alturaM > 0) ? peso / (alturaM * alturaM) : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _resumo('Idade', idade == null ? '—' : '$idade anos'),
                _resumo('Peso', peso == null ? '—' : '${_num1(peso)} kg'),
                _resumo('IMC', imc == null ? '—' : _num1(imc)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nome,
          decoration: const InputDecoration(labelText: 'Nome (opcional)'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _escolherNascimento,
          icon: const Icon(Icons.cake_outlined),
          label: Text(_nascimento == null
              ? 'Data de nascimento'
              : 'Nascimento: ${_data(_nascimento!)}'),
        ),
        const SizedBox(height: 12),
        _dropdown('Sexo', sexosPerfil, _sexo, (v) => setState(() => _sexo = v)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _altura,
                keyboardType: teclado,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Altura (cm)'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _peso,
                keyboardType: teclado,
                onChanged: (_) => setState(() {}),
                decoration:
                    const InputDecoration(labelText: 'Peso atual (kg)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Objetivo',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _dropdown('Objetivo principal', objetivosPerfil, _objetivo,
            (v) => setState(() => _objetivo = v)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _pesoMeta,
                keyboardType: teclado,
                decoration: const InputDecoration(labelText: 'Peso meta (kg)'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _gorduraMeta,
                keyboardType: teclado,
                decoration: const InputDecoration(labelText: '% gordura meta'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _dropdown('Nível de experiência', niveisPerfil, _nivel,
            (v) => setState(() => _nivel = v)),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _dias,
          decoration:
              const InputDecoration(labelText: 'Dias de treino por semana'),
          items: [
            for (var i = 1; i <= 7; i++)
              DropdownMenuItem(value: i, child: Text('$i')),
          ],
          onChanged: (v) => setState(() => _dias = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _obs,
          maxLines: 3,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Lesões, restrições, observações',
          ),
        ),
        if (_erro != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child:
                Text(_erro!, style: const TextStyle(color: Colors.redAccent)),
          ),
        if (_ok != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_ok!,
                style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ),
        FilledButton(
          onPressed: _salvando ? null : _salvar,
          child: const Text('Salvar perfil'),
        ),
      ],
    );
  }

  Widget _resumo(String titulo, String valor) => Column(
        children: [
          Text(titulo, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          Text(valor,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      );
}