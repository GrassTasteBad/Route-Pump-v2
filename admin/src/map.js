import { state } from './state.js';
import { openModal } from './ui.js';

export function initMap() {
  if (state.map) return; // Already initialized

  const mapElement = document.getElementById("map");
  if (!mapElement) return;

  if (typeof google === 'undefined' || typeof google.maps === 'undefined') {
    setTimeout(initMap, 100);
    return;
  }

  // Center on Davao City center
  state.map = new google.maps.Map(mapElement, {
    center: { lat: 7.0736, lng: 125.6110 },
    zoom: 14,
    styles: null,
    mapTypeControl: false,
    streetViewControl: false,
    fullscreenControl: false
  });

  // Click handler to help fill coordinates in the modal
  state.map.addListener("click", (e) => {
    const lat = e.latLng.lat();
    const lng = e.latLng.lng();

    // Prefill modal form coords
    document.getElementById('station-lat').value = lat.toFixed(6);
    document.getElementById('station-lng').value = lng.toFixed(6);

    openModal('station-modal');
  });

  renderMapObjects();

  const locateBtn = document.getElementById('map-locate-btn');
  if (locateBtn) {
    locateBtn.addEventListener('click', () => {
      if (!navigator.geolocation) {
        alert('Geolocation is not supported by your browser.');
        return;
      }

      locateBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Locating...';
      locateBtn.disabled = true;

      navigator.geolocation.getCurrentPosition(
        (position) => {
          const lat = position.coords.latitude;
          const lng = position.coords.longitude;

          if (state.map) {
            state.map.setCenter({ lat, lng });
            state.map.setZoom(17);

            if (state.myLocationMarker) {
              state.myLocationMarker.setMap(null);
            }
            state.myLocationMarker = new google.maps.Marker({
              position: { lat, lng },
              map: state.map,
              title: "My Location",
              icon: {
                path: google.maps.SymbolPath.CIRCLE,
                fillColor: '#3b82f6',
                fillOpacity: 1.0,
                scale: 9,
                strokeColor: '#ffffff',
                strokeWeight: 2
              }
            });

            document.getElementById('station-lat').value = lat.toFixed(6);
            document.getElementById('station-lng').value = lng.toFixed(6);
          }

          locateBtn.innerHTML = '<i class="fa-solid fa-location-crosshairs"></i> Locate Me';
          locateBtn.disabled = false;
        },
        (error) => {
          alert('Error obtaining current location: ' + error.message);
          locateBtn.innerHTML = '<i class="fa-solid fa-location-crosshairs"></i> Locate Me';
          locateBtn.disabled = false;
        },
        { enableHighAccuracy: true, timeout: 8000 }
      );
    });
  }
}

export function renderMapObjects() {
  if (!state.map) return;

  // Clear old markers/polygons
  state.mapMarkers.forEach(m => m.setMap(null));
  state.mapPolygons.forEach(p => p.setMap(null));
  state.mapMarkers = [];
  state.mapPolygons = [];

  state.stations.forEach(station => {
    // Convert geofence coordinates to google.maps.LatLngLiteral objects
    const coords = station.geofence_polygon.map(p => ({ lat: p[0], lng: p[1] }));
    const color = station.queue_count > 3 ? '#f43f5e' : (station.queue_count > 0 ? '#f59e0b' : '#06b6d4');

    // 1. Polygon Boundary
    const polygon = new google.maps.Polygon({
      paths: coords,
      strokeColor: color,
      strokeOpacity: 0.8,
      strokeWeight: 1.5,
      fillColor: color,
      fillOpacity: 0.15,
      map: state.map
    });

    // Tooltip using InfoWindow on mouseover
    const tooltip = new google.maps.InfoWindow({
      content: `<div style="color: #000; font-weight: bold; font-family: sans-serif; font-size: 12px;">${station.name} (${station.branch}) - ${station.queue_count} cars in queue</div>`
    });

    polygon.addListener("mouseover", (e) => {
      tooltip.setPosition(e.latLng);
      tooltip.open(state.map);
    });

    polygon.addListener("mouseout", () => {
      tooltip.close();
    });

    state.mapPolygons.push(polygon);

    // 2. Custom Circle Marker
    const markerColor = station.status === 'active' ? '#10b981' : '#f43f5e';
    const marker = new google.maps.Marker({
      position: { lat: station.latitude, lng: station.longitude },
      map: state.map,
      icon: {
        path: google.maps.SymbolPath.CIRCLE,
        fillColor: markerColor,
        fillOpacity: 0.8,
        scale: 8,
        strokeColor: '#ffffff',
        strokeWeight: 2
      }
    });

    const popupHtml = `
      <div style="font-family: sans-serif; color: #000; min-width: 150px;">
        <strong style="font-size: 15px; display: block; margin-bottom: 4px;">${station.name}</strong>
        <span style="color: #666; display: block; font-size: 12px; margin-bottom: 8px;">${station.branch} Branch</span>
        <div style="font-size: 13px;">
          <strong>Reg Unl (91):</strong> ₱${station.prices['regular unleaded (91)'] ? Number(station.prices['regular unleaded (91)']).toFixed(2) : '-'}<br>
          <strong>Prem Unl (95):</strong> ₱${station.prices['premium unleaded(95)'] ? Number(station.prices['premium unleaded(95)']).toFixed(2) : '-'}<br>
          <strong>Reg Diesel:</strong> ₱${station.prices['regular diesel'] ? Number(station.prices['regular diesel']).toFixed(2) : '-'}<br>
          <strong>Prem Diesel:</strong> ₱${station.prices['premium diesel'] ? Number(station.prices['premium diesel']).toFixed(2) : '-'}
        </div>
        <hr style="border: 0; border-top: 1px solid #ccc; margin: 8px 0;">
        <span class="badge" style="background: rgba(6,182,212,0.1); color: #06b6d4; display: inline-block; padding: 2px 6px; border-radius: 4px;">Q(t): ${station.queue_count} cars</span>
      </div>
    `;

    const infowindow = new google.maps.InfoWindow({
      content: popupHtml
    });

    marker.addListener("click", () => {
      infowindow.open(state.map, marker);
    });

    state.mapMarkers.push(marker);
  });
}
