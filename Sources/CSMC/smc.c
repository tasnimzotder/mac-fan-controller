#include "CSMC.h"
#include <IOKit/IOKitLib.h>
#include <string.h>
// AppleSMC user-client ABI: 80 bytes, including natural alignment padding.
typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } Version;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, memory; } Limits;
typedef struct { uint32_t size, type; uint8_t attributes; } KeyInfo;
typedef struct { uint32_t key; Version version; Limits limits; KeyInfo info;
    uint8_t result, status, command; uint32_t data; uint8_t bytes[32]; } Packet;
_Static_assert(sizeof(Packet) == 80, "AppleSMC ABI mismatch");
static uint32_t fourcc(const char *s) { return ((uint32_t)(uint8_t)s[0]<<24)|((uint32_t)(uint8_t)s[1]<<16)|((uint32_t)(uint8_t)s[2]<<8)|(uint8_t)s[3]; }
static int call(uint32_t c, Packet *in, Packet *out) {
    size_t size = sizeof(*out);
    kern_return_t result = IOConnectCallStructMethod(c, 2, in, sizeof(*in), out, &size);
    if (result) return (int)result;
    if (size != sizeof(*out)) return -1;
    return out->result ? (int)out->result : 0;
}
int mfc_open(uint32_t *c) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return -1;
    int result = IOServiceOpen(service, mach_task_self(), 0, c);
    IOObjectRelease(service); return result;
}
void mfc_close(uint32_t c) { if(c) IOServiceClose(c); }
static int info(uint32_t c, const char *key, Packet *out) {
    Packet in = {0}; in.key = fourcc(key); in.command = 9;
    return call(c, &in, out);
}
int mfc_read(uint32_t c, const char *key, uint8_t *bytes, uint32_t *size, uint32_t *type) {
    Packet metadata = {0}, in = {0}, out = {0}; int result = info(c,key,&metadata);
    if(result) return result;
    if(metadata.info.size > 32 || !metadata.info.size) return -2;
    in.key = fourcc(key); in.info.size = metadata.info.size; in.command = 5;
    result = call(c,&in,&out); if(result) return result;
    *size = metadata.info.size; *type = metadata.info.type;
    memcpy(bytes,out.bytes,*size); return 0;
}
int mfc_write(uint32_t c, const char *key, const uint8_t *bytes, uint32_t size) {
    Packet metadata = {0}, in = {0}, out = {0}; int result = info(c,key,&metadata);
    if(result) return result;
    if(size > 32 || size != metadata.info.size) return -2;
    in.key = fourcc(key); in.info.size = size; in.command = 6;
    memcpy(in.bytes,bytes,size); return call(c,&in,&out);
}
int mfc_key(uint32_t c, uint32_t index, char *key) {
    Packet in = {0}, out = {0}; in.command = 8; in.data = index;
    int result = call(c,&in,&out); if(result) return result;
    for(int i=0;i<4;i++) key[i]=(char)(out.key>>(24-i*8)); key[4]=0; return 0;
}
