#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import "fishhook/fishhook.h"

#ifdef __cplusplus
extern "C" {
#endif

void initSideloadedFixes(void);

#ifdef __cplusplus
}
#endif
