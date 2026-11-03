/**************************************************************************/
/*  apple_signin_delegate.mm                                              */
/**************************************************************************/
/* Copyright (c) 2025-present Vertex Ludi LTDA                            */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#import "apple_signin_delegate.h"

#include "apple_signin.h"

#import <Foundation/Foundation.h>

@implementation GodotASAuthorizationControllerDelegate

- (String) godotStringFromNSString:(NSString *)value {
	if (value == nil) {
		return "";
	}
	return value.UTF8String;
}

- (NSDictionary *) decodeWithToken:(NSString *)token {
	if (token == nil || token.length == 0) {
		return nil;
	}
	NSArray *segments = [token componentsSeparatedByString:@"."];

	if ([segments count] != 3) {
		return nil;
	}
	
	NSString *payloadSeg = segments[1];
	
	// Decode and parse payload JSON
	NSString *string = [[payloadSeg stringByReplacingOccurrencesOfString:@"-" withString:@"+"]
			  stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
	
	int size = [string length] % 4;
	NSMutableString *segment = [[NSMutableString alloc] initWithString:string];
	for (int i = 0; i < size; i++) {
		[segment appendString:@"="];
	}
	
	NSData *jsonData = [[NSData alloc] initWithBase64EncodedString:segment options:0];
	
	NSError *error;
	
	NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableLeaves error:&error];
	
	return payload;
}


- (void) authorizationController:(ASAuthorizationController *) controller
	didCompleteWithAuthorization:(ASAuthorization *) authorization {
	
	ASAuthorizationAppleIDCredential *credentials = (ASAuthorizationAppleIDCredential *)authorization.credential;
	NSPersonNameComponentsFormatter *formatter = [[NSPersonNameComponentsFormatter alloc] init];
	
	NSString *raw_jwt = [[NSString alloc] initWithData:credentials.identityToken encoding:NSUTF8StringEncoding] ?: @"";
	NSString *auth_code = [[NSString alloc] initWithData:credentials.authorizationCode encoding:NSUTF8StringEncoding] ?: @"";
	NSString *name = [formatter stringFromPersonNameComponents:credentials.fullName] ?: @"";
	NSString *email = credentials.email ?: @"";
		
	Dictionary data;
	data["id"] = [self godotStringFromNSString:credentials.user];
	data["name"] = [self godotStringFromNSString:name];
	data["email"] = [self godotStringFromNSString:email];
	data["identity_token"] = [self godotStringFromNSString:raw_jwt];
	data["authorization_code"] = [self godotStringFromNSString:auth_code];
	
	Dictionary jwt_dict;
	NSDictionary *jwt = [self decodeWithToken:raw_jwt];
	
	if (jwt != nil) {
		for (NSString *key in jwt) {
			NSString *value = [NSString stringWithFormat:@"%@", jwt[key]];
			jwt_dict[key.UTF8String] = value.UTF8String;
		}
	}
	
	data["jwt"] = jwt_dict;
	
	godotClass->auth_callback(data);
}

- (void) authorizationController:(ASAuthorizationController *) controller
			didCompleteWithError:(NSError *) error {
	
	String code;
	
	switch (error.code) {
		case ASAuthorizationError::ASAuthorizationErrorCanceled:
			code = "canceled";
			break;
		case ASAuthorizationError::ASAuthorizationErrorFailed:
			code = "failed";
			break;
		case ASAuthorizationError::ASAuthorizationErrorInvalidResponse:
			code = "invalidResponse";
			break;
		case ASAuthorizationError::ASAuthorizationErrorNotHandled:
			code = "notHandled";
			break;
		case ASAuthorizationError::ASAuthorizationErrorNotInteractive:
			code = "notInteractive";
			break;
		case ASAuthorizationError::ASAuthorizationErrorMatchedExcludedCredential:
			code = "matchedExcludedCredential";
			break;
		case ASAuthorizationError::ASAuthorizationErrorCredentialImport:
			code = "credentialImport";
			break;
		case ASAuthorizationError::ASAuthorizationErrorCredentialExport:
			code = "credentialExport";
			break;
		default:
			code = "unknown";
			break;
	}
	
	godotClass->auth_failed_callback(code);
}

@end
