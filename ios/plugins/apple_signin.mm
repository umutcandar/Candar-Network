/**************************************************************************/
/*  apple_signin.mm                                                       */
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

#include "apple_signin.h"

#import "apple_signin_delegate.h"

#include "core/variant/dictionary.h"

@import AuthenticationServices;

void GodotAppleSignIn::_bind_methods() {
	ClassDB::bind_method(D_METHOD("initiate_signin"), &GodotAppleSignIn::initiate_signin);
	ClassDB::bind_method(D_METHOD("request_credential_state", "user_id"), &GodotAppleSignIn::request_credential_state);

	ADD_SIGNAL(MethodInfo("signin_completed", PropertyInfo(Variant::DICTIONARY, "data"), PropertyInfo(Variant::STRING, "error")));
	ADD_SIGNAL(MethodInfo("state_received", PropertyInfo(Variant::STRING, "state")));
}

void GodotAppleSignIn::initiate_signin() {
	ASAuthorizationAppleIDProvider *appleIdProvider = [ASAuthorizationAppleIDProvider alloc];
	
	ASAuthorizationAppleIDRequest *request = appleIdProvider.createRequest;
	request.requestedScopes = @[@"full_name", @"email"];
	
	ASAuthorizationController *controller = [[ASAuthorizationController alloc] initWithAuthorizationRequests:@[request]];
	controller.delegate = signInDelegate;
	[controller performRequests];
}

void GodotAppleSignIn::request_credential_state(const String &userId) {
	ASAuthorizationAppleIDProvider *appleIdProvider = [ASAuthorizationAppleIDProvider alloc];

	[appleIdProvider getCredentialStateForUserID:[NSString stringWithUTF8String:userId.utf8().get_data()] completion:^(ASAuthorizationAppleIDProviderCredentialState credentialState, NSError * error) {
		
		String state;
		switch (credentialState) {
			case ASAuthorizationAppleIDProviderCredentialRevoked:
				state = "revoked";
				break;
			case ASAuthorizationAppleIDProviderCredentialAuthorized:
				state = "authorized";
				break;
			case ASAuthorizationAppleIDProviderCredentialNotFound:
				state = "notFound";
				break;
			case ASAuthorizationAppleIDProviderCredentialTransferred:
				state = "transferred";
				break;
			default:
				state = "unknown";
				break;
				
		}
		
		call_deferred("emit_signal", "state_received", state);
	}];
}

void GodotAppleSignIn::auth_callback(const Dictionary &data) {
	emit_signal("signin_completed", data, "");
}

void GodotAppleSignIn::auth_failed_callback(const String &error) {
	emit_signal("signin_completed", Dictionary(), error);
}

GodotAppleSignIn::GodotAppleSignIn() {
	signInDelegate = [[GodotASAuthorizationControllerDelegate alloc] init];
	signInDelegate->godotClass = this;
}

GodotAppleSignIn::~GodotAppleSignIn() {
	if (signInDelegate) {
		signInDelegate = nil;
	}
}
