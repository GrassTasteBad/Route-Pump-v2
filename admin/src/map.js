import { state } from './state.js';
import { openModal } from './ui.js';

// ─────────────────────────────────────────────────────────────────────────────
// NATIONWIDE BRANDED GAS STATION REFERENCE LAYER
// Visual-only markers sourced from the Google Maps Places API.
// No database records are created here.
// ─────────────────────────────────────────────────────────────────────────────

const BRAND_COLORS = {
  petron:    { bg: '#003087', border: '#FFC906', label: 'P'  },
  shell:     { bg: '#DD1D21', border: '#FFC906', label: 'SH' },
  caltex:    { bg: '#CC0000', border: '#0060A9', label: 'CX' },
  phoenix:   { bg: '#F37021', border: '#ffffff', label: 'PX' },
  cleanfuel: { bg: '#00843D', border: '#ffffff', label: 'CF' },
  seaoil:    { bg: '#1B3F8B', border: '#E31837', label: 'SO' },
  ptt:       { bg: '#009A44', border: '#ED1C24', label: 'PT' },
  total:     { bg: '#EF7D00', border: '#231F20', label: 'TL' },
};

// 60+ major city / area centres across the Philippines
const PH_SEARCH_HUBS = [
  { lat: 14.5995, lng: 120.9842, radius: 25000 }, // Metro Manila (broad)
  { lat: 14.6760, lng: 121.0437, radius: 12000 }, // Quezon City
  { lat: 14.5547, lng: 121.0244, radius:  8000 }, // Makati
  { lat: 14.5764, lng: 121.0851, radius:  8000 }, // Pasig
  { lat: 14.6500, lng: 120.9667, radius: 10000 }, // Caloocan
  { lat: 14.4500, lng: 120.9833, radius:  8000 }, // Las Piñas
  { lat: 14.5176, lng: 121.0509, radius:  8000 }, // Taguig / BGC
  { lat: 14.4793, lng: 121.0198, radius:  8000 }, // Parañaque
  { lat: 14.4081, lng: 121.0415, radius:  8000 }, // Muntinlupa
  { lat: 14.4297, lng: 120.9367, radius:  8000 }, // Imus
  { lat: 14.4582, lng: 120.9644, radius:  8000 }, // Bacoor
  { lat: 14.3294, lng: 120.9367, radius:  8000 }, // Dasmariñas
  { lat: 14.5863, lng: 121.1762, radius: 12000 }, // Antipolo
  { lat: 14.6507, lng: 121.1029, radius:  8000 }, // Marikina
  { lat: 14.5794, lng: 121.0359, radius:  5000 }, // Mandaluyong
  { lat: 14.7011, lng: 120.9830, radius:  8000 }, // Valenzuela
  { lat: 14.6625, lng: 120.9573, radius:  5000 }, // Malabon
  { lat: 14.5378, lng: 121.0014, radius:  5000 }, // Pasay
  { lat: 14.8527, lng: 120.8100, radius:  8000 }, // Malolos
  { lat: 15.4873, lng: 120.9674, radius: 10000 }, // Cabanatuan
  { lat: 15.4756, lng: 120.5960, radius: 10000 }, // Tarlac City
  { lat: 14.8295, lng: 120.2826, radius: 10000 }, // Olongapo
  { lat: 15.1450, lng: 120.5887, radius: 10000 }, // Angeles City
  { lat: 15.0289, lng: 120.6897, radius: 10000 }, // San Fernando, Pampanga
  { lat: 16.4023, lng: 120.5960, radius: 10000 }, // Baguio City
  { lat: 18.1969, lng: 120.5937, radius: 10000 }, // Laoag
  { lat: 17.5747, lng: 120.3869, radius: 10000 }, // Vigan
  { lat: 17.6132, lng: 121.7270, radius: 10000 }, // Tuguegarao
  { lat: 16.6862, lng: 121.5500, radius:  8000 }, // Santiago City
  { lat: 13.7565, lng: 121.0583, radius: 10000 }, // Batangas City
  { lat: 13.9411, lng: 121.1631, radius:  8000 }, // Lipa City
  { lat: 13.9373, lng: 121.6170, radius: 10000 }, // Lucena City
  { lat: 13.6218, lng: 123.1945, radius: 10000 }, // Naga City
  { lat: 13.1391, lng: 123.7438, radius: 10000 }, // Legazpi City
  { lat: 10.3157, lng: 123.8854, radius: 15000 }, // Cebu City
  { lat: 10.3236, lng: 123.9223, radius:  8000 }, // Mandaue
  { lat: 10.3103, lng: 123.9494, radius:  8000 }, // Lapu-Lapu
  { lat: 10.3779, lng: 123.6412, radius:  8000 }, // Toledo
  { lat: 10.5203, lng: 124.0267, radius:  8000 }, // Danao
  { lat:  9.6500, lng: 123.8500, radius:  8000 }, // Tagbilaran
  { lat: 10.7202, lng: 122.5621, radius: 15000 }, // Iloilo City
  { lat: 11.5872, lng: 122.7533, radius:  8000 }, // Roxas City
  { lat: 10.6713, lng: 122.9511, radius: 12000 }, // Bacolod
  { lat:  9.3068, lng: 123.3054, radius: 10000 }, // Dumaguete
  { lat: 10.1311, lng: 124.8450, radius:  8000 }, // Maasin
  { lat: 11.2543, lng: 124.9968, radius: 10000 }, // Tacloban
  { lat:  9.7392, lng: 118.7353, radius: 12000 }, // Puerto Princesa
  { lat:  7.0736, lng: 125.6110, radius: 20000 }, // Davao City
  { lat:  7.4479, lng: 125.8073, radius:  8000 }, // Tagum
  { lat:  6.9575, lng: 126.2163, radius:  8000 }, // Mati City
  { lat:  6.7497, lng: 125.3572, radius:  8000 }, // Digos
  { lat:  7.0083, lng: 125.0894, radius:  8000 }, // Kidapawan
  { lat:  6.5036, lng: 124.8460, radius:  8000 }, // Koronadal
  { lat:  6.1164, lng: 125.1716, radius: 12000 }, // General Santos
  { lat:  8.4542, lng: 124.6319, radius: 15000 }, // Cagayan de Oro
  { lat:  8.9475, lng: 125.5406, radius: 12000 }, // Butuan
  { lat:  9.7840, lng: 125.4980, radius:  8000 }, // Surigao City
  { lat:  8.2086, lng: 126.3270, radius:  8000 }, // Bislig
  { lat:  7.8278, lng: 123.4373, radius: 10000 }, // Pagadian
  { lat:  6.9214, lng: 122.0790, radius: 15000 }, // Zamboanga
  { lat:  7.2236, lng: 124.2464, radius: 10000 }, // Cotabato City
  { lat:  7.9983, lng: 124.2924, radius:  8000 }, // Marawi City
];

