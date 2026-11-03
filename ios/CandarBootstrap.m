#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#if __has_include("Candar_Network-Swift.h")
#import "Candar_Network-Swift.h"
#else
#import "candarnetwork-Swift.h"
#endif

__attribute__((constructor))
static void CandarNativeBootstrap(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[CandarNativeBridge shared] initAll];
    });
}
