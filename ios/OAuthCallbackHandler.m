// OAuthCallbackHandler.m
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface OAuthCallbackHandler : UIResponder <UIApplicationDelegate, UIWindowSceneDelegate>
@end

@implementation OAuthCallbackHandler

// iOS 12 ve altı
- (BOOL)application:(UIApplication *)app
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey,id>)options {

    [self saveOAuthURL:url];
    return YES;
}

// iOS 13+ (SceneDelegate)
- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    UIOpenURLContext *ctx = URLContexts.allObjects.firstObject;
    if (ctx != nil) {
        [self saveOAuthURL:ctx.URL];
    }
}

- (void)saveOAuthURL:(NSURL *)url {
    if (!url) return;

    // Godot'ta user:// = Documents; oraya yazıyoruz
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *path = [docs stringByAppendingPathComponent:@"oauth_callback.txt"];

    NSString *s = [url absoluteString];
    NSError *err = nil;
    [s writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];

    // Uygulama aktif değilse aktifleştir
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"GD_OAUTH_CALLBACK_WRITTEN" object:nil];
    });
}

@end
