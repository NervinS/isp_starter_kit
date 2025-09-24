export class AsignarDto {
  fecha!: string;            // ISO8601
  turno!: 'am' | 'pm';
  tecnicoId?: string;
  tecnicoCodigo?: string;
}
