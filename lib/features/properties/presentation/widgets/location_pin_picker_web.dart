import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Interactive OpenStreetMap (Leaflet) picker. Agents click the map, drag the
/// pin, search a place or use their device location to set the coordinates.
class LocationPinPicker extends StatefulWidget {
  const LocationPinPicker({
    required this.latitude,
    required this.longitude,
    required this.onChanged,
    super.key,
  });

  final double? latitude;
  final double? longitude;
  final void Function(double latitude, double longitude) onChanged;

  @override
  State<LocationPinPicker> createState() => _LocationPinPickerState();
}

class _LocationPinPickerState extends State<LocationPinPicker> {
  static int _nextViewId = 0;

  late final String _token;
  late final String _viewType;
  web.HTMLIFrameElement? _frame;
  late final JSFunction _listener;

  @override
  void initState() {
    super.initState();
    final id = _nextViewId++;
    _token = 'pin$id';
    _viewType = 'haven-link-pin-picker-$id';
    _listener = ((web.MessageEvent event) {
      final data = event.data.dartify();
      if (data is! String) return;
      final prefix = 'haven-pin:$_token:';
      if (!data.startsWith(prefix)) return;
      final parts = data.substring(prefix.length).split(',');
      final lat = double.tryParse(parts.first);
      final lng = double.tryParse(parts.last);
      if (lat == null || lng == null) return;
      widget.onChanged(lat, lng);
    }).toJS;
    web.window.addEventListener('message', _listener);
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (viewId) {
      final frame = web.HTMLIFrameElement()
        ..srcdoc = _html(_token, widget.latitude, widget.longitude).toJS
        ..title = 'Pin the property location'
        ..style.border = '0'
        ..style.display = 'block'
        ..style.width = '100%'
        ..style.height = '100%';
      _frame = frame;
      return frame;
    });
  }

  @override
  void didUpdateWidget(covariant LocationPinPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final lat = widget.latitude;
    final lng = widget.longitude;
    if (lat != null &&
        lng != null &&
        (lat != oldWidget.latitude || lng != oldWidget.longitude)) {
      _frame?.contentWindow?.postMessage('haven-set:$lat,$lng'.toJS, '*'.toJS);
    }
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 320,
    width: double.infinity,
    child: HtmlElementView(viewType: _viewType),
  );
}

String _html(String token, double? lat, double? lng) {
  final hasPin = lat != null && lng != null;
  final startLat = lat ?? -6.7924;
  final startLng = lng ?? 39.2083;
  final startZoom = hasPin ? 16 : 12;
  return '''
<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
html,body,#map{height:100%;margin:0;font-family:sans-serif}
#bar{position:absolute;z-index:1000;top:8px;left:50px;right:8px;display:flex;gap:6px}
#q{flex:1;padding:7px;border:1px solid #888;border-radius:6px;min-width:0}
button{padding:7px 10px;border:0;border-radius:6px;background:#0f766e;color:#fff;cursor:pointer}
#hint{position:absolute;z-index:1000;bottom:22px;left:8px;background:#fffd;padding:4px 8px;border-radius:6px;font-size:12px}
</style></head><body>
<div id="map"></div>
<div id="bar"><input id="q" placeholder="Search a place, e.g. Sinza, Dar es Salaam">
<button id="go">Search</button><button id="me">My location</button></div>
<div id="hint">Tap the map or drag the pin to set the property location</div>
<script>
var T="$token", map=L.map('map').setView([$startLat,$startLng],$startZoom), marker=null;
L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:19,attribution:'&copy; OpenStreetMap'}).addTo(map);
function emit(ll){parent.postMessage('haven-pin:'+T+':'+ll.lat.toFixed(6)+','+ll.lng.toFixed(6),'*');}
function place(ll,notify){
  if(!marker){marker=L.marker(ll,{draggable:true}).addTo(map);marker.on('dragend',function(){emit(marker.getLatLng());});}
  else{marker.setLatLng(ll);}
  if(notify)emit(ll);
}
${hasPin ? 'place([$startLat,$startLng],false);' : ''}
map.on('click',function(e){place(e.latlng,true);});
window.addEventListener('message',function(e){
  if(typeof e.data!=='string'||e.data.indexOf('haven-set:')!==0)return;
  var p=e.data.substring(10).split(',');var ll=L.latLng(parseFloat(p[0]),parseFloat(p[1]));
  place(ll,false);map.setView(ll,Math.max(map.getZoom(),16));
});
function search(){
  var q=document.getElementById('q').value.trim();if(!q)return;
  fetch('https://nominatim.openstreetmap.org/search?format=json&limit=1&q='+encodeURIComponent(q))
   .then(function(r){return r.json();}).then(function(r){
     if(!r.length){alert('Place not found');return;}
     var ll=L.latLng(parseFloat(r[0].lat),parseFloat(r[0].lon));map.setView(ll,16);place(ll,true);
   }).catch(function(){alert('Search failed. Tap the map instead.');});
}
document.getElementById('go').onclick=search;
document.getElementById('q').onkeydown=function(e){if(e.key==='Enter')search();};
document.getElementById('me').onclick=function(){
  if(!navigator.geolocation){alert('Location is not available');return;}
  navigator.geolocation.getCurrentPosition(function(p){
    var ll=L.latLng(p.coords.latitude,p.coords.longitude);map.setView(ll,17);place(ll,true);
  },function(){alert('Could not read your location. Tap the map instead.');});
};
</script></body></html>''';
}
