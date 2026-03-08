import axios from 'axios';

const BASE_URL = process.env.REACT_APP_API_URL || '/api';

const api = axios.create({
  baseURL: BASE_URL,
  timeout: 10000,
  headers: { 'Content-Type': 'application/json' },
});

// Attach JWT token to every request if present
api.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem('hm_token');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => Promise.reject(error)
);

// Handle 401 globally — clear token and redirect to login
api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response && error.response.status === 401) {
      localStorage.removeItem('hm_token');
      localStorage.removeItem('hm_user');
      window.location.href = '/login';
    }
    return Promise.reject(error);
  }
);

// ── Auth ─────────────────────────────────────────────────────────────────────
export const authAPI = {
  register: (data) => api.post('/auth/register', data),
  login:    (data) => api.post('/auth/login',    data),
  profile:  ()     => api.get('/auth/profile'),
};

// ── Products ─────────────────────────────────────────────────────────────────
export const productsAPI = {
  getAll:   (params) => api.get('/products',    { params }),
  getById:  (id)     => api.get(`/products/${id}`),
  getCategories: ()  => api.get('/products/categories'),
};

// ── Orders ───────────────────────────────────────────────────────────────────
export const ordersAPI = {
  create:   (data)   => api.post('/orders',      data),
  getMyOrders: ()    => api.get('/orders/mine'),
  getById:  (id)     => api.get(`/orders/${id}`),
};

// ── Health ───────────────────────────────────────────────────────────────────
export const healthAPI = {
  check: () => api.get('/health'),
};

export default api;
