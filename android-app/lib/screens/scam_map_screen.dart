import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../services/api_service.dart';

class HeatmapPoint {
  final double lat;
  final double lng;
  final int count;
  final String? city;

  const HeatmapPoint({
    required this.lat,
    required this.lng,
    required this.count,
    this.city,
  });

  factory HeatmapPoint.fromJson(Map<String, dynamic> json) {
    return HeatmapPoint(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      count: json['count'] as int? ?? 1,
      city: json['city'] as String?,
    );
  }
}

final scamHeatmapProvider =
    StateNotifierProvider<HeatmapNotifier, AsyncValue<List<HeatmapPoint>>>(
  (ref) => HeatmapNotifier(),
);

class HeatmapNotifier
    extends StateNotifier<AsyncValue<List<HeatmapPoint>>> {
  HeatmapNotifier() : super(const AsyncValue.loading()) {
    _fetch();
    _startTimer();
  }

  Timer? _timer;
  final _api = ApiService();

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _fetch());
  }

  Future<void> _fetch() async {
    state = const AsyncValue.loading();
    try {
      final data = await _api.getScamHeatmap();
      state = AsyncValue.data(data);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void refresh() => _fetch();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class ScamMapScreen extends ConsumerWidget {
  const ScamMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heatmap = ref.watch(scamHeatmapProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scam Map', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(scamHeatmapProvider.notifier).refresh(),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(20.5937, 78.9629), // Center of India
              initialZoom: 4.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.zentra',
              ),
              heatmap.when(
                data: (points) => CircleLayer(
                  circles: points.map((p) {
                    final radius = _radiusForCount(p.count);
                    return CircleMarker(
                      point: LatLng(p.lat, p.lng),
                      radius: radius,
                      color: Colors.red.withOpacity(0.35),
                      borderColor: Colors.red.withOpacity(0.7),
                      borderStrokeWidth: 1.5,
                      useRadiusInMeter: true,
                    );
                  }).toList(),
                ),
                loading: () => const CircleLayer(circles: []),
                error: (_, __) => const CircleLayer(circles: []),
              ),
            ],
          ),

          // Legend
          Positioned(
            bottom: 24,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Scam Hotspots',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  _LegendItem(color: Colors.red.withOpacity(0.3), label: 'Low'),
                  _LegendItem(color: Colors.red.withOpacity(0.5), label: 'Medium'),
                  _LegendItem(color: Colors.red.withOpacity(0.8), label: 'High'),
                ],
              ),
            ),
          ),

          // Loading overlay
          if (heatmap.isLoading)
            const Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Updating map...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _radiusForCount(int count) {
    if (count >= 50) return 50000;
    if (count >= 20) return 35000;
    if (count >= 10) return 25000;
    return 15000;
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.red.withOpacity(0.7)),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}