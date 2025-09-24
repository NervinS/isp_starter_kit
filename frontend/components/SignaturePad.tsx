'use client';
import React, { useRef, useEffect, useState } from 'react';

type Props = {
  width?: number;
  height?: number;
  onChange?: (dataUrl: string) => void;
  /** Deshabilita la captura (bloquea trazo y botón Limpiar) */
  disabled?: boolean;
  /** Clase extra opcional para el contenedor */
  className?: string;
};

export default function SignaturePad({
  width = 360,
  height = 180,
  onChange,
  disabled = false,
  className = '',
}: Props) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const ctxRef = useRef<CanvasRenderingContext2D | null>(null);
  const drawing = useRef(false);
  const last = useRef<{ x: number; y: number } | null>(null);
  const [empty, setEmpty] = useState(true);

  // Inicializa canvas (con soporte HiDPI)
  useEffect(() => {
    const canvas = canvasRef.current!;
    const dpr = Math.max(1, (globalThis as any).devicePixelRatio || 1);
    canvas.width = Math.max(1, Math.round(width * dpr));
    canvas.height = Math.max(1, Math.round(height * dpr));
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;

    const ctx = canvas.getContext('2d')!;
    ctxRef.current = ctx;

    ctx.reset?.(); // si el navegador soporta reset()
    ctx.scale(dpr, dpr);

    // Fondo blanco
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, width, height);

    // Estilos de trazo
    ctx.lineWidth = 2.5;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.strokeStyle = '#111827';

    setEmpty(true);
    if (onChange) onChange('');
  }, [width, height, onChange]);

  // Si se deshabilita en medio del trazo, cortar
  useEffect(() => {
    if (disabled) {
      drawing.current = false;
      last.current = null;
    }
  }, [disabled]);

  const getPos = (e: React.PointerEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current!;
    const rect = canvas.getBoundingClientRect();
    return { x: e.clientX - rect.left, y: e.clientY - rect.top };
  };

  const start = (e: React.PointerEvent<HTMLCanvasElement>) => {
    if (disabled) return;
    (e.target as Element).setPointerCapture(e.pointerId);
    drawing.current = true;
    last.current = getPos(e);
    setEmpty(false);
  };

  const move = (e: React.PointerEvent<HTMLCanvasElement>) => {
    if (!drawing.current || disabled) return;
    e.preventDefault();
    const ctx = ctxRef.current!;
    const p = getPos(e);
    const from = last.current || p;

    ctx.beginPath();
    ctx.moveTo(from.x, from.y);
    ctx.lineTo(p.x, p.y);
    ctx.stroke();
    last.current = p;
  };

  const end = () => {
    if (!drawing.current) return;
    drawing.current = false;
    last.current = null;
    if (onChange && canvasRef.current) {
      onChange(canvasRef.current.toDataURL('image/png'));
    }
  };

  const clear = () => {
    if (disabled) return;
    const canvas = canvasRef.current!;
    const ctx = ctxRef.current!;
    ctx.clearRect(0, 0, width, height);
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, width, height);
    setEmpty(true);
    if (onChange) onChange('');
  };

  return (
    <div className={`space-y-2 ${className}`}>
      <canvas
        ref={canvasRef}
        className="border rounded shadow-sm touch-none"
        style={{
          display: 'block',
          cursor: disabled ? 'not-allowed' : 'crosshair',
          opacity: disabled ? 0.6 : 1,
        }}
        onPointerDown={start}
        onPointerMove={move}
        onPointerUp={end}
        onPointerCancel={end}
        onPointerLeave={end}
      />
      <div className="text-sm flex gap-2 items-center">
        <button
          type="button"
          onClick={clear}
          disabled={disabled || empty}
          className="px-3 py-1 border rounded disabled:opacity-50 disabled:cursor-not-allowed"
        >
          Limpiar
        </button>
        <span className="opacity-70">
          {empty ? 'Firme dentro del recuadro' : 'Firma capturada'}
        </span>
      </div>
    </div>
  );
}
