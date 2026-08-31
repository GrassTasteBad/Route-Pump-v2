import { state } from './state.js';
import { handleLogout } from './auth.js';

const hostname = (typeof window !== 'undefined' && window.location.hostname) ? window.location.hostname : '127.0.0.1';
export const API_BASE_URL = `http://${hostname}:8000/api`;

export async function apiFetch(endpoint, options = {}) {
  const headers = {
    'Authorization': `Bearer ${state.token}`,
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    ...options.headers
  };

  const response = await fetch(`${API_BASE_URL}${endpoint}`, {
    ...options,
    headers
  });

  if (response.status === 401) {
    handleLogout();
    throw new Error('Session expired');
  }

  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.message || 'API request failed');
  }

  return data;
}
