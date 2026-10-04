#include <stdint.h>
#include <stddef.h>
int mfc_open(uint32_t *connection);
void mfc_close(uint32_t connection);
int mfc_read(uint32_t connection, const char *key, uint8_t *bytes, uint32_t *size, uint32_t *type);
int mfc_write(uint32_t connection, const char *key, const uint8_t *bytes, uint32_t size);
int mfc_key(uint32_t connection, uint32_t index, char *key);
