#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

NSData *decompressGzip(const void *input, size_t inputLen);
void customLog2(NSString *format, ...);
void customLogMsg(NSString *msg);

#ifdef __cplusplus
}
#endif
