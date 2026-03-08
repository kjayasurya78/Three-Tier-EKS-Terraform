import React from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import { AuthProvider } from './context/AuthContext';
import { CartProvider } from './context/CartContext';
import Navbar from './components/Navbar';
import HeroBanner from './components/HeroBanner';
import ProductGrid from './components/ProductGrid';
import ProductDetail from './components/ProductDetail';
import Cart from './components/Cart';
import Checkout from './components/Checkout';
import Login from './components/Auth/Login';
import Register from './components/Auth/Register';

function HomePage() {
  return (
    <>
      <HeroBanner />
      <ProductGrid />
    </>
  );
}

function App() {
  return (
    <AuthProvider>
      <CartProvider>
        <Router>
          <Navbar />
          <Cart />
          <Routes>
            <Route path="/"                  element={<HomePage />} />
            <Route path="/products/:id"      element={<ProductDetail />} />
            <Route path="/checkout"          element={<Checkout />} />
            <Route path="/login"             element={<Login />} />
            <Route path="/register"          element={<Register />} />
          </Routes>
        </Router>
      </CartProvider>
    </AuthProvider>
  );
}

export default App;