const BRAND_KEYS = Object.keys(BRAND_COLORS);

// ── helpers ───────────────────────────────────────────────────────────────────

function detectBrand(name) {
  const lower = (name || '').toLowerCase();
  for (const brand of BRAND_KEYS) {
    if (lower.includes(brand)) return brand;
  }
  return null;
}

function makeBrandIcon(cfg) {
  const fs = cfg.label.length > 2 ? 7 : 11;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="34" height="44" viewBox="0 0 34 44">
    <path d="M17 0 C7.6 0 0 7.6 0 17 C0 29.75 17 44 17 44 C17 44 34 29.75 34 17 C34 7.6 26.4 0 17 0Z"
      fill="${cfg.bg}" stroke="${cfg.border}" stroke-width="2.5"/>
    <text x="17" y="22" text-anchor="middle" font-family="Arial,sans-serif"
      font-weight="bold" font-size="${fs}" fill="#fff">${cfg.label}</text>
  </svg>`;
  return {
    url: 'data:image/svg+xml;charset=UTF-8,' + encodeURIComponent(svg),
    scaledSize: new google.maps.Size(30, 38),
    anchor: new google.maps.Point(15, 38),
  };
}

// Capitalise first letter of each word
function toTitleCase(str) {
  return (str || '').replace(/\w\S*/g, w => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase());
}

// ── reference marker state ────────────────────────────────────────────────────

state.brandedGasMarkers = state.brandedGasMarkers || [];
const _seenPlaceIds = new Set();
let _activeInfoWindow = null; // only one info window open at a time

// ── "Add as Partner Station" action ──────────────────────────────────────────

function prefillAndOpenModal(place, brand) {
  // Determine brand name + branch from the Places name
  // e.g. "Petron Matina Branch" → name="Petron", branch="Matina Branch"
  const fullName = place.name || '';
  const brandTitle = toTitleCase(brand);

  // Branch = everything after the brand keyword, trimmed
  const branchRaw = fullName.replace(new RegExp(brand, 'i'), '').trim();
  // Fallback to vicinity if branch text is empty
  const branch = branchRaw || (place.vicinity ? place.vicinity.split(',')[0].trim() : '');

  const lat = place.geometry.location.lat();
  const lng = place.geometry.location.lng();

  // Reset the form so we're always in "Add" mode
  const form = document.getElementById('station-form');
  if (form) form.reset();

  // Remove any hidden edit-id so the form submits as a new station
  const hiddenId = document.getElementById('station-edit-id');
  if (hiddenId) hiddenId.value = '';

  // Pre-fill fields
  const nameEl   = document.getElementById('station-name');
  const branchEl = document.getElementById('station-branch');
  const latEl    = document.getElementById('station-lat');
  const lngEl    = document.getElementById('station-lng');

  if (nameEl)   nameEl.value   = brandTitle;
  if (branchEl) branchEl.value = branch;
  if (latEl)    latEl.value    = lat.toFixed(6);
  if (lngEl)    lngEl.value    = lng.toFixed(6);

  // Title
  const title = document.getElementById('station-modal-title');
  if (title) title.innerText = `Add ${brandTitle} as Partner Station`;

  openModal('station-modal');
}

// ── Places search ─────────────────────────────────────────────────────────────

function buildInfoWindowContent(place, brand) {
  const cfg = BRAND_COLORS[brand];
  return `
    <div style="font-family:'Segoe UI',sans-serif;color:#111;min-width:190px;max-width:230px;">
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:6px;">
        <div style="width:32px;height:32px;border-radius:50%;background:${cfg.bg};
             border:2px solid ${cfg.border};display:flex;align-items:center;
             justify-content:center;color:#fff;font-weight:700;font-size:11px;flex-shrink:0;">
          ${cfg.label}
        </div>
        <div>
          <strong style="font-size:13px;display:block;line-height:1.2;">${place.name}</strong>
          <span style="font-size:11px;color:#666;">${place.vicinity || ''}</span>
        </div>
      </div>
      <hr style="border:0;border-top:1px solid #e5e7eb;margin:6px 0;">
      <div style="display:flex;align-items:center;gap:6px;margin-bottom:8px;">
        <span style="font-size:10px;background:#f0fdf4;color:#15803d;
              padding:2px 7px;border-radius:20px;border:1px solid #bbf7d0;">
          📍 Reference only — not yet in DB
        </span>
      </div>
      <button
        id="rp-add-partner-btn"
        onclick="window.__rpAddPartner('${place.place_id}')"
        style="width:100%;padding:7px 0;background:${cfg.bg};color:#fff;border:none;
               border-radius:6px;font-size:12px;font-weight:600;cursor:pointer;
               display:flex;align-items:center;justify-content:center;gap:5px;">
        ➕ Add as Partner Station
      </button>
    </div>`;
}

function searchHubForBrands(service, hub, map) {
  service.nearbySearch(
    { location: { lat: hub.lat, lng: hub.lng }, radius: hub.radius, type: 'gas_station' },
    (results, status, pagination) => {
      if (status === google.maps.places.PlacesServiceStatus.OK && results) {
        results.forEach(place => {
          const brand = detectBrand(place.name);
          if (!brand) return;
          if (_seenPlaceIds.has(place.place_id)) return;
          _seenPlaceIds.add(place.place_id);

          // Store place data for the button callback
          window.__rpPlaceCache = window.__rpPlaceCache || {};
          window.__rpPlaceCache[place.place_id] = { place, brand };

          const marker = new google.maps.Marker({
            position: place.geometry.location,
            map,
            title: place.name,
            icon: makeBrandIcon(BRAND_COLORS[brand]),
            zIndex: 1,
          });

          const iw = new google.maps.InfoWindow({
            content: buildInfoWindowContent(place, brand),
          });

          marker.addListener('click', () => {
            if (_activeInfoWindow) _activeInfoWindow.close();
            _activeInfoWindow = iw;
            iw.open(map, marker);
          });

          state.brandedGasMarkers.push(marker);
        });

        if (pagination && pagination.hasNextPage) {
          setTimeout(() => pagination.nextPage(), 250);
        }
      }
    }
  );
}

// Global callback for the "Add as Partner Station" button inside InfoWindow DOM
window.__rpAddPartner = function (placeId) {
  const cached = window.__rpPlaceCache && window.__rpPlaceCache[placeId];
  if (!cached) return;
  if (_activeInfoWindow) _activeInfoWindow.close();
  prefillAndOpenModal(cached.place, cached.brand);
};

export function searchBrandedStations(map) {
  if (!map) return;

  // Clear old reference markers
  (state.brandedGasMarkers || []).forEach(m => m.setMap(null));
  state.brandedGasMarkers = [];
  _seenPlaceIds.clear();
  window.__rpPlaceCache = {};

  const service = new google.maps.places.PlacesService(map);

  // Stagger calls to avoid hitting the Places API rate limit
  PH_SEARCH_HUBS.forEach((hub, i) => {
    setTimeout(() => searchHubForBrands(service, hub, map), i * 300);
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// MAP INIT
// ─────────────────────────────────────────────────────────────────────────────

export function initMap() {
  if (state.map) return;

  const mapElement = document.getElementById('map');
  if (!mapElement) return;

  if (typeof google === 'undefined' || typeof google.maps === 'undefined') {
    setTimeout(initMap, 100);
    return;
  }

  state.map = new google.maps.Map(mapElement, {
    center: { lat: 7.0736, lng: 125.6110 }, // Davao City
    zoom: 14,
    tilt: 0,
    styles: [
      // Hide ALL default POI icons (restaurants, malls, churches, hospitals, etc.)
      { featureType: 'poi', stylers: [{ visibility: 'off' }] },
      // Hide transit markers (bus stops, train stations, etc.)
      { featureType: 'transit', stylers: [{ visibility: 'off' }] },
    ],
    mapTypeControl: false,
    streetViewControl: false,
    fullscreenControl: false,
  });

  // Click handler: pre-fill coordinates AND open the Add Station modal
  state.map.addListener('click', e => {
    const lat = e.latLng.lat();
    const lng = e.latLng.lng();
    document.getElementById('station-lat').value = lat.toFixed(6);
    document.getElementById('station-lng').value = lng.toFixed(6);
    openModal('station-modal');
  });

  renderMapObjects();
  searchBrandedStations(state.map);

  // Locate-me button: zoom to user location + drop a "My Location" blue dot
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
        position => {
          const lat = position.coords.latitude;
          const lng = position.coords.longitude;

          if (state.map) {
            state.map.setCenter({ lat, lng });
            state.map.setZoom(17);

            // Drop / refresh the "My Location" blue dot marker
            if (state.myLocationMarker) {
              state.myLocationMarker.setMap(null);
            }
            state.myLocationMarker = new google.maps.Marker({
              position: { lat, lng },
              map: state.map,
              title: 'My Location',
              icon: {
                path: google.maps.SymbolPath.CIRCLE,
                fillColor: '#3b82f6',
                fillOpacity: 1.0,
                scale: 9,
                strokeColor: '#ffffff',
                strokeWeight: 2,
              },
            });

            // Also pre-fill the form coords
            document.getElementById('station-lat').value = lat.toFixed(6);
            document.getElementById('station-lng').value = lng.toFixed(6);
          }

          locateBtn.innerHTML = '<i class="fa-solid fa-location-crosshairs"></i> Locate Me';
          locateBtn.disabled = false;
        },
        error => {
          alert('Error obtaining current location: ' + error.message);
          locateBtn.innerHTML = '<i class="fa-solid fa-location-crosshairs"></i> Locate Me';
          locateBtn.disabled = false;
        },
        { enableHighAccuracy: true, timeout: 8000 }
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RENDER DB STATIONS (partner stations already in the database)
// ─────────────────────────────────────────────────────────────────────────────

export function renderMapObjects() {
  if (!state.map) return;

  // Clear previous DB markers / polygons only
  state.mapMarkers.forEach(m => m.setMap(null));
  state.mapPolygons.forEach(p => p.setMap(null));
  state.mapMarkers  = [];
  state.mapPolygons = [];

  state.stations.forEach(station => {
    const coords = station.geofence_polygon.map(p => ({ lat: p[0], lng: p[1] }));
    const queueColor =
      station.queue_count > 3 ? '#f43f5e' :
      station.queue_count > 0 ? '#f59e0b' :
                                '#06b6d4';

    // ── 1. Geofence polygon ───────────────────────────────────────────────────
    const polygon = new google.maps.Polygon({
      paths: coords,
      strokeColor:   queueColor,
      strokeOpacity: 0.85,
      strokeWeight:  1.5,
      fillColor:     queueColor,
      fillOpacity:   0.15,
      map: state.map,
    });

    const tooltip = new google.maps.InfoWindow({
      content: `<div style="color:#000;font-weight:bold;font-family:sans-serif;font-size:12px;">
        ${station.name} (${station.branch}) — ${station.queue_count} cars in queue
      </div>`,
    });

    polygon.addListener('mouseover', e => { tooltip.setPosition(e.latLng); tooltip.open(state.map); });
    polygon.addListener('mouseout',  ()  => tooltip.close());
    state.mapPolygons.push(polygon);

    // ── 2. Station pin (partner station — already in DB) ─────────────────────
    const pinColor = station.status === 'active' ? '#10b981' : '#f43f5e';
    const pinSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="34" height="44" viewBox="0 0 34 44">
      <path d="M17 0 C7.6 0 0 7.6 0 17 C0 29.75 17 44 17 44 C17 44 34 29.75 34 17 C34 7.6 26.4 0 17 0Z"
        fill="${pinColor}" stroke="#fff" stroke-width="2.5"/>
      <text x="17" y="22" text-anchor="middle" font-family="Arial,sans-serif"
        font-weight="bold" font-size="9" fill="#fff">DB</text>
    </svg>`;

    const marker = new google.maps.Marker({
      position: { lat: station.latitude, lng: station.longitude },
      map: state.map,
      title: `${station.name} – ${station.branch}`,
      icon: {
        url: 'data:image/svg+xml;charset=UTF-8,' + encodeURIComponent(pinSvg),
        scaledSize: new google.maps.Size(30, 38),
        anchor:     new google.maps.Point(15, 38),
      },
      zIndex: 10, // always on top of reference markers
    });

    const popupHtml = `
      <div style="font-family:'Segoe UI',sans-serif;color:#111;min-width:170px;">
        <strong style="font-size:14px;display:block;margin-bottom:2px;">${station.name}</strong>
        <span style="color:#555;font-size:12px;display:block;margin-bottom:8px;">${station.branch} Branch</span>
        <div style="font-size:12px;line-height:1.7;">
          <b>Reg Unl (91):</b> ₱${station.prices['regular unleaded (91)']
            ? Number(station.prices['regular unleaded (91)']).toFixed(2) : '—'}<br>
          <b>Prem Unl (95):</b> ₱${station.prices['premium unleaded(95)']
            ? Number(station.prices['premium unleaded(95)']).toFixed(2) : '—'}<br>
          <b>Reg Diesel:</b> ₱${station.prices['regular diesel']
            ? Number(station.prices['regular diesel']).toFixed(2) : '—'}<br>
          <b>Prem Diesel:</b> ₱${station.prices['premium diesel']
            ? Number(station.prices['premium diesel']).toFixed(2) : '—'}
        </div>
        <hr style="border:0;border-top:1px solid #e5e7eb;margin:8px 0;">
        <span style="font-size:11px;background:rgba(6,182,212,.1);color:#06b6d4;
              padding:2px 8px;border-radius:20px;">
          ⛽ ${station.queue_count} cars in queue
        </span>
      </div>`;

    const infowindow = new google.maps.InfoWindow({ content: popupHtml });

    marker.addListener('click', () => {
      if (_activeInfoWindow) _activeInfoWindow.close();
      _activeInfoWindow = infowindow;
      infowindow.open(state.map, marker);
    });

    state.mapMarkers.push(marker);
  });
}
