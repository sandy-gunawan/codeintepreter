import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Code Interpreter - Banking Analytics',
  description: 'Secure code interpreter for banking data analysis',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="min-h-screen">{children}</body>
    </html>
  );
}
