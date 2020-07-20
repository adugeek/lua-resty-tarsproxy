
#ifndef _TARS_PARSE_H
#define _TARS_PARSE_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <zconf.h>

int parser(const char **servantName, size_t *servantNameLen, const char *buff, size_t size);

#ifdef __cplusplus
}
#endif
#endif //_TARS_PARSE_H