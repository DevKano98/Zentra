import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme.dart';
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

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text('Scam Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                ref.read(scamHeatmapProvider.notifier).refresh(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // Map
          FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(20.5937, 78.9629),
              initialZoom: 4.5,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.zentra',
              ),
              heatmap.when(
                data: (points) => CircleLayer(
                  circles: points.map((p) {
                    final radius = _radiusForCount(p.count);
                    return CircleMarker(
                      point: LatLng(p.lat, p.lng),
                      radius: radius,
                      color: const Color(0xFFDC2626).withOpacity(0.28),
                      borderColor: const Color(0xFFDC2626).withOpacity(0.65),
                      borderStrokeWidth: 1.5,
                      useRadiusInMeter: true,
                    );
                  }).toList(),
                ),
                loading: () => const CircleLayer<CircleMarker>(circles: []),
                error: (_, __) => const CircleLayer<CircleMarker>(circles: []),
              ),
            ],
          ),

          // Legend card
          Positioned(
            bottom: 24,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kSurface.withOpacity(0.95),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Scam Hotspots',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: kTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _LegendItem(
                    color: const Color(0xFFDC2626).withOpacity(0.3),
                    label: 'Low',
                  ),
                  _LegendItem(
                    color: const Color(0xFFDC2626).withOpacity(0.55),
                    label: 'Medium',
                  ),
                  _LegendItem(
                    color: const Color(0xFFDC2626).withOpacity(0.8),
                    label: 'High',
                  ),
                ],
              ),
            ),
          ),

          // Loading overlay
          if (heatmap.isLoading)
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: kPurpleDark),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Updating map…',
                        style: TextStyle(
                            fontSize: 13,
                            color: kTextPrimary,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
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
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                  color: const Color(0xFFDC2626).withOpacity(0.7),
                  width: 1),
            ),
          ),
          const SizedBox(width: 8),
          Text(label,
              style:
                  const TextStyle(fontSize: 11, color: kTextSecondary)),
        ],
      ),
    );
  }
}