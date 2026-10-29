#import <Foundation/Foundation.h>
#import "Logger.h"

void customLog(NSString *format, ...) {
#ifdef DEBUG
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[Tweak] %@", message);
#endif
}

void customLog2(NSString *format, ...) {
#ifdef DEBUG
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[Tweak] %@", message);
#endif
}
