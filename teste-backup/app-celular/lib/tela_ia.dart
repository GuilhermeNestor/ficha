import 'dart:convert';

import 'package:flutter/material.dart';

import 'banco.dart';
import 'ia_api.dart';
import 'ia_montar.dart';
import 'ia_nucleo.dart';
import 'ia_plano.dart';
import 'visual.dart';

// Personal IA: a IA sugere, você decide. Nada muda sozinho.

String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

String _dataMs(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// "2026-11-12" -> "12/11"
String _dataIso(String iso) {
  final p = iso.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}' : iso;
}

const _nomeTipo = {
  'semana': 'Avaliação da semana',
  'revisao': 'Revisão da ficha',
  'montar': 'Ficha nova (rascunho)',
};

const _iconeAcao = {
  'manter': Icons.pause_circle_outline,
  'ajustar_series': Icons.layers_outlined,
  'sugerir_carga': Icons.fitness_center,
  'ajustar_plano': Icons.tune,
  'trocar_exercicio': Icons.swap_horiz,
  'observar': Icons.visibility_outlined,
};

const _nomeAcao = {
  'manter': 'Manter',
  'ajustar_series': 'Ajustar séries',
  'sugerir_carga': 'Sugestão de carga',
  'ajustar_plano': 'Ajustar planejamento',
  'trocar_exercicio': 'Trocar exercício',
  'observar': 'Observar',
};

void _aviso(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
}

// ===========================================================================
// TELA INICIAL DO PERSONAL IA
// ===========================================================================

class TelaPersonalIA extends StatefulWidget {
  const TelaPersonalIA({super.key});

  @override
  State<TelaPersonalIA> createState() => _TelaPersonalIAState();
}

class _TelaPersonalIAState extends State<TelaPersonalIA> {
  bool _carregando = true;
  String? _erro;

  List<Json> _fichas = [];
  String? _fichaId;
  Json _lembrete = const {};
  List<Json> _pendentes = [];
  Map<String, Json> _avaliacoes = {};
  ProvedorIA? _provedor;

  /// Tipo em andamento ('semana', 'revisao'); trava toque duplo.
  String? _executando;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final b = Banco.instancia;
      final fichas = await b.listarFichas();
      var escolhida = await b.ajuste('ia_ficha');
      if (fichas.isEmpty) {
        escolhida = null;
      } else if (escolhida == null ||
          !fichas.any((f) => f['id'] == escolhida)) {
        escolhida = fichas.first['id'] as String;
      }

      final pendentes = await b.listarSugestoes(estado: 'pendente');
      final avaliacoes = <String, Json>{};
      for (final s in pendentes) {
        final id = s['avaliacaoId'] as String;
        if (!avaliacoes.containsKey(id)) {
          final a = await b.obterAvaliacao(id);
          if (a != null) avaliacoes[id] = a;
        }
      }

      final lembrete = await b.lembreteRevisao();
      final provedor = await ServicoIA.provedorAtual();

