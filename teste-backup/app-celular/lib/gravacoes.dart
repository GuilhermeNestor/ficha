import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'banco.dart';

String checksumGravacao(String texto) {
  var h = 2166136261;
  for (final c in texto.codeUnits) {
    h = ((h ^ c) * 16777619) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

class Gravacoes {
  static final instancia = Gravacoes();

  int _inteiro(dynamic v, int min, int max) {
    if (v is! int || v < min || v > max) throw Exception('Número da gravação inválido.');
    return v;
  }

  void _validar(Json g, String id) {
    if (g['versao'] != 1 || g['id'] != id || g['unidade'] != 'cm/s2') {
      throw Exception('Formato da gravação inválido.');
    }
    for (final campo in ['exercicioNome', 'exercicioId', 'fichaNome', 'detector']) {
      if (g[campo] is! String || (g[campo] as String).length > 200) {
        throw Exception('Metadados inválidos.');
      }
    }
    _inteiro(g['inicio'], 0, 8640000000000000);
    final amostras = g['amostras'];
    if (amostras is! List || amostras.isEmpty || amostras.length > 6000) {
      throw Exception('Lista de amostras inválida.');
    }
    var anterior = -1;
    for (final a in amostras) {
      if (a is! List || a.length != 4) throw Exception('Amostra inválida.');
      final t = _inteiro(a[0], 0, 90000);
      if (t <= anterior) throw Exception('Tempos fora de ordem.');
      anterior = t;
      for (var i = 1; i < 4; i++) { _inteiro(a[i], -1000000, 1000000); }
    }
    if (g['repsReais'] != null) _inteiro(g['repsReais'], 0, 300);
    if (g['eventos'] is! List || (g['eventos'] as List).length > 10000) {
      throw Exception('Eventos inválidos.');
    }
    for (final e in g['eventos'] as List) {
      if (e is! Map || e['tipo'] is! String) throw Exception('Evento inválido.');
      _inteiro(e['t'], 0, 86400000);
    }
  }

  Future<Json> receberParte(Json p) async {
    final id = p['id'], hash = p['hash'], conteudo = p['conteudo'];
    if (id is! String || !RegExp(r'^coleta_[a-zA-Z0-9_]+$').hasMatch(id) || id.length > 100 ||
        hash is! String || !RegExp(r'^[0-9a-f]{8}$').hasMatch(hash) || conteudo is! String ||
        conteudo.isEmpty || conteudo.length > 1024) throw Exception('Bloco inválido.');
    final total = _inteiro(p['total'], 1, 400);
    final indice = _inteiro(p['indice'], 0, total - 1);
    final tamanho = _inteiro(p['tamanho'], 1, 400 * 1024);
    if ((tamanho + 1023) ~/ 1024 != total ||
        conteudo.length != (indice == total - 1 ? tamanho - indice * 1024 : 1024)) {
      throw Exception('Tamanho do bloco inconsistente.');
    }
    final db = await Banco.instancia.database;
    return db.transaction((tx) async {
      Json ack(bool completa) => {'versao':1,'id':id,'hash':hash,'indice':indice,
        'completa':completa,'persistido':completa};
      final salvos = await tx.query('gravacoes', where:'id = ?', whereArgs:[id]);
      if (salvos.isNotEmpty) {
        if (salvos.single['hash'] != hash || (salvos.single['conteudo'] as String).length != tamanho) {
          throw Exception('Mesmo ID com gravação diferente.');
        }
        final original = salvos.single['conteudo'] as String;
        if (original.substring(indice * 1024, indice * 1024 + conteudo.length) != conteudo) {
          throw Exception('Bloco diverge da gravação salva.');
        }
        return ack(true);
      }
      final partes = await tx.query('gravacao_partes', where:'id = ?', whereArgs:[id], orderBy:'indice ASC');
      for (final parte in partes) {
        if (parte['hash'] != hash || parte['total'] != total || parte['tamanho'] != tamanho) {
          throw Exception('Blocos de versões diferentes.');
        }
        if (parte['indice'] == indice && parte['conteudo'] != conteudo) {
          throw Exception('Bloco repetido com outro conteúdo.');
        }
      }
      await tx.insert('gravacao_partes', {'id':id,'indice':indice,'total':total,
        'tamanho':tamanho,'hash':hash,'conteudo':conteudo}, conflictAlgorithm: ConflictAlgorithm.ignore);
      final todas = await tx.query('gravacao_partes', where:'id = ?', whereArgs:[id], orderBy:'indice ASC');
      if (todas.length != total) return ack(false);
      final texto = todas.map((r)=>r['conteudo'] as String).join();
      if (texto.length != tamanho || checksumGravacao(texto) != hash) {
        throw Exception('Integridade da gravação inválida.');
      }
      final valor = jsonDecode(texto);
      if (valor is! Map) throw Exception('Gravação inválida.');
      final g = Json.from(valor); _validar(g,id);
      await tx.insert('gravacoes', {'id':id,'inicio':g['inicio'],'nome':g['exercicioNome'],
        'hash':hash,'conteudo':texto,'rotulos':jsonEncode({'repsReais':g['repsReais'],
        'observacao':'','repsAtipicas':[],'temposReais':[]})});
      await tx.delete('gravacao_partes', where:'id = ?', whereArgs:[id]);
      return ack(true);
    });
  }

  Future<List<Json>> listar() async {
    final db = await Banco.instancia.database;
    final rows = await db.query('gravacoes', orderBy:'inicio DESC');
    return rows.map((r) => {...Json.from(jsonDecode(r['conteudo'] as String) as Map),
      'rotulos':Json.from(jsonDecode(r['rotulos'] as String) as Map)}).toList();
  }

  Future<void> rotular(String id, int reais, String observacao, List<int> atipicas) async {
    _inteiro(reais,0,300);
    if (observacao.length > 2000 || atipicas.any((n)=>n<1||n>reais)) {
      throw Exception('Observação ou número de repetição inválido.');
    }
    final db = await Banco.instancia.database;
    await db.update('gravacoes', {'rotulos':jsonEncode({'repsReais':reais,
      'observacao':observacao,'repsAtipicas':atipicas.toSet().toList(),'temposReais':[]})},
      where:'id = ?',whereArgs:[id]);
  }

  Future<String> exportar() async => const JsonEncoder.withIndent('  ').convert({
    'formato':'ficha-treino-coletas','versao':1,'exportadoEm':DateTime.now().toUtc().toIso8601String(),
    'gravacoes':await listar(),
  });
}
