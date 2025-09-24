export class CrearVentaDto {
  cliente_nombre!: string;
  cliente_apellido!: string;
  documento!: string;
  plan!: string;   // Ej: "FTTH 200M Hogar"
  total!: number;  // Ej: 30.00
}
