declare module 'qrcode' {
  const QRCode: {
    toDataURL(text: string, options?: unknown): Promise<string>
    toString(text: string, options?: unknown): Promise<string>
  }

  export default QRCode
}
