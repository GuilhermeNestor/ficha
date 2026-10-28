import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'banco.dart';
import 'gravacoes.dart';
import 'ponte.dart';

class TelaGravacoes extends StatefulWidget {
  const TelaGravacoes({super.key});
  @override
  State<TelaGravacoes> createState() => _TelaGravacoesState();
}
class _TelaGravacoesState extends State<TelaGravacoes> {
  List<Json> _lista = [];
  bool _exportando = false;
  String? _erro;
  int _consulta = 0;
  @override
  void initState() { super.initState(); Ponte.instancia.addListener(_carregar); _carregar(); }
  @override
  void dispose() { Ponte.instancia.removeListener(_carregar); super.dispose(); }
  Future<void> _carregar() async {
    final consulta = ++_consulta;
    try {
      final lista = await Gravacoes.instancia.listar();
      if (mounted && consulta == _consulta) setState(() { _lista=lista; _erro=null; });
    } catch(e) { if(mounted) setState(()=>_erro=e.toString()); }
  }
  Future<void> _exportar() async {
    setState(()=>_exportando=true);
    try {
      final texto = await Gravacoes.instancia.exportar();
      final nome = 'gravacoes_treino_${DateTime.now().millisecondsSinceEpoch}.json';
      await SharePlus.instance.share(ShareParams(
        title:'Gravações dos exercícios',
        files:[XFile.fromData(Uint8List.fromList(utf8.encode(texto)),mimeType:'application/json')],
        fileNameOverrides:[nome],
      ));
    } catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e'))); }
    finally {if(mounted)setState(()=>_exportando=false);}
  }
  Future<void> _editar(Json g) async {
    final rotulos = Json.from(g['rotulos'] as Map);
    final reais = TextEditingController(text:(rotulos['repsReais']??g['repsReais']??'').toString());
    final obs = TextEditingController(text:(rotulos['observacao']??'').toString());
    final atipicas = TextEditingController(text:((rotulos['repsAtipicas']??[]) as List).join(', '));
    final salvar = await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
      title:Text(g['exercicioNome'] as String),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:reais,keyboardType:TextInputType.number,
          decoration:const InputDecoration(labelText:'Repetições reais')),
        const SizedBox(height:12),
        TextField(controller:atipicas,decoration:const InputDecoration(
          labelText:'Repetições diferentes do padrão',hintText:'Exemplo: 4, 8')),
        const SizedBox(height:12),
        TextField(controller:obs,maxLines:3,decoration:const InputDecoration(
          labelText:'Observações',hintText:'Ex.: balancei o braço após terminar; pulso esquerdo.')),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancelar')),
        FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Salvar'))],
    ));
    try {
      if(salvar==true){
        final n=int.tryParse(reais.text.trim());
        if(n==null)throw Exception('Informe o total real.');
        final partes=atipicas.text.split(',').map((s)=>s.trim()).where((s)=>s.isNotEmpty);
        final lista=partes.map((s){final v=int.tryParse(s);if(v==null)throw Exception('Use números separados por vírgula.');return v;}).toList();
        await Gravacoes.instancia.rotular(g['id'] as String,n,obs.text.trim(),lista);
        await _carregar();
      }
    } catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}
    finally {reais.dispose();obs.dispose();atipicas.dispose();}
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(title:const Text('Gravações de teste'),actions:[
      IconButton(onPressed:_carregar,icon:const Icon(Icons.refresh),tooltip:'Atualizar'),
    ]),
    body:Column(children:[
      const Padding(padding:EdgeInsets.all(16),child:Text(
        'Grave no relógio, informe o total real e sincronize. '
        'Toque em uma gravação para adicionar observações. '
        'O arquivo exportado contém os sinais do acelerômetro.')),
      if(_erro!=null)Padding(padding:const EdgeInsets.all(16),child:Text(_erro!)),
      Expanded(child:_lista.isEmpty?const Center(child:Text('Nenhuma gravação recebida.')):
        ListView.builder(itemCount:_lista.length,itemBuilder:(context,i){
          final g=_lista[i]; final rotulos=Json.from(g['rotulos'] as Map);
          final amostras=g['amostras'] as List;
          final data=DateTime.fromMillisecondsSinceEpoch(g['inicio'] as int);
          return ListTile(onTap:()=>_editar(g),leading:const Icon(Icons.sensors),
            title:Text('${g['exercicioNome']} · série ${g['serie']}'),
            subtitle:Text('${data.day}/${data.month} · ${g['carga']} kg\n'
              'Reais: ${rotulos['repsReais']??"?"} · detector: ${g['repsDetectadasSerie']??g['repsDetectadas']??"?"}\n'
              '${amostras.length} leituras'
              '${g['truncada']==true?" · PARCIAL":""}'
              '${g['interrompida']==true?" · INTERROMPIDA":""}'),
            isThreeLine:true,trailing:const Icon(Icons.edit_outlined));
        })),
      SafeArea(child:Padding(padding:const EdgeInsets.all(16),child:SizedBox(width:double.infinity,
        child:FilledButton.icon(onPressed:_lista.isEmpty||_exportando?null:_exportar,
          icon:const Icon(Icons.share),label:Text(_exportando?'Preparando…':'Exportar todas (.json)'))))),
    ]),
  );
}
