import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'banco.dart';
import 'gravacoes.dart';

// Deve ser igual ao token no app-side/index.js desta instalação.
const _token = 'ficha_9a7e2b46d8104f5b8196e032a67c43fd';

class Ponte extends ChangeNotifier {
  Ponte._();
  static final instancia = Ponte._();
  HttpServer? _servidor;
  Future<void>? _abertura;
  String status = 'Iniciando sincronização…';
  int resultadosRecebidos = 0;
  bool get ativa => _servidor != null;

  Future<void> iniciar() async {
    if (ativa) return;
    if (_abertura != null) return _abertura!;
    final abertura = _abrir();
    _abertura = abertura;
    try {
      await abertura;
    } finally {
      _abertura = null;
    }
  }

  void _informar(String texto) {
    status = texto;
    notifyListeners();
  }

  Future<void> _abrir() async {
    try {
      await Banco.instancia.database;
      final servidor = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        8765,
      );
      _servidor = servidor;
      servidor.listen(
        (pedido) {
          unawaited(_atender(pedido));
        },
        onError: (Object erro) {
          _informar('Falha na conexão: $erro');
        },
        onDone: () {
          if (identical(_servidor, servidor)) {
            _servidor = null;
            _informar('Conexão encerrada. Toque em Sincronizar.');
          }
        },
      );
      _informar('Pronto. Toque em SINCRONIZAR no relógio.');
    } catch (erro) {
      _informar('Não foi possível iniciar: $erro');
      rethrow;
    }
  }

  Future<Json> _ler(HttpRequest pedido) async {
    final bytes = <int>[];
    await for (final parte in pedido) {
      if (bytes.length + parte.length > 512 * 1024) {
        throw Exception('Pedido muito grande.');
      }
      bytes.addAll(parte);
    }
    final valor = jsonDecode(utf8.decode(bytes));
    if (valor is! Map) throw Exception('Pedido inválido.');
    return Json.from(valor);
  }

  Future<void> _atender(HttpRequest pedido) async {
    String? requestId;
    Json dados;
    var codigo = HttpStatus.ok;
    try {
      if (pedido.method != 'POST' || pedido.uri.path != '/rpc') {
        codigo = HttpStatus.notFound;
        throw Exception('Rota inválida.');
      }
      if (pedido.headers.value('X-Ficha-Token') != _token) {
        codigo = HttpStatus.forbidden;
        throw Exception('Código de conexão inválido. Atualize os dois apps.');
      }
      final envelope = await _ler(pedido).timeout(const Duration(seconds: 6));
      final id = envelope['requestId'];
      if (envelope['versao'] != 1 ||
          id is! String ||
          id.isEmpty ||
          id.length > 100 ||
          envelope['params'] is! Map) {
        throw Exception('Formato da mensagem inválido.');
      }
      requestId = id;
      final params = Json.from(envelope['params'] as Map);
      if (params['versao'] != 1) throw Exception('Protocolo incompatível.');
      switch (envelope['method']) {
        case 'gravacao.parte':
          dados = await Gravacoes.instancia.receberParte(params);
          if (dados['completa'] == true) _informar('Gravação salva no celular.');
          break;
        case 'resultado.salvar':
          if (params['resultado'] is! Map) {
            throw Exception('Resultado ausente.');
          }
          // O ACK só é criado após o commit, inclusive em reenvios.
          dados = await Banco.instancia.salvarResultado(
            Json.from(params['resultado'] as Map),
          );
          resultadosRecebidos++;
          _informar('Resultado salvo no celular. Enviando confirmação.');
          break;
        case 'fichas.obter':
          final revisao = params['revisao'];
          if (revisao is! int || revisao < 0) {
            throw Exception('Revisão do relógio inválida.');
          }
          final pacote = await Banco.instancia.exportarFichas();
          if (revisao > (pacote['revisao'] as int)) {
            throw Exception(
              'O relógio tem uma revisão mais recente. '
              'Não substituímos as fichas.',
            );
          }
          // Enviar inclusive na mesma revisão permite ao relógio
          // detectar conteúdo diferente com a mesma revisão.
          dados = {'versao': 1, 'pacote': pacote};
          _informar('Fichas disponibilizadas. Confira a conclusão no relógio.');
          break;
        default:
          throw Exception('Operação desconhecida.');
      }
    } catch (erro) {
      if (codigo == HttpStatus.ok) codigo = HttpStatus.badRequest;
      final mensagem = erro.toString().replaceFirst('Exception: ', '');
      dados = {'erro': mensagem};
      _informar('Sincronização: $mensagem');
    }
    try {
      pedido.response.statusCode = codigo;
      pedido.response.headers.contentType = ContentType.json;
      pedido.response.headers.set('Cache-Control', 'no-store');
      pedido.response.write(
        jsonEncode({
          'app': 'ficha-treino',
          'requestId': requestId,
          'dados': dados,
        }),
      );
      await pedido.response.close();
    } catch (_) {
      // Se o commit já ocorreu, o reenvio recupera a confirmação.
      _informar('Resposta interrompida. Sincronize novamente no relógio.');
    }
  }
}
