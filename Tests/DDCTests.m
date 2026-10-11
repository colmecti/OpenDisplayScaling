// SPDX-License-Identifier: MIT
@import Foundation;
@import IOKit;
#import "i2c.h"
static int assertions=0;static uint32_t writeLength=0;
IOReturn IOAVServiceReadI2C(IOAVServiceRef service,uint32_t chip,uint32_t offset,void *output,uint32_t size){return kIOReturnSuccess;}
IOReturn IOAVServiceWriteI2C(IOAVServiceRef service,uint32_t chip,uint32_t address,void *input,uint32_t size){writeLength=size;return kIOReturnSuccess;}
static void Check(BOOL condition){assertions++;if(!condition){fprintf(stderr,"DDC assertion %d failed\n",assertions);exit(1);}}
int main(void){@autoreleasepool {
    UInt8 reply[12]={0x6e,0x88,0x02,0x00,0x10,0x00,0x01,0x00,0x00,0x80,0,0};
    DDCValue value=convertI2CtoDDC((char *)reply);Check(value.maxValue==256 && value.curValue==128);
    reply[3]=1;Check(convertI2CtoDDC((char *)reply).curValue==-1);reply[3]=0;
    reply[8]=2;Check(convertI2CtoDDC((char *)reply).curValue==-1);reply[8]=0;
    reply[0]=0;Check(convertI2CtoDDC((char *)reply).curValue==-1);reply[0]=0x6e;
    reply[1]=0;Check(convertI2CtoDDC((char *)reply).curValue==-1);reply[1]=0x88;
    reply[2]=0;Check(convertI2CtoDDC((char *)reply).curValue==-1);reply[2]=2;
    Check(convertI2CtoDDC(NULL).curValue==-1);
    DDCPacket packet=createDDCPacket(LUMINANCE);prepareDDCWrite(&packet,0x6e ^ DEFAULT_INPUT_ADDRESS ^ 0x84 ^ 0x03 ^ LUMINANCE);
    Check(packet.data[5]==0);performDDCWrite(NULL,&packet);Check(writeLength==6);
    packet=createDDCPacket(LUMINANCE);prepareDDCRead(packet.data);performDDCWrite(NULL,&packet);Check(writeLength==4);
    printf("Passed %d DDC packet assertions (I2C writes mocked).\n",assertions);
}return 0;}
