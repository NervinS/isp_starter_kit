// src/modules/pdf/pdf.controller.ts
import { Controller, Get, Post, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { PdfService } from './pdf.service';

@ApiTags('PDF')
@Controller('pdf')
export class PdfController {
  constructor(private readonly pdf: PdfService) {}

  @Get('public-url')
  @ApiOperation({ summary: 'Devuelve la URL pública para una key dada' })
  publicUrl(@Query('key') key: string) {
    const url = this.pdf.publicUrlFor(key);
    return { key, url };
  }

  @Post('ensure')
  @ApiOperation({
    summary:
      'Asegura que exista un PDF (dummy) para la key indicada y devuelve su URL pública',
  })
  async ensure(@Query('key') key: string) {
    const url = await this.pdf.ensurePdf(key);
    return { key, url, created: !!url };
  }
}
