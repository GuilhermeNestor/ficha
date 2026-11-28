import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'banco.dart';
import 'ia_nucleo.dart';

// Cliente do Personal IA: Flutter -> API própria (HTTPS) -> Hermes.
// A chave do provedor de IA fica no servidor, nunca no app.
//
// Há dois provedores com a mesma interface:
//  - simulado: regras locais, marcado como DEMONSTRAÇÃO (padrão);
//  - http: chama a sua API quando a URL for configurada.

class ErroIA implements Exception {
  ErroIA(this.mensagem);
  final String mensagem;

  @override
  String toString() => mensagem;
}

abstract class ProvedorIA {
  String get nome;
  bool get demonstracao;

  /// Recebe o pedido e devolve a resposta BRUTA (ainda não validada).
  Future<dynamic> avaliar(Json pedido);
}

class ProvedorSimuladoLocal implements ProvedorIA {
  @override
  String get nome => 'Demonstração (sem IA)';

  @override
  bool get demonstracao => true;

  @override
  Future<dynamic> avaliar(Json pedido) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return ProvedorSimulado.responder(pedido);
  }
}

/// Só HTTPS. HTTP puro apenas para teste local (localhost / emulador).
String? validarUrlIA(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || !u.hasScheme || u.host.isEmpty) return 'URL inválida.';
  if (u.scheme == 'https') return null;
  const locais = ['localhost', '127.0.0.1', '10.0.2.2'];
  if (u.scheme == 'http' && locais.contains(u.host)) return null;
  return 'Use uma URL https:// (http só para localhost).';
}

class ProvedorHttp implements ProvedorIA {
  ProvedorHttp(this.url, this.token);

  final String url;
  final String? token;

  @override
  String get nome => 'Hermes (${Uri.parse(url).host})';

  @override
  bool get demonstracao => false;

  @override
  Future<dynamic> avaliar(Json pedido) async {
    final erroUrl = validarUrlIA(url);
    if (erroUrl != null) throw ErroIA(erroUrl);

    final cliente = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);

    try {
      final req = await cliente.postUrl(Uri.parse(url.trim()));
      req.headers.contentType = ContentType.json;
      // A mesma chave em novas tentativas evita cobrança em dobro.
      req.headers.set('Idempotency-Key', pedido['avaliacaoId'] as String);
      if (token != null && token!.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $token');
      }
      req.write(jsonEncode(pedido));

      final resp = await req.close().timeout(const Duration(seconds: 90));
      final bytes = <int>[];
      await for (final parte in resp) {
        bytes.addAll(parte);
        if (bytes.length > 512 * 1024) {
          throw ErroIA('A resposta da IA veio grande demais.');
        }
      }

      switch (resp.statusCode) {
        case 200:
          break;
        case 401:
        case 403:
          throw ErroIA('Acesso negado pelo servidor. Confira o token.');
        case 409:
          throw ErroIA('Essa avaliação ainda está sendo processada. Tente em instantes.');
        case 429:
          throw ErroIA('Limite de uso atingido. Tente mais tarde.');
        default:
          if (resp.statusCode >= 500) {
            throw ErroIA('O servidor da IA está indisponível (${resp.statusCode}).');
          }
          throw ErroIA('O servidor recusou o pedido (${resp.statusCode}).');
      }

      return jsonDecode(utf8.decode(bytes));
    } on ErroIA {
      rethrow;
    } on SocketException {
      throw ErroIA('Sem conexão com o servidor.');
    } on TimeoutException {
      throw ErroIA('O servidor demorou demais para responder.');
    } on HandshakeException {
      throw ErroIA('Falha de segurança na conexão (certificado).');
    } on FormatException {
      throw ErroIA('O servidor respondeu algo que não é JSON.');
    } finally {
      cliente.close(force: true);
    }
  }
}

class ServicoIA {
  ServicoIA._();

  static final Set<String> _emAndamento = {};

  static Future<ProvedorIA> provedorAtual() async {
    final b = Banco.instancia;
    final url = await b.ajuste('ia_url');
    if ((await b.ajuste('ia_provedor')) == 'http' &&
        url != null &&
        url.isNotEmpty) {
      return ProvedorHttp(url, await b.ajuste('ia_token'));
    }
    return ProvedorSimuladoLocal();
  }

  /// Monta o pedido SEM enviar (para "Ver dados que serão enviados").
  static Future<Json> prever({
    required String tipo,
    String? fichaId,
    Json? respostasMontagem,
  }) {
    return Banco.instancia.montarPedidoIA(
      avaliacaoId: 'previa',
      tipo: tipo,
      fichaId: fichaId,
      respostasMontagem: respostasMontagem,
    );
  }

  /// Executa uma avaliação. Para tentar de novo, passe o mesmo
  /// [avaliacaoId]: ele reaproveita o pedido e a chave de idempotência.
  /// Se a API estiver fora do ar, o erro fica salvo e o app segue normal.
  static Future<Json> avaliar({
    required String tipo,
    String? fichaId,
    Json? respostasMontagem,
    String? avaliacaoId,
  }) async {
    final banco = Banco.instancia;
    final id = avaliacaoId ?? novoId('aval');

    if (!_emAndamento.add(id)) {
      throw ErroIA('Esta avaliação já está em andamento.');
    }

    try {
      final provedor = await provedorAtual();

      var avaliacao = await banco.obterAvaliacao(id);
      if (avaliacao == null) {
        final pedido = await banco.montarPedidoIA(
          avaliacaoId: id,
          tipo: tipo,
          fichaId: fichaId,
          respostasMontagem: respostasMontagem,
        );

        if (tipo == 'semana') {
          final n = (pedido['periodo'] as Map)['sessoesNaJanela'] as int;
          if (n == 0) {
            throw ErroIA('Nenhum treino desta ficha nos últimos 7 dias.');
          }
        }
        if (tipo == 'montar' && (pedido['faltando'] as List).isNotEmpty) {
          throw ErroIA('Faltam respostas para montar a ficha.');
        }

        avaliacao = await banco.criarAvaliacao(
          id: id,
          tipo: tipo,
          fichaId: fichaId,
          pedido: pedido,
          demonstracao: provedor.demonstracao,
        );
      }

      if (avaliacao['estado'] == 'concluida') return avaliacao;
      await banco.reabrirAvaliacao(id);

      final pedido = Json.from(avaliacao['pedido'] as Map);

      try {
        final bruta = await provedor.avaliar(pedido);
        final valida = ValidacaoIA.validarResposta(bruta, pedido);
        if (provedor.demonstracao) valida['demonstracao'] = true;
        await banco.concluirAvaliacao(id, valida);
      } on RespostaInvalida catch (e) {
        await banco.falharAvaliacao(id, e.toString());
        throw ErroIA(e.toString());
      } on ErroIA catch (e) {
        await banco.falharAvaliacao(id, e.mensagem);
        rethrow;
      } catch (e) {
        final msg = 'Não foi possível avaliar agora: '
            '${e.toString().replaceFirst('Exception: ', '')}';
        await banco.falharAvaliacao(id, msg);
        throw ErroIA(msg);
      }

      return (await banco.obterAvaliacao(id))!;
    } finally {
      _emAndamento.remove(id);
    }
  }
}