declare module 'subset-font' {
  interface SubsetOptions {
    targetFormat?: 'sfnt' | 'woff' | 'woff2' | 'truetype';
    noHinting?: boolean;
    variationAxes?: Record<string, number | { min: number; max: number; default?: number }>;
  }
  export default function subsetFont(font: Uint8Array, text: string, options?: SubsetOptions): Promise<Uint8Array>;
}
