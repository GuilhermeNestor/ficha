import 'package:flutter/material.dart';

class CartaoVisual extends StatelessWidget {
  const CartaoVisual({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.destaque = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: destaque ? null : cores.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: destaque
              ? cores.primary.withAlpha(70)
              : Colors.white10,
        ),
        gradient: destaque
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    cores.primary.withAlpha(45),
                    cores.surface,
                  ),
                  cores.surface,
                ],
              )
            : null,
      ),
      child: child,
    );
  }
}

Widget rotuloVisual(
  BuildContext context,
  String texto, {
  bool destaque = false,
}) {
  return Text(
    texto.toUpperCase(),
    style: TextStyle(
      color: destaque
          ? Theme.of(context).colorScheme.primary
          : Colors.white54,
      fontSize: 11,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w700,
    ),
  );
}

Widget tituloVisual(
  BuildContext context,
  String texto, {
  Widget? acao,
}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            texto,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        if (acao != null) acao,
      ],
    ),
  );
}

class IconeVisual extends StatelessWidget {
  const IconeVisual(
    this.icone, {
    super.key,
    this.tamanho = 46,
  });

  final IconData icone;
  final double tamanho;

  @override
  Widget build(BuildContext context) {
    final cor = Theme.of(context).colorScheme.primary;

    return Container(
      width: tamanho,
      height: tamanho,
      decoration: BoxDecoration(
        color: cor.withAlpha(24),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        icone,
        color: cor,
        size: tamanho * .48,
      ),
    );
  }
}

class MetricaVisual extends StatelessWidget {
  const MetricaVisual(
    this.rotulo,
    this.valor,
    this.icone, {
    super.key,
  });

  final String rotulo;
  final String valor;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          Colors.black26,
          cores.surface,
        ),
        border: Border.all(color: Colors.white10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: cores.primary, size: 19),
          const SizedBox(height: 9),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            rotulo,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}