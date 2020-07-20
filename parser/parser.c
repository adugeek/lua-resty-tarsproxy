
#include "parser.h"
#include <stdint.h>
#include <endian.h>

/*
此处目标是提取出 sServantName ,且因为tag 是严格有序的,此处只需要考虑到 sServantName之前的数据类型即可,可以减少parser工作量
*/

enum {
    eChar = 0,
    eShort = 1,
    eInt32 = 2,
    eInt64 = 3,
    eFloat = 4,
    eDouble = 5,
    eString1 = 6,
    eString4 = 7,
    eMap = 8,
    eList = 9,
    eStructBegin = 10,
    eStructEnd = 11,
    eZeroTag = 12,
    eSimpleList = 13,
};

#define SERVANT_TAG 5

#define ENSURE_LEFT_LENGTH(pos, v, s) \
do { \
    if ((pos)+(v)>(s)){ return -1;} \
}while(0)

#define APPEND_POS(pos, v) \
do { \
    (pos)+=(v); \
}while(0)


#define betoh_uint8_t(x) (x)
#define betoh_uint16_t(x) be16toh(x)
#define betoh_uint32_t(x) be32toh(x)
#define betoh_uint64_t(x) be64toh(x)
#define BETOH(type, x) betoh_##type(x)

#define LOAD(type, dLen) \
do {           \
        ENSURE_LEFT_LENGTH(*pos, sizeof(type), size); \
        *dLen = *(type *) (s + *pos);        \
        *dLen = BETOH(type,*dLen);             \
        APPEND_POS(*pos, sizeof(type));          \
}while(0)

int READ_DATA_LENGTH(uint32_t *value, int type, const char *s, size_t *pos, size_t size) {
    do {
        switch (type) {
            case eChar: {
                LOAD(uint8_t, value);
            }
                break;
            case eShort: {
                LOAD(uint16_t, value);
            }
                break;
            case eInt32: {
                LOAD(uint32_t, value);
            }
                break;
            case eInt64: {
                LOAD(uint64_t, value);
            }
                break;
            default:
                return -1;
        }
    } while (0);
    return 0;
}

int parser(const char **servantObj, size_t *servantNameLen, const char *s, size_t size) {
    size_t pos = 0;
    while (pos != size) {
        ENSURE_LEFT_LENGTH(pos, sizeof(uint8_t), size);
        uint8_t key = *(s + pos);
        APPEND_POS(pos, sizeof(uint8_t));
        uint8_t tag = (key >> 4u);
        if (tag == 15) {
            ENSURE_LEFT_LENGTH(pos, sizeof(uint8_t), size);
            tag = *(s + pos);
            APPEND_POS(pos, sizeof(uint8_t));
        }
        uint8_t type = (key & 0X0fu);
        uint32_t len = 0;
        switch (type) {
            case eChar:
                len = 1;
                break;
            case eShort:
                len = 2;
                break;
            case eInt32:
                len = 4;
                break;
            case eInt64:
                len = 8;
                break;
            case eZeroTag:
                len = 0;
                break;
            case eString1: {
                if (READ_DATA_LENGTH(&len, eChar, s, &pos, size) != 0) {
                    return -1;
                }
            }
                break;
            case eString4: {
                if (READ_DATA_LENGTH(&len, eInt32, s, &pos, size) != 0) {
                    return -1;
                }
            }
                break;
            default:
                return -1;
        }
        ENSURE_LEFT_LENGTH(pos, len, size);
        if (tag == SERVANT_TAG) {
            *servantObj = s + pos;
            *servantNameLen = len;
            return 0;
        }
        APPEND_POS(pos, len);
    }
    return -1;
}