      if (!mounted) return;
      setState(() {
        _fichas = fichas;
        _fichaId = escolhida;
        _pendentes = pendentes;
        _avaliacoes = avaliacoes;
        _lembrete = lembrete;
        _provedor = provedor;
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

  Json? get _ficha {
    for (final f in _fichas) {
      if (f['id'] == _fichaId) return f;
    }
    return null;
  }

  Future<void> _escolherFicha(String? id) async {
    if (id == null) return;
    await Banco.instancia.definirAjuste('ia_ficha', id);
    setState(() => _fichaId = id);
  }

  Future<void> _abrir(Widget tela) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => tela));
    if (mounted) await _carregar();
  }

  Future<void> _avaliar(String tipo) async {
    if (_executando != null) return;
    if (_fichaId == null) {
      _aviso(context, 'Crie uma ficha primeiro.');
      return;
    }

    setState(() => _executando = tipo);
    try {
      final r = await ServicoIA.avaliar(tipo: tipo, fichaId: _fichaId);
      if (!mounted) return;
      await _abrir(TelaAvaliacaoIA(avaliacaoId: r['id'] as String));
    } on ErroIA catch (e) {
      if (mounted) _aviso(context, e.mensagem);
      if (mounted) await _carregar();
    } catch (e) {
      if (mounted) _aviso(context, _msg(e));
    } finally {
      if (mounted) setState(() => _executando = null);
    }
  }

  Future<void> _anteciparRevisao() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Antecipar a revisão?'),
        content: const Text(
          'Use quando você mudou de objetivo, de dias disponíveis ou de '
          'equipamento. Isso só marca a revisão como recomendada; nada é '
          'enviado nem alterado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Marcar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await Banco.instancia.definirAjuste('ia_revisao_antecipada', '1');
    if (mounted) await _carregar();
  }

  Widget _acao({
    required IconData icone,
    required String titulo,
    required String texto,
    required VoidCallback? aoTocar,
    bool carregando = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CartaoVisual(
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                IconeVisual(icone),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 3),
                      Text(texto,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
                if (carregando)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                else
                  const Icon(Icons.chevron_right, color: Colors.white38),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cabecalho() {
    final ultima = _lembrete['ultimaRevisao'] as int?;
    final dias = _lembrete['diasDesdeUltima'] as int?;
    final demo = _provedor?.demonstracao ?? true;

    return CartaoVisual(
      destaque: true,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: rotuloVisual(context, 'Ficha em análise', destaque: true),
              ),
              if (demo)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(40),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('DEMONSTRAÇÃO',
                      style: TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_fichas.isEmpty)
            const Text('Nenhuma ficha cadastrada.')
          else
            DropdownButtonFormField<String>(
              initialValue: _fichaId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Ficha'),
              items: [
                for (final f in _fichas)
                  DropdownMenuItem(
                    value: f['id'] as String,
                    child: Text(f['nome'] as String,
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _executando != null ? null : _escolherFicha,
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.event_available_outlined,
                  size: 18, color: Colors.white54),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ultima == null
                      ? 'Última revisão: nenhuma ainda'
                      : 'Última revisão: ${_dataMs(ultima)}'
                          '${dias == null ? '' : ' (há $dias dias)'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
          if (demo)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Sem URL configurada, as respostas vêm de regras locais de '
                'exemplo, não de uma IA. Configure em Ajustes.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bannerLembrete() {
    if (_lembrete['devido'] != true) return const SizedBox.shrink();

    final motivo = _lembrete['motivo'];
    final semanas = _lembrete['semanas'];
    final texto = motivo == 'antecipada'
        ? 'Você marcou a revisão como recomendada.'
        : motivo == 'sem_revisao'
            ? 'Você treina há mais de $semanas semanas e ainda não revisou a ficha.'
            : 'Já se passaram $semanas semanas desde a última revisão.';

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: CartaoVisual(
        child: Row(
          children: [
            const IconeVisual(Icons.notifications_active_outlined),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Hora de revisar?',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(texto,
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 4),
                  const Text(
                    'É só um lembrete: a ficha não muda sozinha.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
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
                  onPressed: _carregar, child: const Text('Tentar novamente')),
            ],
          ),
        ),
      );
    }

    final ocupado = _executando != null;

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _cabecalho(),
          _bannerLembrete(),
          const SizedBox(height: 20),
          tituloVisual(context, 'O que você quer fazer?'),
          _acao(
            icone: Icons.calendar_view_week_outlined,
            titulo: 'Avaliar minha semana',
            texto: 'Olha os treinos dos últimos 7 dias e sugere ajustes pontuais.',
            carregando: _executando == 'semana',
            aoTocar: ocupado ? null : () => _avaliar('semana'),
          ),
          _acao(
            icone: Icons.fact_check_outlined,
            titulo: 'Revisar minha ficha',
            texto: 'Considera o histórico completo. Pode recomendar manter.',
            carregando: _executando == 'revisao',
            aoTocar: ocupado ? null : () => _avaliar('revisao'),
          ),
          _acao(
            icone: Icons.auto_awesome_outlined,
            titulo: 'Montar uma ficha',
            texto: 'Gera um rascunho a partir das suas respostas. '
                'Não substitui a ficha em uso.',
            aoTocar: ocupado ? null : () => _abrir(const TelaMontarFicha()),
          ),
          const SizedBox(height: 14),
          tituloVisual(
            context,
            'Sugestões para decidir',
            acao: Text('${_pendentes.length}',
                style: const TextStyle(color: Colors.white54)),
          ),
          if (_pendentes.isEmpty)
            const CartaoVisual(
              child: Text(
                'Nenhuma sugestão pendente. Quando você avaliar a semana ou '
                'revisar a ficha, os cartões aparecem aqui para aceitar ou '
                'ignorar.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          for (final s in _pendentes.take(6))
            if (_avaliacoes[s['avaliacaoId']] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: CartaoSugestao(
                  sugestao: s,
                  pedido: Json.from(
                      _avaliacoes[s['avaliacaoId']]!['pedido'] as Map),
                  demonstracao:
                      _avaliacoes[s['avaliacaoId']]!['demonstracao'] == true,
                  aoMudar: _carregar,
                ),
              ),
          if (_pendentes.length > 6)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _abrir(const TelaHistoricoIA()),
                child: Text('Ver as outras ${_pendentes.length - 6}'),
              ),
            ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                onPressed: _fichas.isEmpty
                    ? null
                    : () => _abrir(TelaPlanejamento(ficha: _ficha!)),
                icon: const Icon(Icons.edit_note, size: 18),
                label: const Text('Planejamento'),
              ),
              OutlinedButton.icon(
                onPressed: _fichaId == null
                    ? null
                    : () => _abrir(TelaDadosEnviados(fichaId: _fichaId!)),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Ver dados enviados'),
              ),
              OutlinedButton.icon(
                onPressed: () => _abrir(const TelaHistoricoIA()),
                icon: const Icon(Icons.history, size: 18),
                label: const Text('Histórico'),
              ),
              OutlinedButton.icon(
                onPressed: () => _abrir(const TelaAjustesIA()),
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Ajustes'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _anteciparRevisao,
            child: const Align(
              alignment: Alignment.centerLeft,
              child: Text('Mudei de objetivo, dias ou equipamento'),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// CARTÃO DE SUGESTÃO (Aplicar / Ignorar)
// ===========================================================================

class CartaoSugestao extends StatefulWidget {
  const CartaoSugestao({
    super.key,
    required this.sugestao,
    required this.pedido,
    required this.demonstracao,
    required this.aoMudar,
  });

  final Json sugestao;
  final Json pedido;
  final bool demonstracao;
  final Future<void> Function() aoMudar;

  @override
  State<CartaoSugestao> createState() => _CartaoSugestaoState();
}

class _CartaoSugestaoState extends State<CartaoSugestao> {
  bool _ocupado = false;
  String? _impedimento;
  bool _conferido = false;

  Json get _s => widget.sugestao;
  bool get _pendente => _s['estado'] == 'pendente';
  bool get _aplicavel => acoesAplicaveis.contains(_s['acao']);

  @override
  void initState() {
    super.initState();
    _conferir();
  }

  @override
  void didUpdateWidget(CartaoSugestao antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.sugestao['chave'] != widget.sugestao['chave'] ||
        antigo.sugestao['estado'] != widget.sugestao['estado']) {
      _conferir();
    }
  }

  /// Antes de oferecer "Aplicar", confere se a ficha ainda tem o valor
  /// analisado. Se mudou, só resta ignorar.
  Future<void> _conferir() async {
    if (!_pendente || !_aplicavel) {
      if (mounted) setState(() => _conferido = true);
      return;
    }
    try {
      final motivo = await Banco.instancia.motivoNaoAplicavel(_s);
      if (!mounted) return;
      setState(() {
        _impedimento = motivo;
        _conferido = true;
      });
    } catch (_) {
      if (mounted) setState(() => _conferido = true);
    }
  }

  Future<void> _aplicar() async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      final r = await Banco.instancia.aplicarSugestao(_s['chave'] as String);
      if (!mounted) return;
      final texto = r['jaAplicada'] == true
          ? 'Esta sugestão já tinha sido aplicada.'
          : r['destino'] == 'ficha'
              ? 'Séries atualizadas na ficha. Sincronize para enviar ao relógio.'
              : _s['acao'] == 'sugerir_carga'
                  ? 'Carga guardada como sugestão para a próxima sessão.'
                  : 'Planejamento atualizado.';
      _aviso(context, texto);
    } catch (e) {
      if (mounted) _aviso(context, _msg(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
      await widget.aoMudar();
    }
  }

  Future<void> _ignorar() async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await Banco.instancia.ignorarSugestao(_s['chave'] as String);
    } catch (e) {
      if (mounted) _aviso(context, _msg(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
      await widget.aoMudar();
    }
  }

  String? _nomeExercicio() {
    final id = _s['exercicioId'];
    for (final e in (widget.pedido['exercicios'] as List? ?? const [])) {
      if (e is Map && e['exercicioId'] == id) return '${e['nome']}';
    }
    return null;
  }

  /// Os números do histórico vêm do que o celular calculou (pedido), não do
  /// texto da IA: assim dá para conferir.
  Widget _evidencia(Map ev) {
    String? registro;
    for (final e in (widget.pedido['exercicios'] as List? ?? const [])) {
      if (e is! Map || e['exercicioId'] != ev['exercicioId']) continue;
      for (final s in (e['sessoes'] as List? ?? const [])) {
        if (s is! Map || s['sessaoId'] != ev['sessaoId']) continue;
        final series = s['series'];
        if (series is List && series.isNotEmpty) {
          final reps = series.map((x) => '${(x as Map)['reps']}').join('/');
          final carga = (series.last as Map)['cargaKg'];
          final rir = s['rirUltimaSerie'];
          registro = '${_dataIso('${s['data']}')} · $reps reps'
              '${carga is num ? ' · ${fmtNum(carga)} kg' : ''}'
              ' · esforço da última série: '
              '${rir == 'desconhecido' ? 'não informado' : (rir == 'nao_sei' ? 'não sei' : rir)}';
        } else {
          registro = '${_dataIso('${s['data']}')} · sem detalhe das séries';
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${ev['texto']}', style: const TextStyle(fontSize: 13)),
          if (registro != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Registro: $registro',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _estadoFinal() {
    final estado = _s['estado'];
    final texto = estado == 'aceita'
        ? 'Aplicada'
        : estado == 'obsoleta'
            ? 'Obsoleta: a ficha mudou depois da análise'
            : (_aplicavel ? 'Ignorada' : 'Dispensada');
    final cor = estado == 'aceita' ? Theme.of(context).colorScheme.primary : Colors.white54;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Icon(estado == 'aceita' ? Icons.check_circle : Icons.remove_circle_outline,
              size: 18, color: cor),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: TextStyle(color: cor, fontSize: 13))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final acao = '${_s['acao']}';
    final nomeEx = _nomeExercicio();
    final evidencias = (_s['evidencia'] as List? ?? const []).cast<Map>();

    return CartaoVisual(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconeVisual(_iconeAcao[acao] ?? Icons.lightbulb_outline, tamanho: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    rotuloVisual(
                      context,
                      '${_nomeAcao[acao] ?? acao}${nomeEx == null ? '' : ' · $nomeEx'}',
                      destaque: true,
                    ),
                    const SizedBox(height: 4),
                    Text('${_s['titulo']}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('${_s['motivo']}', style: const TextStyle(color: Colors.white70)),
          if (evidencias.isNotEmpty) ...[
            const SizedBox(height: 12),
            rotuloVisual(context, 'Evidência do histórico'),
            for (final ev in evidencias) _evidencia(ev),
          ],
          if (acao == 'sugerir_carga')
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Sugestão para a próxima sessão. O relógio mostra a última '
                'carga que você usou; o novo valor fica guardado no celular.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              _Etiqueta('Confiança ${_s['confianca']}'),
              if (widget.demonstracao) const _Etiqueta('Demonstração'),
            ],
          ),
          if (!_pendente)
            _estadoFinal()
          else ...[
            if (_impedimento != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '$_impedimento Para aplicar, gere uma nova avaliação.',
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                ),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _ocupado ? null : _ignorar,
                    child: Text(_aplicavel ? 'Ignorar' : 'Entendi'),
                  ),
                ),
                if (_aplicavel) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          (_ocupado || !_conferido || _impedimento != null)
                              ? null
                              : _aplicar,
                      child: _ocupado
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : const Text('Aplicar'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(texto, style: const TextStyle(fontSize: 11, color: Colors.white70)),
    );
  }
}

// ===========================================================================
// DETALHE DE UMA AVALIAÇÃO
// ===========================================================================

class TelaAvaliacaoIA extends StatefulWidget {
  const TelaAvaliacaoIA({super.key, required this.avaliacaoId});

  final String avaliacaoId;

  @override
  State<TelaAvaliacaoIA> createState() => _TelaAvaliacaoIAState();
}

class _TelaAvaliacaoIAState extends State<TelaAvaliacaoIA> {
  Json? _avaliacao;
  List<Json> _sugestoes = [];
  bool _carregando = true;
  bool _tentando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final a = await Banco.instancia.obterAvaliacao(widget.avaliacaoId);
      final s = await Banco.instancia.listarSugestoes(avaliacaoId: widget.avaliacaoId);
      if (!mounted) return;
      setState(() {
        _avaliacao = a;
        _sugestoes = s;
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

  Future<void> _tentarDeNovo() async {
    final a = _avaliacao;
    if (a == null || _tentando) return;
    setState(() => _tentando = true);
    try {
      await ServicoIA.avaliar(
        tipo: a['tipo'] as String,
        fichaId: a['fichaId'] as String?,
        avaliacaoId: a['id'] as String,
      );
    } on ErroIA catch (e) {
      if (mounted) _aviso(context, e.mensagem);
    } catch (e) {
      if (mounted) _aviso(context, _msg(e));
    } finally {
      if (mounted) setState(() => _tentando = false);
      await _carregar();
    }
  }

  Widget _secao(String titulo, Widget filho) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [tituloVisual(context, titulo), filho],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final a = _avaliacao;

    return Scaffold(
      appBar: AppBar(
        title: Text(a == null ? 'Avaliação' : (_nomeTipo[a['tipo']] ?? 'Avaliação')),
      ),
      body: SafeArea(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : (_erro != null || a == null)
                ? Center(child: Text(_erro ?? 'Erro'))
                : _corpo(a),
      ),
    );
  }

  Widget _corpo(Json a) {
    final resposta = a['resposta'] == null ? null : Json.from(a['resposta'] as Map);
    final pedido = Json.from(a['pedido'] as Map);
    final demo = a['demonstracao'] == true;
    final estado = a['estado'];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        CartaoVisual(
          destaque: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              rotuloVisual(
                context,
                '${_nomeTipo[a['tipo']]} · ${_dataMs(a['criado'] as int)}',
                destaque: true,
              ),
              const SizedBox(height: 10),
              if (estado == 'concluida' && resposta != null)
                Text('${resposta['resumo']}', style: const TextStyle(fontSize: 15))
              else if (estado == 'erro')
                Text('${a['erro']}',
                    style: const TextStyle(color: Colors.redAccent))
              else
                const Text('Esta avaliação não terminou.'),
              if (demo)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: _Etiqueta('Demonstração: regras locais, sem IA'),
                ),
            ],
          ),
        ),
        if (estado != 'concluida') ...[
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _tentando ? null : _tentarDeNovo,
            icon: _tentando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(Icons.refresh),
            label: const Text('Tentar de novo'),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Você continua treinando normalmente e o histórico local segue '
              'disponível. Tentar de novo reaproveita o mesmo pedido.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ],
        if (resposta != null) ...[
          if (a['tipo'] == 'montar')
            _secao(
              'Rascunho',
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => TelaRascunho(avaliacaoId: a['id'] as String)),
                ),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Revisar o rascunho'),
              ),
            ),
          if (_sugestoes.isNotEmpty)
            _secao(
              'Sugestões',
              Column(
                children: [
                  for (final s in _sugestoes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: CartaoSugestao(
                        key: ValueKey(s['chave']),
                        sugestao: s,
                        pedido: pedido,
                        demonstracao: demo,
                        aoMudar: _carregar,
                      ),
                    ),
                ],
              ),
            ),
          if ((resposta['perguntas'] as List).isNotEmpty)
            _secao(
              'Perguntas da IA',
              CartaoVisual(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final p in (resposta['perguntas'] as List))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text('• $p'),
                      ),
                    const SizedBox(height: 6),
                    const Text(
                      'Responda registrando o esforço dos treinos ou ajustando '
                      'o planejamento do exercício.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          if (resposta['explicacao'] is Map)
            _secao('Como ler isto', _Explicacao(Json.from(resposta['explicacao'] as Map))),
        ],
        _secao(
          'Dados usados',
          CartaoVisual(
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Ver o que foi enviado'),
                children: [
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert(pedido),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Explicacao extends StatelessWidget {
  const _Explicacao(this.dados);

  final Json dados;

  static const _titulos = {
    'volumeEDescanso': 'Volume e descanso',
    'faixaReps': 'Faixa de repetições',
    'encerrarSerie': 'Quando encerrar a série',
    'progressao': 'Quando subir a carga',
    'forca': 'Trabalho de força',
  };

  @override
  Widget build(BuildContext context) {
    return CartaoVisual(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in _titulos.entries)
            if (dados[e.key] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    rotuloVisual(context, e.value),
                    const SizedBox(height: 4),
                    Text('${dados[e.key]}',
                        style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

// ===========================================================================
// HISTÓRICO DE AVALIAÇÕES
// ===========================================================================

class TelaHistoricoIA extends StatefulWidget {
  const TelaHistoricoIA({super.key});

  @override
  State<TelaHistoricoIA> createState() => _TelaHistoricoIAState();
}

class _TelaHistoricoIAState extends State<TelaHistoricoIA> {
  List<Json> _lista = [];
  Map<String, int> _pendentes = {};
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final lista = await Banco.instancia.listarAvaliacoes();
      final sug = await Banco.instancia.listarSugestoes(estado: 'pendente');
      final cont = <String, int>{};
      for (final s in sug) {
        cont[s['avaliacaoId'] as String] = (cont[s['avaliacaoId']] ?? 0) + 1;
      }
      if (!mounted) return;
      setState(() {
        _lista = lista;
        _pendentes = cont;
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

  Future<void> _abrir(Json a) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => a['tipo'] == 'montar' && a['estado'] == 'concluida'
            ? TelaRascunho(avaliacaoId: a['id'] as String)
            : TelaAvaliacaoIA(avaliacaoId: a['id'] as String),
      ),
    );
    if (mounted) await _carregar();
  }

  Future<void> _excluir(Json a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar esta avaliação?'),
        content: const Text(
          'Some do histórico, junto com as sugestões dela. Mudanças já '
          'aplicadas na ficha continuam valendo.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true) return;
    await Banco.instancia.excluirAvaliacao(a['id'] as String);
    if (mounted) await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico da IA')),
      body: SafeArea(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
                ? Center(child: Text(_erro!))
                : _lista.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('Nenhuma avaliação ainda.',
                              style: TextStyle(color: Colors.white70)),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        children: [
                          for (final a in _lista)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: CartaoVisual(
                                padding: EdgeInsets.zero,
                                child: ListTile(
                                  onTap: () => _abrir(a),
                                  title: Text(_nomeTipo[a['tipo']] ?? '${a['tipo']}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  subtitle: Text(
                                    '${_dataMs(a['criado'] as int)} · '
                                    '${a['estado'] == 'concluida' ? 'concluída' : (a['estado'] == 'erro' ? 'com erro' : 'não terminou')}'
                                    '${a['demonstracao'] == true ? ' · demonstração' : ''}'
                                    '${(_pendentes[a['id']] ?? 0) > 0 ? ' · ${_pendentes[a['id']]} p/ decidir' : ''}',
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Apagar',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _excluir(a),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
      ),
    );
  }
}

// ===========================================================================
// VER DADOS QUE SERÃO ENVIADOS
// ===========================================================================

class TelaDadosEnviados extends StatefulWidget {
  const TelaDadosEnviados({super.key, required this.fichaId});

  final String fichaId;

  @override
  State<TelaDadosEnviados> createState() => _TelaDadosEnviadosState();
}

class _TelaDadosEnviadosState extends State<TelaDadosEnviados> {
  String _tipo = 'semana';
  String? _json;
  String? _erro;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final p = await ServicoIA.prever(tipo: _tipo, fichaId: widget.fichaId);
      if (!mounted) return;
      setState(() {
        _json = const JsonEncoder.withIndent('  ').convert(p);
        _erro = null;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dados enviados')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const CartaoVisual(
              child: Text(
                'Este é exatamente o resumo que o celular calcula e enviaria. '
                'Não são enviados: fotos, nome, data de nascimento, gravações '
                'do sensor nem observações de saúde. Nada sai daqui até você '
                'tocar em uma avaliação.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'semana', label: Text('Semana')),
                ButtonSegment(value: 'revisao', label: Text('Revisão')),
              ],
              selected: {_tipo},
              onSelectionChanged: (s) {
                _tipo = s.first;
                _carregar();
              },
            ),
            const SizedBox(height: 12),
            if (_carregando)
              const Center(child: CircularProgressIndicator())
            else if (_erro != null)
              Text(_erro!, style: const TextStyle(color: Colors.redAccent))
            else
              CartaoVisual(
                child: SelectableText(
                  _json ?? '',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}