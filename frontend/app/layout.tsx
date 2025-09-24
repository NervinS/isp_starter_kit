export const metadata = {
  title: 'ISP | Panel',
  description: 'Gestión de órdenes, agenda y técnico',
};

import './globals.css';

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="es">
      <body>{children}</body>
    </html>
  );
}
