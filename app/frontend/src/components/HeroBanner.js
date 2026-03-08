import React from 'react';
import { Link } from 'react-router-dom';

export default function HeroBanner() {
  return (
    <div className="hero-banner">
      <h1>New Season Arrivals</h1>
      <p>Discover the latest trends in fashion — from casual to couture.</p>
      <Link to="/">
        <button className="btn-shop">Shop Now</button>
      </Link>
    </div>
  );
}
