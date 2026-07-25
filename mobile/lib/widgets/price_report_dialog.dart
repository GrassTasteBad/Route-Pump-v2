import 'package:flutter/material.dart';
import '../models/gas_station.dart';

class PriceReportDialog extends StatelessWidget {
  final GasStation station;
  final VoidCallback onStayOnMap;
  final VoidCallback onReportPrices;

  const PriceReportDialog({
    super.key,
    required this.station,
    required this.onStayOnMap,
    required this.onReportPrices,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Arrived!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                Text(
                  '${station.name} – ${station.branch}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.normal),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'You are now inside the station perimeter. Would you like to report current fuel prices?',
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reporting prices helps other motorists find the best deals nearby.',
                    style: TextStyle(fontSize: 11, color: Colors.grey[700], height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onStayOnMap,
          child: Text('Stay on Map', style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w500)),
        ),
        ElevatedButton.icon(
          onPressed: onReportPrices,
          icon: const Icon(Icons.edit_note, size: 16),
          label: const Text('Report Prices', style: TextStyle(fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }
}
