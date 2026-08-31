import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Photorealistic 3D navigation map powered by Google Maps JS API Map3DElement
/// (gmp-map-3d) via WebView on mobile, with seamless native GoogleMap on Web.
class Map3DNavigationView extends StatefulWidget {
  final double lat;
  final double lng;
  final double bearing;
  final double tilt;
  final double destLat;
  final double destLng;
  final List<Map<String, double>> routePoints;

  const Map3DNavigationView({
    super.key,
    required this.lat,
    required this.lng,
    required this.bearing,
    required this.tilt,
    required this.destLat,
    required this.destLng,
    this.routePoints = const [],
  });

  @override
  State<Map3DNavigationView> createState() => Map3DNavigationViewState();
}

class Map3DNavigationViewState extends State<Map3DNavigationView> {
  WebViewController? _webViewController;
  GoogleMapController? _googleMapController;
  bool _loaded = false;

  /// Exposed for external JS injection on mobile
  WebViewController? get controller => _loaded ? _webViewController : null;

  static const String _apiKey = 'AIzaSyAGMiQQ_bqlwYd8vC6JP0Z3d7phZSQM8eo';

  String _buildHtml(double lat, double lng, double heading, double tilt,
      double destLat, double destLng, List<Map<String, double>> route) {
    final routeJson = jsonEncode(
      route.map((p) => {'lat': p['lat'], 'lng': p['lng']}).toList(),
    );

    return '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
  <title>RoutePump 3D Navigation</title>
  <script async
    src="https://maps.googleapis.com/maps/api/js?key=$_apiKey&v=alpha&libraries=maps3d">
  </script>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { width: 100%; height: 100%; overflow: hidden; background: #000; }
    gmp-map-3d { width: 100%; height: 100%; display: block; }
  </style>
</head>
<body>
  <gmp-map-3d
    id="map3d"
    center="$lat,$lng,80"
    heading="$heading"
    tilt="$tilt"
    range="350">
  </gmp-map-3d>

  <script>
    const routePoints = $routeJson;
    const destLat = $destLat;
    const destLng = $destLng;

    let map3d = null;
    let destinationMarker = null;
    let routePolyline = null;
    let userMarker = null;

    customElements.whenDefined('gmp-map-3d').then(async () => {
      map3d = document.getElementById('map3d');
      await map3d.innerComplete;

      // User location marker (current position)
      userMarker = new google.maps.maps3d.Marker3DInteractiveElement({
        position: { lat: $lat, lng: $lng, altitude: 5 },
        altitudeMode: 'RELATIVE_TO_GROUND',
      });
      map3d.appendChild(userMarker);

      // Destination marker
      destinationMarker = new google.maps.maps3d.Marker3DInteractiveElement({
        position: { lat: destLat, lng: destLng, altitude: 5 },
        altitudeMode: 'RELATIVE_TO_GROUND',
      });
      map3d.appendChild(destinationMarker);

      // Route polyline
      if (routePoints.length > 1) {
        routePolyline = new google.maps.maps3d.Polyline3DElement({
          strokeColor: '#00FFCC',
          strokeWidth: 8,
          altitudeMode: 'CLAMP_TO_GROUND',
        });
        routePolyline.coordinates = routePoints.map(p => ({lat: p.lat, lng: p.lng, altitude: 0}));
        map3d.appendChild(routePolyline);
      }
    });

    function updateCamera(lat, lng, heading, tilt, range) {
      if (!map3d) return;
      map3d.center = { lat: lat, lng: lng, altitude: 80 };
      map3d.heading = heading;
      map3d.tilt = tilt;
      map3d.range = range || 350;
      if (userMarker) {
        userMarker.position = { lat: lat, lng: lng, altitude: 5 };
      }
    }

    function updateRoute(routeJson) {
      if (!map3d) return;
      const pts = JSON.parse(routeJson);
      if (pts.length < 2) return;
      if (routePolyline) map3d.removeChild(routePolyline);
      routePolyline = new google.maps.maps3d.Polyline3DElement({
        strokeColor: '#00FFCC',
        strokeWidth: 8,
        altitudeMode: 'CLAMP_TO_GROUND',
      });
      routePolyline.coordinates = pts.map(p => ({lat: p.lat, lng: p.lng, altitude: 0}));
      map3d.appendChild(routePolyline);
    }
  </script>
</body>
</html>''';
  }

  @override
  void initState() {
    super.initState();

    if (!kIsWeb) {
      _initMobileWebView();
    } else {
      _loaded = true;
    }
  }

  void _initMobileWebView() {
    try {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black)
        ..setNavigationDelegate(NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loaded = true);
          },
        ))
        ..loadHtmlString(
          _buildHtml(
            widget.lat,
            widget.lng,
            widget.bearing,
            widget.tilt,
            widget.destLat,
            widget.destLng,
            widget.routePoints,
          ),
          baseUrl: 'https://routepump.app',
        );
    } catch (e) {
      debugPrint('Error initializing WebView: $e');
      if (mounted) setState(() => _loaded = true);
    }
  }

  void updateCamera(double lat, double lng, double bearing, double tilt) {
    if (kIsWeb) {
      _googleMapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(lat, lng),
            zoom: 17.5,
            bearing: bearing,
            tilt: tilt,
          ),
        ),
      );
    } else if (_loaded && _webViewController != null) {
      _webViewController!.runJavaScript(
        'updateCamera($lat, $lng, $bearing, $tilt, 350);',
      );
    }
  }

  @override
  void didUpdateWidget(Map3DNavigationView old) {
    super.didUpdateWidget(old);

    final posChanged = old.lat != widget.lat ||
        old.lng != widget.lng ||
        old.bearing != widget.bearing ||
        old.tilt != widget.tilt;

    if (posChanged) {
      updateCamera(widget.lat, widget.lng, widget.bearing, widget.tilt);
    }

    final routeChanged = old.routePoints.length != widget.routePoints.length;
    if (routeChanged && !kIsWeb && _loaded && widget.routePoints.isNotEmpty && _webViewController != null) {
      final routeJson = jsonEncode(
        widget.routePoints
            .map((p) => {'lat': p['lat'], 'lng': p['lng']})
            .toList(),
      );
      _webViewController!.runJavaScript(
        "updateRoute('${routeJson.replaceAll("'", "\\'")}');",
      );
    }
  }

  Set<Marker> _buildWebMarkers() {
    final markers = <Marker>{};

    // User position marker
    markers.add(
      Marker(
        markerId: const MarkerId('user_pos'),
        position: LatLng(widget.lat, widget.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
        infoWindow: const InfoWindow(title: 'Your Location'),
        rotation: widget.bearing,
        flat: true,
      ),
    );

    // Destination marker
    markers.add(
      Marker(
        markerId: const MarkerId('dest_station'),
        position: LatLng(widget.destLat, widget.destLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Destination Station'),
      ),
    );

    return markers;
  }

  Set<Polyline> _buildWebPolylines() {
    final polylines = <Polyline>{};

    if (widget.routePoints.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('nav_route'),
          points: widget.routePoints
              .map((p) => LatLng(p['lat']!, p['lng']!))
              .toList(),
          color: const Color(0xFF10B981),
          width: 6,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
    }

    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || _webViewController == null) {
      // Clean, interactive GoogleMap on Web / Fallback
      return GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(widget.lat, widget.lng),
          zoom: 17.5,
          bearing: widget.bearing,
          tilt: widget.tilt,
        ),
        onMapCreated: (controller) => _googleMapController = controller,
        markers: _buildWebMarkers(),
        polylines: _buildWebPolylines(),
        myLocationEnabled: false,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        compassEnabled: true,
        trafficEnabled: true,
        buildingsEnabled: true,
        mapToolbarEnabled: false,
      );
    }

    return Stack(
      children: [
        WebViewWidget(controller: _webViewController!),
        if (!_loaded)
          Container(
            color: Colors.black,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF10B981)),
                  SizedBox(height: 14),
                  Text(
                    'Loading 3D Map...',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
