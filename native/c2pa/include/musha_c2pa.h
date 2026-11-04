#ifndef MUSHA_C2PA_H
#define MUSHA_C2PA_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
char *musha_c2pa_verify(const uint8_t *bytes, size_t len, const char *mime);
char *musha_c2pa_verify_online(const uint8_t *bytes, size_t len, const char *mime);
void musha_c2pa_free(char *result);
#ifdef __cplusplus
}
#endif
#endif
