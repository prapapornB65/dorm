import 'package:flutter/material.dart';
import '../../models/meter.dart';

class MeterCard extends StatelessWidget {
  final Meter m;
  final VoidCallback? onTap;
  final VoidCallback? onBuy;
  final VoidCallback? onToggle;

  const MeterCard({super.key, required this.m, this.onTap, this.onBuy, this.onToggle});

  @override
  Widget build(BuildContext context) {
    final state = m.isCut
      ? 'CUT'
      : (m.thresholdCritical!=null && m.creditKwh <= m.thresholdCritical!) ? 'CRITICAL'
      : (m.thresholdLow!=null && m.creditKwh <= m.thresholdLow!) ? 'LOW'
      : 'OK';

    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(m.name ?? m.deviceId),
        subtitle: Text('เครดิต: ${m.creditKwh.toStringAsFixed(2)} kWh'),
        trailing: Wrap(spacing: 8, children: [
          Chip(label: Text(state)),
          if (onBuy   != null) IconButton(icon: const Icon(Icons.add_shopping_cart), onPressed: onBuy),
          if (onToggle!= null) IconButton(icon: Icon(m.isCut ? Icons.power_off : Icons.power), onPressed: onToggle),
        ]),
      ),
    );
  }
}
