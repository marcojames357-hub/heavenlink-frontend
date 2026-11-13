import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class PropertyMapFrame extends StatefulWidget {
  const PropertyMapFrame({
    required this.locationQuery,
    required this.zoom,
    super.key,
  });

  final String locationQuery;
  final int zoom;

  @override
  State<PropertyMapFrame> createState() => _PropertyMapFrameState();
}

class _PropertyMapFrameState extends State<PropertyMapFrame> {
  static int _nextViewId = 0;

  late final String _viewType;
  web.HTMLIFrameElement? _frame;

  @override
  void initState() {
    super.initState();
    _viewType = 'haven-link-property-map-${_nextViewId++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (viewId) {
      final frame = web.HTMLIFrameElement()
        ..src = _mapUri().toString()
        ..title = 'Property location map'
        ..allowFullscreen = true
        ..style.border = '0'
        ..style.display = 'block'
        ..style.width = '100%'
        ..style.height = '100%';
      frame.setAttribute('loading', 'eager');
      _frame = frame;
      return frame;
    });
  }

  @override
  void didUpdateWidget(covariant PropertyMapFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locationQuery != widget.locationQuery ||
        oldWidget.zoom != widget.zoom) {
      _frame?.src = _mapUri().toString();
    }
  }

  Uri _mapUri() => Uri.https('maps.google.com', '/maps', {
    'q': widget.locationQuery,
    'z': widget.zoom.toString(),
    'output': 'embed',
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 300,
    width: double.infinity,
    child: HtmlElementView(viewType: _viewType),
  );
}
