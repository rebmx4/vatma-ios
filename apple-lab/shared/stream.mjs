// The helper sends multipart JPEGs. Markers are independent of chunk boundaries.
export class JpegFrames {
  constructor(onFrame, limit = 8 * 1024 * 1024) {
    this.onFrame = onFrame;
    this.limit = limit;
    this.buffer = Buffer.alloc(0);
  }
  push(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    while (this.buffer.length) {
      const start = this.buffer.indexOf(Buffer.from([255, 216]));
      if (start < 0) { this.buffer = this.buffer.subarray(-1); return; }
      if (start > 0) this.buffer = this.buffer.subarray(start);
      const end = this.buffer.indexOf(Buffer.from([255, 217]), 2);
      if (end < 0) {
        if (this.buffer.length > this.limit) throw new Error('JPEG frame too large');
        return;
      }
      if (end + 2 > this.limit) throw new Error('JPEG frame too large');
      this.onFrame(this.buffer.subarray(0, end + 2));
      this.buffer = this.buffer.subarray(end + 2);
    }
  }
}
