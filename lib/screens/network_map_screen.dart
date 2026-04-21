import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../models/rivr_node.dart';
import '../providers/app_providers.dart';
import '../widgets/node_tile.dart';

class NetworkMapScreen extends ConsumerWidget {
  const NetworkMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodes = ref.watch(nodesProvider).values.toList();
    final hasGeo = nodes.any((n) => n.hasPosition);
    final hasNeighbours = nodes.any((n) => n.hopCount != 0);

    if (!hasNeighbours) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.share, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No nodes to map yet.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final ringView = Column(
      children: [
        Expanded(
          child: InteractiveViewer(
            constrained: false,
            boundaryMargin: const EdgeInsets.all(64),
            minScale: 0.3,
            maxScale: 3.0,
            child: SizedBox(
              width: 600,
              height: 600,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  final pos = details.localPosition;
                  final positions = _MeshPainter._layoutNodes(
                    nodes, 300.0, 300.0, const Size(600, 600));
                  for (final e in positions.entries) {
                    if ((e.value - pos).distance <= 28.0) {
                      NodeTile.showDetails(context, e.key);
                      return;
                    }
                  }
                },
                child: CustomPaint(
                  painter: _MeshPainter(
                    nodes: nodes,
                    primaryColor: Theme.of(context).colorScheme.primary,
                    textColor: Theme.of(context).colorScheme.onSurface,
                    linkColor: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
        _Legend(nodes: nodes),
      ],
    );

    if (!hasGeo) return ringView;

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.hub_outlined), text: 'Mesh'),
              Tab(icon: Icon(Icons.map_outlined), text: 'Map'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ringView,
                _GeoMapView(nodes: nodes),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Geo map view using OpenStreetMap tiles.  Displayed when at least one node
/// has a known position.  Falls back to a message when no nodes have coords.
class _GeoMapView extends StatelessWidget {
  final List<RivrNode> nodes;
  const _GeoMapView({required this.nodes});

  @override
  Widget build(BuildContext context) {
    final geoNodes = nodes.where((n) => n.hasPosition).toList();
    if (geoNodes.isEmpty) {
      return const Center(
          child: Text('No position data available.',
              style: TextStyle(color: Colors.grey)));
    }

    final center = LatLng(
      geoNodes.map((n) => n.lat!).reduce((a, b) => a + b) / geoNodes.length,
      geoNodes.map((n) => n.lon!).reduce((a, b) => a + b) / geoNodes.length,
    );

    final markers = geoNodes.map((n) {
      final Color color = n.isGateway
          ? const Color(0xFF6C63FF)
          : n.isRepeater
              ? const Color(0xFF00E5A0)
              : _scoreColor(n.linkScore);
      final String roleBadge = n.isGateway
          ? 'GW'
          : n.isRepeater
              ? 'R'
              : '';
      return Marker(
        point: LatLng(n.lat!, n.lon!),
        width: 96,
        height: 74,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => NodeTile.showDetails(context, n),
          child: SizedBox(
            width: 96,
            height: 74,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: 4,
                  child: _GeoRoleOutline(
                    isRepeater: n.isRepeater,
                    isGateway: n.isGateway,
                  ),
                ),
                Positioned(
                  top: 10,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      n.isGateway
                          ? Icons.cell_tower
                          : n.isRepeater
                              ? Icons.repeat
                              : Icons.person,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (roleBadge.isNotEmpty)
                  Positioned(
                    top: 2,
                    right: 18,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: n.isGateway
                            ? const Color(0xFF6C63FF)
                            : const Color(0xFF00E5A0),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white, width: 1.2),
                      ),
                      child: Text(
                        roleBadge,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Text(
                    n.displayName,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                      shadows: [
                        Shadow(
                          color: Colors.white,
                          blurRadius: 2,
                          offset: Offset(-1, -1),
                        ),
                        Shadow(
                          color: Colors.white,
                          blurRadius: 2,
                          offset: Offset(1, -1),
                        ),
                        Shadow(
                          color: Colors.white,
                          blurRadius: 2,
                          offset: Offset(-1, 1),
                        ),
                        Shadow(
                          color: Colors.white,
                          blurRadius: 2,
                          offset: Offset(1, 1),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: 12,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.rivr.companion',
        ),
        MarkerLayer(markers: markers),
      ],
    );
  }

  Color _scoreColor(int score) {
    if (score >= 70) return Colors.green.shade600;
    if (score >= 40) return Colors.orange.shade600;
    if (score >= 20) return Colors.red.shade400;
    return Colors.grey;
  }
}

class _GeoRoleOutline extends StatelessWidget {
  final bool isRepeater;
  final bool isGateway;

  const _GeoRoleOutline({
    required this.isRepeater,
    required this.isGateway,
  });

  @override
  Widget build(BuildContext context) {
    if (!isRepeater && !isGateway) {
      return const SizedBox(width: 48, height: 48);
    }

    final accent = isGateway
        ? const Color(0xFF6C63FF)
        : const Color(0xFF00E5A0);

    if (isGateway) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent, width: 2.6),
        ),
      );
    }

    return Transform.rotate(
      angle: math.pi / 4,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent, width: 2.6),
        ),
      ),
    );
  }
}

/// Force-directed layout approximation: positions nodes in a circle with the
/// centre reserved for the connected device (hop=0).  Nodes at hop=1 sit in
/// the inner ring, hop=2 in the outer.
class _MeshPainter extends CustomPainter {
  final List<RivrNode> nodes;
  final Color primaryColor;
  final Color textColor;
  final Color linkColor;

