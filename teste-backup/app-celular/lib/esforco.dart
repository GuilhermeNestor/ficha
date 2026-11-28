import 'package:flutter/material.dart';

import 'banco.dart';
import 'ia_nucleo.dart';
import 'visual.dart';

// Séries realizadas de um treino + pergunta opcional sobre o esforço da
// ÚLTIMA série de cada exercício. A resposta é guardada à parte e nunca
// altera o resultado sincronizado com o relógio.

String _num(num v) => fmtNum(v);

const _rotuloResposta = {
  '0': '0',
  '1': '1',
  '2': '2',
  '3+': '3+',
  'nao_sei': 'Não sei',
};

const _rotuloDesconforto = {
  'leve': 'Leve',
  'moderado': 'Moderado',
  'forte': 'Forte',
};

/// Lista os exercícios do treino com as séries feitas e a pergunta de esforço.
class SeriesDoTreino extends StatelessWidget {
  const SeriesDoTreino({super.key, required this.resultado});

  final Json resultado;

  @override
  Widget build(BuildContext context) {
    final series = resultado['seriesRealizadas'];
    if (series is! List || series.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text(
          'Este treino foi sincronizado sem o detalhe das séries.',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      );
    }

    final porExercicio = <String, List<Map>>{};
    final nomes = <String, String>{};
    for (final s in series) {
      if (s is! Map) continue;
      final id = '${s['exercicioId']}';
      (porExercicio[id] ??= []).add(s);
      nomes[id] = '${s['exercicioNome']}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        rotuloVisual(context, 'Séries realizadas'),
        for (final e in porExercicio.entries) ...[
          const SizedBox(height: 12),
          _ExercicioRealizado(
            resultado: resultado,
            exercicioId: e.key,
            nome: nomes[e.key]!,
            series: e.value
              ..sort((a, b) =>
                  (a['serie'] as num).compareTo(b['serie'] as num)),
          ),
        ],
      ],
    );
  }
}

class _ExercicioRealizado extends StatefulWidget {
  const _ExercicioRealizado({
    required this.resultado,
    required this.exercicioId,
    required this.nome,
    required this.series,
  });

  final Json resultado;
  final String exercicioId;
  final String nome;
  final List<Map> series;

  @override
  State<_ExercicioRealizado> createState() => _ExercicioRealizadoState();
}

class _ExercicioRealizadoState extends State<_ExercicioRealizado> {
  String? _resposta;
  String? _desconforto;
  bool _carregando = true;
  bool _salvando = false;
  String? _erro;

  String get _resultadoId => widget.resultado['id'] as String;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final e = await Banco.instancia.obterEsforco(_resultadoId, widget.exercicioId);
      if (!mounted) return;
      setState(() {
        _resposta = e?['resposta'] as String?;
        _desconforto = e?['desconforto'] as String?;
        _carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar(String? resposta, String? desconforto) async {
    if (_salvando) return;
    final anterior = (_resposta, _desconforto);
    setState(() {
      _salvando = true;
      _erro = null;
      _resposta = resposta;
      _desconforto = desconforto;
    });
    try {
      await Banco.instancia.salvarEsforco(
        resultadoId: _resultadoId,
        exercicioId: widget.exercicioId,
        resposta: resposta,
        desconforto: desconforto,
      );
      if (mounted) setState(() => _salvando = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resposta = anterior.$1;
        _desconforto = anterior.$2;
        _salvando = false;
        _erro = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Widget _chips<T>({
    required Map<String, String> opcoes,
    required String? atual,
    required void Function(String?) aoEscolher,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final o in opcoes.entries)
          ChoiceChip(
            label: Text(o.value),
            selected: atual == o.key,
            showCheckmark: false,
            selectedColor: Theme.of(context).colorScheme.primary,
            backgroundColor: Colors.transparent,
            side: BorderSide(
              color: atual == o.key
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white24,
            ),
            labelStyle: TextStyle(
              color: atual == o.key ? Colors.black : Colors.white70,
            ),
            // Tocar de novo na opção marcada limpa a resposta.
            onSelected: _salvando
                ? null
                : (_) => aoEscolher(atual == o.key ? null : o.key),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ultima = widget.series.last;
    final reps = widget.series.map((s) => '${s['repeticoes']}').join(' / ');
    final carga = (ultima['carga'] as num?) ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.nome,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            '$reps reps  ·  ${_num(carga)} kg',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (_carregando)
            const LinearProgressIndicator(minHeight: 2)
          else ...[
            Text(
              'Última série (${ultima['serie']}ª): quantas repetições boas '
              'ainda sairiam?',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            _chips<void>(
              opcoes: _rotuloResposta,
              atual: _resposta,
              aoEscolher: (v) => _salvar(v, _desconforto),
            ),
            const SizedBox(height: 4),
            const Text(
              'Opcional. Encerrar pela coroa ou pausa não prova falha '
              'muscular, e a resposta vale só para esta série.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 12),
            const Text('Teve desconforto?', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            _chips<void>(
              opcoes: _rotuloDesconforto,
              atual: _desconforto,
              aoEscolher: (v) => _salvar(_resposta, v),
            ),
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_erro!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
          ],
        ],
      ),
    );
  }
}