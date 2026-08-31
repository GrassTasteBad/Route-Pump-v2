// State Management for RoutePump Admin
export const state = {
  token: localStorage.getItem('rp_admin_token') || '',
  user: JSON.parse(localStorage.getItem('rp_admin_user')) || null,
  activePage: 'dashboard',
  stations: [],
  catalog: [],
  anomalies: [],
  submissions: [],
  users: [],
  map: null,
  mapMarkers: [],
  mapPolygons: [],
};
