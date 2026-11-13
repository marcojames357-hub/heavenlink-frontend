import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Inline OpenStreetMap preview of a listing pin; tapping moves the pin.
class PinMap extends StatefulWidget {
  const PinMap({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.onMoved,
  });

  final double latitude;
  final double longitude;
  final void Function(double latitude, double longitude) onMoved;

  @override
  State<PinMap> createState() => _PinMapState();
}

class _PinMapState extends State<PinMap> {
  final _controller = MapController();

  @override
  void didUpdateWidget(PinMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      _controller.move(
        LatLng(widget.latitude, widget.longitude),
        _controller.camera.zoom,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final point = LatLng(widget.latitude, widget.longitude);
    return SizedBox(
      height: 220,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: point,
            initialZoom: 17,
            onTap: (_, tapped) =>
                widget.onMoved(tapped.latitude, tapped.longitude),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.havenlink.haven_link',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: point,
                  width: 44,
                  height: 44,
                  alignment: Alignment.topCenter,
                  child: Icon(
                    HavenIcons.locationOn,
                    size: 44,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: ColoredBox(
                color: Colors.white70,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '© OpenStreetMap contributors',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: Colors.black87),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