  const _MeshPainter({
    required this.nodes,
    required this.primaryColor,
    required this.textColor,
    required this.linkColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Assign positions based on hop count
    final positions = _layoutNodes(nodes, cx, cy, size);

    // Draw edges (hub-and-spoke based on hop count)
    final edgePaint = Paint()
      ..color = linkColor
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final thisPos = Offset(cx, cy);
    for (final e in positions.entries) {
      if (e.key.hopCount <= 1) {
        canvas.drawLine(thisPos, e.value, edgePaint);
      } else {
        // Draw edge to closest hop-1 node (approximate)
        final hop1 = positions.entries
            .where((x) => x.key.hopCount == 1)
            .fold<MapEntry<RivrNode, Offset>?>(null, (best, candidate) {
          if (best == null) return candidate;
          final dBest = (best.value - e.value).distance;
          final dCand = (candidate.value - e.value).distance;
          return dCand < dBest ? candidate : best;
        });
        if (hop1 != null) {
          canvas.drawLine(hop1.value, e.value, edgePaint);
        }
      }
    }

    // Draw "this device" node at centre
    final selfNode = nodes.where((n) => n.hopCount == 0).firstOrNull;
    final selfLabel = (selfNode != null && selfNode.callsign.isNotEmpty)
        ? selfNode.callsign
        : 'This\nDevice';
    _drawNode(canvas, thisPos, label: selfLabel,
      color: primaryColor,
      radius: 22,
      textColor: Colors.white,
      isRepeater: selfNode?.isRepeater ?? false,
      isGateway: selfNode?.isGateway ?? false);

    // Draw discovered nodes
    for (final e in positions.entries) {
      final node = e.key;
      final pos = e.value;
      final score = node.linkScore;
      final color = _scoreColor(score);
      _drawNode(canvas, pos,
          label: node.displayName,
          color: color,
          radius: 18,
          textColor: Colors.white,
          rssi: node.rssiDbm,
          isRepeater: node.isRepeater,
          isGateway: node.isGateway);
    }
  }

  void _drawNode(Canvas canvas, Offset pos, {
    required String label,
    required Color color,
    required double radius,
    required Color textColor,
    int? rssi,
    bool isRepeater = false,
    bool isGateway = false,
  }) {
    final nodePaint = Paint()..color = color;
    canvas.drawCircle(pos, radius, nodePaint);

    // Draw a diamond border around repeaters / gateways
    if (isRepeater || isGateway) {
      final borderColor = isGateway ? const Color(0xFF6C63FF) : const Color(0xFF00E5A0);
      final borderPaint = Paint()
        ..color = borderColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      final d = radius + 5;
      final path = Path()
        ..moveTo(pos.dx, pos.dy - d)
        ..lineTo(pos.dx + d, pos.dy)
        ..lineTo(pos.dx, pos.dy + d)
        ..lineTo(pos.dx - d, pos.dy)
        ..close();
      canvas.drawPath(path, borderPaint);
    }

    // Label below
    final tp = TextPainter(
      text: TextSpan(
          text: label,
          style: TextStyle(
              color: this.textColor, fontSize: 10, fontWeight: FontWeight.w500)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 80);
    tp.paint(
        canvas, pos + Offset(-tp.width / 2, radius + 4));

    if (rssi != null) {
      final rssiTp = TextPainter(
        text: TextSpan(
            text: '$rssi dBm',
            style: const TextStyle(color: Colors.grey, fontSize: 9)),
        textDirection: TextDirection.ltr,
      )..layout();
      rssiTp.paint(canvas,
          pos + Offset(-rssiTp.width / 2, radius + tp.height + 6));
    }
  }

  static Map<RivrNode, Offset> _layoutNodes(
      List<RivrNode> nodes, double cx, double cy, Size size) {
    final hop1 = nodes.where((n) => n.hopCount == 1).toList();
    final hop2 = nodes.where((n) => n.hopCount == 2).toList();
    final hopN = nodes.where((n) => n.hopCount > 2).toList();

    final result = <RivrNode, Offset>{};

    void placeRing(List<RivrNode> ring, double radius) {
      for (var i = 0; i < ring.length; i++) {
        final angle = (2 * math.pi * i / ring.length) - math.pi / 2;
        result[ring[i]] = Offset(
          cx + radius * math.cos(angle),
          cy + radius * math.sin(angle),
        );
      }
    }

    placeRing(hop1, 120);
    placeRing(hop2, 210);
    placeRing(hopN, 290);
    return result;
  }

  Color _scoreColor(int score) {
    if (score >= 70) return Colors.green.shade600;
    if (score >= 40) return Colors.orange.shade600;
    if (score >= 20) return Colors.red.shade400;
    return Colors.grey;
  }

  @override
  bool shouldRepaint(_MeshPainter old) =>
      old.nodes != nodes ||
      old.primaryColor != primaryColor;
}

class _Legend extends StatelessWidget {
  final List<RivrNode> nodes;
  const _Legend({required this.nodes});

  @override
  Widget build(BuildContext context) {
    // Exclude self-node (hopCount==0) from neighbour counts.
    final neighbours = nodes.where((n) => n.hopCount != 0).toList();
    final total = neighbours.length;
    final good = neighbours.where((n) => n.linkScore >= 70).length;
    final fair = neighbours.where((n) => n.linkScore >= 40 && n.linkScore < 70).length;
    final poor = neighbours.where((n) => n.linkScore < 40).length;
    final repeaters = neighbours.where((n) => n.isRepeater).length;
    final gateways = neighbours.where((n) => n.isGateway).length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Wrap(
          alignment: WrapAlignment.spaceAround,
          spacing: 12,
          children: [
            _LegendDot(color: const Color(0xFF00E5A0), label: 'Good ($good)'),
            _LegendDot(color: const Color(0xFFFFCA28), label: 'Fair ($fair)'),
            _LegendDot(color: const Color(0xFFFF5252), label: 'Poor ($poor)'),
            if (repeaters > 0)
              _LegendDiamond(color: const Color(0xFF00E5A0), label: 'Repeater ($repeaters)'),
            if (gateways > 0)
              _LegendDiamond(color: const Color(0xFF6C63FF), label: 'Gateway ($gateways)'),
            Text('$total nodes', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _LegendDiamond extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDiamond({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(10, 10),
          painter: _DiamondPainter(color: color),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _DiamondPainter extends CustomPainter {
  final Color color;
  const _DiamondPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final path = Path()
      ..moveTo(cx, 0)
      ..lineTo(size.width, cy)
      ..lineTo(cx, size.height)
      ..lineTo(0, cy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_DiamondPainter old) => old.color != color;
}
