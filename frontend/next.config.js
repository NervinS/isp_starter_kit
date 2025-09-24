/** @type {import('next').NextConfig} */
const API_BASE_SSR =
  process.env.API_BASE_SSR || 'http://127.0.0.1:3000/v1';

const nextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,

  // Proxy de /api/* al backend Nest
  async rewrites() {
    return [
      { source: '/api/:path*', destination: `${API_BASE_SSR}/:path*` },
    ];
  },
};

module.exports = nextConfig;
