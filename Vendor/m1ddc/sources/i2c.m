@import Foundation;

#include "i2c.h"
#include "utils.h"

// ODS fix: a zero checksum is still a byte. Use the protocol length.
static int getBytesUsed(UInt8* data) {
    int length = (data[0] & 0x7f) + 2;
    return length <= DDC_BUFFER_SIZE ? length : 0;
}

// Function to get ready for DDC operations for a specific display attribute
DDCPacket createDDCPacket(UInt8 attrCode) {
    DDCPacket packet = {};
    packet.data[2] = attrCode;
    packet.inputAddr = packet.data[2] == INPUT_ALT ? ALTERNATE_INPUT_ADDRESS : DEFAULT_INPUT_ADDRESS;
    return packet;
}

// Prepare DDC packet for read
void prepareDDCRead(UInt8* data) {
    data[0] = 0x82;
    data[1] = 0x01;
    data[3] = 0x6e ^ data[0] ^ data[1] ^ data[2] ^ data[3];
}

// Prepare DDC packet for write
void prepareDDCWrite(DDCPacket *packet, UInt16 newValue) {
    UInt8* data = packet->data;
    data[0] = 0x84;
    data[1] = 0x03;
    data[3] = (newValue) >> 8;
    data[4] = newValue & 255;
    data[5] = 0x6E ^ packet->inputAddr ^ data[0] ^ data[1] ^ data[2] ^ data[3] ^ data[4];
}


IOReturn performDDCReadAtChipAddress(IOAVServiceRef avService, UInt32 chipAddress, DDCPacket *packet) {
    memset(packet->data, 0, sizeof(UInt8) * DDC_BUFFER_SIZE);
    usleep(chipAddress == DDC_CHIP_ADDRESS_MCDP29XX ? DDC_MCDP_READ_WAIT : DDC_WAIT);
    return IOAVServiceReadI2C(avService, chipAddress, packet->inputAddr, packet->data, 12);
}

IOReturn performDDCWriteAtChipAddress(IOAVServiceRef avService, UInt32 chipAddress, DDCPacket *packet) {
    IOReturn ret;

    for (int i = 0; i < DDC_ITERATIONS; ++i) {
        usleep(DDC_WAIT);
        if ((ret = IOAVServiceWriteI2C(avService, chipAddress, packet->inputAddr, packet->data, getBytesUsed(packet->data)))) {
            return ret;
        }
    }
    return ret;
}

IOReturn performDDCRead(IOAVServiceRef avService, DDCPacket *packet) {
    return performDDCReadAtChipAddress(avService, DDC_CHIP_ADDRESS_DEFAULT, packet);
}

IOReturn performDDCWrite(IOAVServiceRef avService, DDCPacket *packet) {
    return performDDCWriteAtChipAddress(avService, DDC_CHIP_ADDRESS_DEFAULT, packet);
}


// ODS fix: reject unsupported/malformed replies and decode two-byte fields
// directly. The original sizeof(2) read requested four bytes from two-byte data.
DDCValue convertI2CtoDDC(char *i2cBytes) {
    const UInt8 *p = (const UInt8 *)i2cBytes;
    DDCValue invalid = {-1, -1};
    if (!p || p[0] != 0x6e || (p[1] & 0x7f) != 8 || p[2] != 2 || p[3] != 0) return invalid;
    DDCValue value = {.maxValue = (p[6] << 8) | p[7], .curValue = (p[8] << 8) | p[9]};
    if (value.maxValue < 1 || value.curValue > value.maxValue) return invalid;
    return value;
}
