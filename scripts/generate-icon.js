#!/usr/bin/env node
// Generates a minimal 256x256 ICO file (PNG-in-ICO format) with no dependencies.
const fs = require('fs')
const zlib = require('zlib')
const path = require('path')

function crc32(buf) {
  let crc = 0xFFFFFFFF
  for (let i = 0; i < buf.length; i++) {
    crc ^= buf[i]
    for (let j = 0; j < 8; j++) {
      crc = (crc & 1) ? (0xEDB88320 ^ (crc >>> 1)) : (crc >>> 1)
    }
  }
  return (crc ^ 0xFFFFFFFF) >>> 0
}

function makeChunk(type, data) {
  const len = Buffer.alloc(4)
  len.writeUInt32BE(data.length)
  const typeB = Buffer.from(type, 'ascii')
  const crcVal = crc32(Buffer.concat([typeB, data]))
  const crcB = Buffer.alloc(4)
  crcB.writeUInt32BE(crcVal)
  return Buffer.concat([len, typeB, data, crcB])
}

function createSolidPNG(width, height, r, g, b) {
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])

  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(width, 0)
  ihdr.writeUInt32BE(height, 4)
  ihdr[8] = 8  // bit depth
  ihdr[9] = 2  // RGB color type
  // compression, filter, interlace all 0

  // Raw image data: filter byte (0x00 = None) + RGB pixels per row
  const rowSize = 1 + width * 3
  const rawData = Buffer.alloc(height * rowSize)
  for (let y = 0; y < height; y++) {
    const base = y * rowSize
    rawData[base] = 0  // filter: None
    for (let x = 0; x < width; x++) {
      rawData[base + 1 + x * 3] = r
      rawData[base + 1 + x * 3 + 1] = g
      rawData[base + 1 + x * 3 + 2] = b
    }
  }

  const compressed = zlib.deflateSync(rawData)

  return Buffer.concat([
    sig,
    makeChunk('IHDR', ihdr),
    makeChunk('IDAT', compressed),
    makeChunk('IEND', Buffer.alloc(0)),
  ])
}

function createIco(pngData) {
  // ICO header
  const header = Buffer.alloc(6)
  header.writeUInt16LE(0, 0)  // reserved
  header.writeUInt16LE(1, 2)  // type: 1 = ICO
  header.writeUInt16LE(1, 4)  // image count

  // Directory entry (16 bytes)
  const entry = Buffer.alloc(16)
  entry[0] = 0    // width: 0 means 256
  entry[1] = 0    // height: 0 means 256
  entry[2] = 0    // color count (0 = no palette)
  entry[3] = 0    // reserved
  entry.writeUInt16LE(1, 4)               // color planes
  entry.writeUInt16LE(24, 6)              // bits per pixel
  entry.writeUInt32LE(pngData.length, 8)  // size of image data
  entry.writeUInt32LE(22, 12)             // offset: 6 (header) + 16 (entry)

  return Buffer.concat([header, entry, pngData])
}

// Healthcare blue: #2B7FD4
const png = createSolidPNG(256, 256, 43, 127, 212)
const ico = createIco(png)

const outPath = path.join(__dirname, '../assets/icon.ico')
fs.mkdirSync(path.dirname(outPath), { recursive: true })
fs.writeFileSync(outPath, ico)
console.log(`Written: ${outPath} (${ico.length} bytes)`)
