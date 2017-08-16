
#import "A0Auth0.h"

#import <SafariServices/SafariServices.h>
#import <CommonCrypto/CommonCrypto.h>

#if __has_include("RCTUtils.h")
#import "RCTUtils.h"
#else
#import <React/RCTUtils.h>
#endif

@interface A0Auth0 () <SFSafariViewControllerDelegate>
@property (weak, nonatomic) SFSafariViewController *last;
@property (copy, nonatomic) RCTResponseSenderBlock sessionCallback;
@property (copy, nonatomic) RCTResponseSenderBlock didLoadCallback;
@end

@implementation A0Auth0

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE();

RCT_EXPORT_METHOD(hide) {
    [self terminateWithError:nil dismissing:YES animated:YES];
}

RCT_EXPORT_METHOD(showUrl:(NSString *)urlString callback:(RCTResponseSenderBlock)callback) {
    [self presentSafariWithURL:[NSURL URLWithString:urlString]];
    self.sessionCallback = callback;
}

RCT_EXPORT_METHOD(didLoadURL:(NSString *)urlString callback:(RCTResponseSenderBlock)callback) {
    [self presentSafariWithURL:[NSURL URLWithString:urlString]];
    __weak A0Auth0 *weakSelf = self;
    self.didLoadCallback = ^void(NSArray *response) {
        [weakSelf.last.presentingViewController dismissViewControllerAnimated:NO completion:nil];
        callback(response);
    };
}

RCT_EXPORT_METHOD(oauthParameters:(RCTResponseSenderBlock)callback) {
    callback(@[[self generateOAuthParameters]]);
}

- (NSDictionary *)constantsToExport {
    return @{ @"bundleIdentifier": [[NSBundle mainBundle] bundleIdentifier] };
}

#pragma mark - Internal methods

- (void)presentSafariWithURL:(NSURL *)url {
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    SFSafariViewController *controller = [[SFSafariViewController alloc] initWithURL:url];
    controller.delegate = self;
    [self terminateWithError:RCTMakeError(@"Only one Safari can be visible", nil, nil) dismissing:YES animated:NO];
    [window.rootViewController presentViewController:controller animated:YES completion:nil];
    self.last = controller;
}

- (void)terminateWithError:(id)error dismissing:(BOOL)dismissing animated:(BOOL)animated {
    RCTResponseSenderBlock callback = self.sessionCallback ? self.sessionCallback : ^void(NSArray *_unused) {};
    if (dismissing) {
        [self.last.presentingViewController dismissViewControllerAnimated:animated
                                                               completion:^{
                                                                   if (error) {
                                                                       callback(@[error]);
                                                                   }
                                                               }];
    } else if (error) {
        callback(@[error]);
    }
    self.sessionCallback = nil;
    self.last = nil;
}

- (NSString *)randomValue {
    NSMutableData *data = [NSMutableData dataWithLength:32];
    int result __attribute__((unused)) = SecRandomCopyBytes(kSecRandomDefault, 32, data.mutableBytes);
    NSString *value = [[[[data base64EncodedStringWithOptions:0]
                         stringByReplacingOccurrencesOfString:@"+" withString:@"-"]
                        stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
                       stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"="]];
    return value;
}

- (NSString *)sign:(NSString*)value {
    CC_SHA256_CTX ctx;

    uint8_t * hashBytes = malloc(CC_SHA256_DIGEST_LENGTH * sizeof(uint8_t));
    memset(hashBytes, 0x0, CC_SHA256_DIGEST_LENGTH);

    NSData *valueData = [value dataUsingEncoding:NSUTF8StringEncoding];

    CC_SHA256_Init(&ctx);
    CC_SHA256_Update(&ctx, [valueData bytes], (CC_LONG)[valueData length]);
    CC_SHA256_Final(hashBytes, &ctx);

    NSData *hash = [NSData dataWithBytes:hashBytes length:CC_SHA256_DIGEST_LENGTH];

    if (hashBytes) {
        free(hashBytes);
    }

    return [[[[hash base64EncodedStringWithOptions:0]
              stringByReplacingOccurrencesOfString:@"+" withString:@"-"]
             stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
            stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"="]];
}

- (NSDictionary *)generateOAuthParameters {
    NSString *verifier = [self randomValue];
    return @{
             @"verifier": verifier,
             @"code_challenge": [self sign:verifier],
             @"code_challenge_method": @"S256",
             @"state": [self randomValue]
             };
}

#pragma mark - SFSafariViewControllerDelegate

- (void)safariViewControllerDidFinish:(SFSafariViewController *)controller {
    NSDictionary *error = @{
                            @"error": @"a0.session.user_cancelled",
                            @"error_description": @"User cancelled the Auth"
                            };
    [self terminateWithError:error dismissing:NO animated:NO];
}

- (void)safariViewController:(SFSafariViewController *)controller didCompleteInitialLoad:(BOOL)didLoadSuccessfully {
    if (self.didLoadCallback) {
        NSArray *response = didLoadSuccessfully ? @[[NSNull null]] : @[@{@"error": @"failed to load url"}];
        self.didLoadCallback(response);
        self.didLoadCallback = nil;
    } else if (!didLoadSuccessfully) {
        NSDictionary *error = @{
                                @"error": @"a0.session.failed_load",
                                @"error_description": @"Failed to load authorize url"
                                };
        [self terminateWithError:error dismissing:YES animated:YES];
    }
}
@end
