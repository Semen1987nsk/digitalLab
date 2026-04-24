/// CRC8 (Dallas/Maxim, reflected polynomial 0x8C)
/// Must match firmware crc8() EXACTLY.
int crc8(List<int> data) {
  int crc = 0x00;
  for (int i = 0; i < data.length; i++) {
    int b = data[i] & 0xFF;
    for (int bit = 0; bit < 8; bit++) {
      if ((crc ^ b) & 0x01 != 0) {
        crc = (crc >> 1) ^ 0x8C;
      } else {
        crc >>= 1;
      }
      b >>= 1;
    }
  }
  return crc & 0xFF;
}
