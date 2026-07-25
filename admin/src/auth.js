import { state } from './state.js';
import { apiFetch, API_BASE_URL } from './api.js';
import { loadAllData } from './views.js';

export function showAuthScreen() {
  document.getElementById('auth-section').style.display = 'flex';
  document.getElementById('app-section').style.display = 'none';
}

export function showDashboardApp() {
  document.getElementById('auth-section').style.display = 'none';
  document.getElementById('app-section').style.display = 'flex';
  
  // Set User UI Details
  document.getElementById('user-display-name').innerText = state.user?.name || 'Administrator';
  if (state.user?.name) {
    const letters = state.user.name.split(' ').map(n => n[0]).join('').substring(0, 2).toUpperCase();
    document.getElementById('avatar-letters').innerText = letters;
  }

  // Load all initial data
  loadAllData();
  
  // Auto-refresh stats every 15 seconds
  if (window.statsInterval) clearInterval(window.statsInterval);
  window.statsInterval = setInterval(loadAllData, 15000);
}

export function setupAuth() {
  const loginForm = document.getElementById('login-form');
  if (!loginForm) return;

  loginForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const email = document.getElementById('login-email').value;
    const password = document.getElementById('login-password').value;
    const alertBox = document.getElementById('auth-alert');
    const submitBtn = document.getElementById('login-submit-btn');

    alertBox.style.display = 'none';
    submitBtn.disabled = true;
    submitBtn.innerHTML = '<span class="spinner"></span>Signing In...';

    try {
      const response = await fetch(`${API_BASE_URL}/login`, {
        method: 'POST',
        headers: { 
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: JSON.stringify({ email, password }),
      });

      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.message || 'Login failed');
      }

      if (data.user.role !== 'admin') {
        throw new Error('Access denied: You must be an administrator.');
      }

      // Save credentials
      state.token = data.token;
      state.user = data.user;
      localStorage.setItem('rp_admin_token', data.token);
      localStorage.setItem('rp_admin_user', JSON.stringify(data.user));

      showDashboardApp();
    } catch (err) {
      alertBox.innerText = err.message;
      alertBox.style.display = 'block';
    } finally {
      submitBtn.disabled = false;
      submitBtn.innerHTML = '<span>Sign In</span>';
    }
  });
}

export async function handleLogout() {
  try {
    await fetch(`${API_BASE_URL}/logout`, {
      method: 'POST',
      headers: { 
        'Authorization': `Bearer ${state.token}`,
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      }
    });
  } catch (e) {
    console.error('Logout error API', e);
  }

  // Clear local storage anyway
  state.token = '';
  state.user = null;
  localStorage.removeItem('rp_admin_token');
  localStorage.removeItem('rp_admin_user');
  
  if (window.statsInterval) clearInterval(window.statsInterval);

  showAuthScreen();
}
